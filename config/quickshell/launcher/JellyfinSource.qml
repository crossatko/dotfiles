import QtQuick
import Quickshell
import Quickshell.Io
import "js/Ranker.js" as Ranker

// Source: Jellyfin (movies, shows, music) through the helper CLI `jellyfin-qs` (config/launcher/jellyfin/, installed to
// ~/.local/bin). QML never sees tokens: data commands print a JSON array on stdout, one line on stderr on error;
// exit 0 ok, 2 not configured / token rejected, 3 network / server error, 4 not found, 127 helper not installed.
// Two entry points, both owned by this file:
//   - the "jellyfin" section (root row in SectionsSource, which delegates header / glyph / enter to `jf`): menu rows
//     (Continue watching, Next up, Recently added, Libraries, Playlists), live search while typing, nested levels
//     (`children <id>`: library -> items, series -> seasons -> episodes, artist -> albums -> tracks, playlist -> items);
//   - the exclusive prefix mode "jf <text>" in the main list (search only; Right browses via the same nested levels).
// All rows are transient + private (never in usage.json / history.json). Every request is an async Process with a token;
// a newer request kills the older one and stale exits are ignored. Search is debounced (250 ms), one request per query,
// no automatic retry. The helper is resolved from PATH, then ~/.local/bin (Quickshell's PATH may lack it).
QtObject {
    id: src

    signal updated()

    readonly property var items: []                 // nothing in the normal list (the root row lives in SectionsSource)
    readonly property string modeTitle: "Jellyfin"  // launcher header in the "jf " prefix mode
    readonly property string modeGlyph: ""

    // ---- state -----------------------------------------------------------------------------------------------------
    property var stack: []                          // nested levels: {title, sub, glyph, args, query, selId, state, rows, code, err}
    readonly property int depth: stack.length
    property bool fromPrefix: false                 // the nested levels were entered from the "jf " prefix mode (leaving the last one returns there)
    property string lastRaw: ""                     // raw filter text / section of the last track() (for push + retry)
    property string lastSection: ""

    property int statusCode: -1                     // -1 = pending, 0 ok, else the exit code of `status`
    property string statusErr: ""
    property string user: ""

    property string searchKey: ""
    property string searchState: "idle"             // idle | loading | ok | error
    property var searchRows: []
    property int searchCode: 0
    property string searchErr: ""

    property int statusTok: 0
    property int searchTok: 0
    property int levelTok: 0
    property var statusProc: null
    property var searchProc: null
    property var levelProc: null

    // ---- helpers -----------------------------------------------------------------------------------------------------
    readonly property string wrap: 'PATH="$PATH:$HOME/.local/bin"; exec jellyfin-qs "$@"'
    function argv(args) { return ["sh", "-c", wrap, "sh"].concat(args) }

    function errLine(err) {
        return (err || "").trim().split("\n")[0].replace(/[A-Za-z0-9_\-]{30,}/g, "***").slice(0, 160)
    }
    function validId(id) { return /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/.test(String(id)) }

    function info(id, name, sub, glyph) {
        return { id: "sec:jf:" + id, name: name, subtitle: sub, kind: "info", source: "", glyph: glyph, transient: true, private: true }
    }
    function actionRow(id, kind, name, sub, glyph) {
        return { id: "sec:jf:" + id, name: name, subtitle: sub, kind: kind, source: "", glyph: glyph, transient: true, private: true }
    }

    function errRows(code, err) {
        const l = errLine(err)
        if (code === 2) return [info("auth", "Not logged in to Jellyfin", l, ""),
                                info("auth-how", "Run `jellyfin-qs login` in a terminal", "", ""),
                                actionRow("login", "jf-login", "Open login in terminal", "kitty -e jellyfin-qs login", "")]
        if (code === 3) return [info("net", "Jellyfin server unreachable (is Tailscale connected?)", l, ""),
                                actionRow("retry", "jf-retry", "Try again", "", "")]
        if (code === 127) return [info("missing", "jellyfin-qs not found: run install.sh", "", "")]
        if (code === 4) return [info("nf", "Not found on the Jellyfin server", l, "")]
        return [info("err", "Could not load Jellyfin", l !== "" ? l : "exit code " + code, ""),
                actionRow("retry", "jf-retry", "Try again", "", "")]
    }

    // ---- rows -------------------------------------------------------------------------------------------------------
    readonly property var typeLabels: ({
        Movie: "Movie", Series: "Series", Season: "Season", Episode: "Episode", MusicArtist: "Artist", MusicAlbum: "Album",
        Audio: "Track", Playlist: "Playlist", CollectionFolder: "Library", Folder: "Folder", BoxSet: "Collection", MusicVideo: "Music video"
    })
    readonly property var groupOrder: ["Movie", "Series", "Episode", "MusicArtist", "MusicAlbum", "Audio", "Playlist"]
    function typeLabel(t) { return typeLabels[t] || t || "" }

    function glyphFor(it) {
        const ct = it.collection_type
        if (ct) return ct === "movies" ? "" : ct === "tvshows" ? "" : ct === "music" ? "" : ""
        switch (it.type) {
        case "Movie": return ""
        case "Series": case "Season": return ""
        case "Episode": case "MusicVideo": return ""
        case "MusicArtist": return ""
        case "MusicAlbum": return "\uf025"
        case "Audio": return ""
        case "Playlist": return "\uf0ca"
        }
        return it.kind === "audio" ? "" : it.kind === "video" ? "" : ""
    }
    function clock(s) {
        s = Math.max(0, Math.floor(s))
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60
        return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (x < 10 ? "0" : "") + x
    }
    function runtimeText(s) {
        const m = Math.round(s / 60)
        return m < 60 ? Math.max(1, m) + " min" : Math.floor(m / 60) + "h" + (m % 60 < 10 ? "0" : "") + (m % 60) + "m"
    }
    // right-hand hint: remaining / resume position, a tick when played, else the runtime
    function hintOf(it) {
        if (it.played) return "✓"
        const rs = Number(it.resume_s) || 0, rt = Number(it.runtime_s) || 0
        if (it.kind === "video" && rs > 0) return rt > rs ? Math.max(1, Math.round((rt - rs) / 60)) + " min left" : "Resume " + clock(rs)
        return rt > 0 ? runtimeText(rt) : ""
    }
    function isMusicContainer(t) { return t === "MusicArtist" || t === "MusicAlbum" || t === "Playlist" }

    function itemRow(it, search) {
        const id = String(it.id === undefined ? "" : it.id)
        if (!validId(id)) return null
        const playable = it.playable === true, browsable = it.browsable === true
        const resume = it.kind === "video" && (Number(it.resume_s) || 0) > 0
        const parts = []
        if (search && it.type) parts.push(typeLabel(it.type))
        const sub = it.subtitle ? String(it.subtitle) : ""
        if (sub) parts.push(sub)
        if (it.year && sub.indexOf(String(it.year)) < 0) parts.push(String(it.year))
        const pct = Number(it.progress_pct) || 0
        if (pct > 0 && pct < 100 && !it.played) parts.push(Math.round(pct) + "%")
        const acts = []
        if (playable && resume) acts.push({ id: "jf-play-start", label: "Play from start", glyph: "" })
        if (playable && browsable && isMusicContainer(it.type)) acts.push({ id: "jf-shuffle", label: "Shuffle", glyph: "" })
        if (browsable && playable) acts.push({ id: "jf-browse", label: "Browse", glyph: "" })
        if (browsable && it.collection_type) acts.push({ id: "jf-latest", label: "Recently added", glyph: "" })
        return {
            id: "sec:jf:" + id, name: String(it.name || "Untitled"), subtitle: parts.join("  ·  "),
            kind: playable ? "jf" : browsable ? "jf-nav" : "info", source: hintOf(it), glyph: glyphFor(it),
            iconColor: it.played ? "muted" : "", transient: true, private: true,
            keywords: it.parent_name ? [String(it.parent_name)] : [],
            runLabel: playable ? (resume ? "Resume" : "Play") : "Open", actions: acts,
            jfId: id, jfType: String(it.type || ""), jfKind: String(it.kind || ""), jfResume: resume, jfBrowsable: browsable
        }
    }
    // JSON array -> rows (null when the text is not one); search results are grouped Movies, Series, Episodes, Artists, Albums, Tracks, Playlists
    function parseItems(text, search) {
        let arr
        try { arr = JSON.parse(text) } catch (e) { return null }
        if (!Array.isArray(arr)) return null
        const buckets = {}, rest = []
        for (const it of arr) {
            if (!it || typeof it !== "object") continue
            const row = itemRow(it, search)
            if (!row) continue
            if (search && groupOrder.indexOf(it.type) >= 0) (buckets[it.type] = buckets[it.type] || []).push(row)
            else rest.push(row)
        }
        if (!search) return rest
        let out = []
        for (const g of groupOrder) if (buckets[g]) out = out.concat(buckets[g])
        return out.concat(rest)
    }

    readonly property var menuRows: [
        menuRow("resume", "Continue watching", "Resume where you left off", "", ["resume"]),
        menuRow("nextup", "Next up", "The next unwatched episodes", "", ["nextup"]),
        menuRow("latest", "Recently added", "New movies, shows and music", "", ["latest"]),
        menuRow("libraries", "Libraries", "Browse by library", "", ["libraries"]),
        menuRow("playlists", "Playlists", "Your playlists", "", ["playlists"])
    ]
    function menuRow(id, name, sub, glyph, args) {
        return { id: "sec:jf:menu:" + id, name: name, subtitle: sub, kind: "jf-nav", source: "", glyph: glyph, transient: true, private: true,
                 jfMenu: true, jfArgs: args }
    }

    // ---- what the launcher shows ------------------------------------------------------------------------------------
    function header() { return depth > 0 ? stack[depth - 1].title : "Jellyfin" }
    function headerSub() {
        if (depth > 0) return stack[depth - 1].sub
        return statusCode === 0 ? user : ""
    }
    function glyph() { return depth > 0 ? stack[depth - 1].glyph : "" }
    function rightHintFor(it) { return it && (it.kind === "jf-nav" || (it.actions && it.actions.some(a => a.id === "jf-browse"))) }

    function searchList() {
        if (searchState === "loading") return [info("searching", "Searching Jellyfin...", "", "")]
        if (searchState === "error") return errRows(searchCode, searchErr)
        if (searchRows.length === 0) return [info("none", "No results", searchKey, "")]
        return searchRows
    }
    // section view: nested level (local filter), else menu / error rows when the filter is empty, else the server search
    function listFor(q) {
        if (depth > 0) {
            const lv = stack[depth - 1]
            if (lv.state === "loading") return [info("loading", "Loading...", "", "")]
            if (lv.state === "error") return errRows(lv.code, lv.err)
            if (lv.rows.length === 0) return [info("empty", "Nothing here", "", "")]
            return q === "" ? lv.rows : Ranker.rank(lv.rows, q, {}, Date.now(), { limit: 50 }).map(r => r.item)
        }
        if (statusCode > 0) return errRows(statusCode, statusErr)
        if (q === "") return menuRows
        return searchList()
    }

    // ---- prefix mode ("jf <text>", only with the space) -------------------------------------------------------------
    function prefixText(raw) {
        const m = typeof raw === "string" ? /^jf (.*)$/i.exec(raw) : null
        return m ? m[1].trim() : null
    }
    function exclusive(q, raw) { return prefixText(raw) !== null }
    function dynamic(q, raw) {
        const t = prefixText(raw)
        if (t === null) return []
        if (t === "") return [info("hint", "Search Jellyfin", "Type a title, artist or album", "")].concat(menuRows)
        return searchList()
    }

    // ---- processes -------------------------------------------------------------------------------------------------
    property Component procComp: Component {
        Process {
            id: p
            property string kind: ""
            property int token: 0
            stdout: StdioCollector { id: o }
            stderr: StdioCollector { id: e }
            onExited: code => src.finished(p, code, o.text, e.text)
        }
    }
    function spawn(kind, token, args) {
        const p = procComp.createObject(src, { kind: kind, token: token, command: argv(args) })
        p.running = true
        return p
    }
    function kill(p) { if (p) p.running = false }

    function finished(p, code, out, err) {
        const k = p.kind, tok = p.token
        if (statusProc === p) statusProc = null
        if (searchProc === p) searchProc = null
        if (levelProc === p) levelProc = null
        p.destroy(50)
        if (k === "play") { if (code !== 0) toast(code, err); return }
        if (k === "status") {
            if (tok !== statusTok) return
            statusCode = code; statusErr = err
            user = ""
            if (code === 0) { try { user = String(JSON.parse(out).user || "") } catch (x) {} }
        } else if (k === "search") {
            if (tok !== searchTok) return
            const rows = code === 0 ? parseItems(out, true) : null
            if (code === 0 && rows === null) { searchState = "error"; searchCode = 1; searchErr = "Unexpected output from jellyfin-qs" }
            else if (code === 0) { searchState = "ok"; searchRows = rows }
            else { searchState = "error"; searchCode = code; searchErr = err }
        } else if (k === "level") {
            if (tok !== levelTok || depth === 0) return
            const rows = code === 0 ? parseItems(out, false) : null
            if (code === 0 && rows === null) setTop({ state: "error", code: 1, err: "Unexpected output from jellyfin-qs" })
            else if (code === 0) setTop({ state: "ok", rows: rows })
            else setTop({ state: "error", code: code, err: err })
        }
        updated()
    }
    function setTop(o) { stack = stack.slice(0, -1).concat([Object.assign({}, stack[stack.length - 1], o)]) }

    function toast(code, err) {
        let m = code === 127 ? "jellyfin-qs not found: run install.sh" : errLine(err)
        if (m === "") m = "jellyfin-qs play failed (exit " + code + ")"
        if (code === 3 && m.indexOf("Tailscale") < 0) m += " (is Tailscale connected?)"
        Quickshell.execDetached(["notify-send", "-a", "Launcher", "Jellyfin", m])
    }

    // ---- lifecycle ----------------------------------------------------------------------------------------------------
    function reset() {
        kill(searchProc); kill(levelProc); kill(statusProc)
        searchTok++; levelTok++; statusTok++
        debounce.stop()
        stack = []; fromPrefix = false
        searchKey = ""; searchState = "idle"; searchRows = []
    }
    function checkStatus() {
        kill(statusProc)
        statusCode = -1; statusErr = ""; user = ""
        statusProc = spawn("status", ++statusTok, ["status", "--json"])
    }
    function enter() {          // section opened
        reset()
        checkStatus()
    }

    // ---- search (called from Launcher.onQueryChanged) ------------------------------------------------------------------
    function cancelSearch(keepResult) {
        debounce.stop()
        if (searchState === "loading") { kill(searchProc); searchTok++; searchState = "idle"; searchKey = "" }
        else if (!keepResult) { searchState = "idle"; searchKey = "" }
    }
    function track(raw, section) {
        lastRaw = raw; lastSection = section
        let t = null
        if (section === "jellyfin" && depth === 0) t = raw.trim()
        else if (section === "") { t = prefixText(raw); if (t === null && depth > 0) { kill(levelProc); levelTok++; stack = []; fromPrefix = false } }
        if (t === null) { cancelSearch(section === "jellyfin"); return }
        t = t.replace(/^-+/, "")
        if (t === "") { cancelSearch(false); return }
        if (t === searchKey && searchState !== "idle") return
        kill(searchProc); searchTok++
        searchKey = t; searchState = "loading"
        debounce.restart()
    }
    property Timer debounce: Timer {
        interval: 250
        onTriggered: {
            if (src.searchState !== "loading") return
            src.searchProc = src.spawn("search", src.searchTok, ["search", src.searchKey, "--limit", "40"])
        }
    }

    // ---- nested levels ------------------------------------------------------------------------------------------------
    function pushLevel(title, sub, glyph, args, selId) {
        if (depth === 0) fromPrefix = lastSection === ""
        kill(levelProc)
        stack = stack.concat([{ title: title, sub: sub, glyph: glyph, args: args, query: lastRaw, selId: selId, state: "loading", rows: [], code: 0, err: "" }])
        levelProc = spawn("level", ++levelTok, args)
    }
    // one level back: returns the filter text and the selected row id to restore in the parent view
    function pop() {
        kill(levelProc); levelTok++
        const top = stack[stack.length - 1]
        stack = stack.slice(0, -1)
        return { text: top.query, selId: top.selId }
    }
    function refetchTop() {
        if (depth === 0) return
        kill(levelProc)
        setTop({ state: "loading", code: 0, err: "" })
        levelProc = spawn("level", ++levelTok, stack[depth - 1].args)
    }
    function retry() {
        if (depth > 0) refetchTop()
        else if (statusCode > 0) checkStatus()
        else { searchState = "idle"; searchKey = ""; track(lastRaw, lastSection) }
    }

    // ---- actions / run -------------------------------------------------------------------------------------------------
    function play(args) {
        spawn("play", 0, ["play"].concat(args))
    }
    // item actions (Launcher.doAction): true = done and close, "enter" = a nested level was pushed, "keep" = redraw, false = not ours
    function action(id, item) {
        if (id === "jf-retry") { retry(); return "keep" }
        if (!item || !/^jf/.test(item.kind || "")) return false
        if (id === "jf-browse") {
            if (item.jfMenu) pushLevel(item.name, "", item.glyph, item.jfArgs, item.id)
            else if (item.jfBrowsable && validId(item.jfId)) pushLevel(item.name, typeLabel(item.jfType), item.glyph, ["children", item.jfId], item.id)
            else return false
            return "enter"
        }
        if (id === "jf-latest" && validId(item.jfId)) { pushLevel(item.name, "Recently added", "", ["latest", "--library", item.jfId], item.id); return "enter" }
        if (!validId(item.jfId)) return false
        if (id === "jf-play-start") { play([item.jfId]); return true }
        if (id === "jf-shuffle") { play([item.jfId, "--shuffle"]); return true }
        return false
    }
    function run(item) {
        if (item.kind === "jf") {
            if (!validId(item.jfId)) return true
            play(item.jfResume ? [item.jfId, "--resume"] : [item.jfId])
            return true
        }
        if (item.kind === "jf-login") {
            Quickshell.execDetached(["kitty", "-e", "sh", "-c", 'PATH="$PATH:$HOME/.local/bin"; exec jellyfin-qs login'])
            return true
        }
        return false
    }
}
