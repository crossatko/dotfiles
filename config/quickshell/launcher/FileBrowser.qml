import QtQuick
import Quickshell
import Quickshell.Io
import "js/Fs.js" as Fs

// Source: the file browser, one instance per mode (`mode`, defined in js/Fs.js MODES; declared in Launcher.qml):
//  - browse:   "/..." or "~/..." lists that folder; Enter on a folder descends (row `descend`, Launcher.runItem), on a file opens it
//  - find:     "f <text>": name search under $HOME, 200 ms after the last keystroke, results streamed in
//  - projects: "code <text>" / "c <text>": the projects under ~/code ($QS_CODE_ROOT), Enter opens them in zellij
// The modes differ only in their Fs.MODES entry (query match, lister, freshness, rows); listing, caching, process handling and
// the row actions are this file. Enter = xdg-open (or code-open for project rows), Ctrl+Enter (row `alt`) = open in the
// dedicated zellij session via bin/code-open (folder: a tab there; text file: a tab in its folder running the editor).
// Item actions (Ctrl+K / Right) depend on the file type (Fs.actionsFor). No destructive actions.
QtObject {
    id: src

    property string mode: "browse"
    property bool active: false                    // launcher shown: per-open listings (projects) are listed again on the next open
    signal updated()

    readonly property var items: []
    readonly property var spec: Fs.MODES[mode]
    readonly property string modeTitle: spec.title   // launcher header in prefix mode
    readonly property string modeGlyph: spec.glyph
    readonly property string home: Quickshell.env("HOME")
    readonly property string codeRoot: Quickshell.env("QS_CODE_ROOT") || home + "/code"
    readonly property string codeOpen: String(Qt.resolvedUrl("bin/code-open")).replace(/^file:\/\//, "")

    function match(q, raw) { return spec.match(q, raw, home, codeRoot) }
    function exclusive(q, raw) { return match(q, raw) !== null }

    function dynamic(q, raw) {
        const p = match(q, raw)
        if (p === null) { wanted = ""; return [] }
        if (spec.readLine) return search(p)
        request(p.base)
        return listing.base === p.base ? spec.rows(listing, p, home) : []
    }

    // Tab in a path query (browse mode): the completed text (Fs.completePath against the current listing), or null.
    // row = the selected row, taken when nothing is typed after the last "/" ("Open folder" is no entry).
    function complete(text, row) {
        const p = mode === "browse" ? match(text.trim(), text) : null
        if (p === null || listing.base !== p.base || !listing.ok) return null
        const sel = row && row.kind === "file" && row.id !== "file:open:" + row.path ? { name: Fs.baseName(row.path), dir: row.isDir } : null
        return Fs.completePath(text, listing.entries, sel)
    }

    onActiveChanged: { lastReq = { base: "", at: 0 }; if (!active) { wanted = ""; stop() } }

    // ---- one-shot listers (folder, projects): the whole NUL-separated output at once, fresh for spec.ttl per base -----------
    property var listing: ({ base: "", entries: [], ok: false })   // last finished listing
    property var lastReq: ({ base: "", at: 0 })
    property string queued: ""
    property string loading: ""

    function request(base) {
        const now = Date.now()
        if (lastReq.base === base && now - lastReq.at < spec.ttl) return
        lastReq = { base: base, at: now }
        if (lister.running) { queued = base; return }
        startList(base)
    }

    function startList(base) {
        loading = base; queued = ""; listDone = 0
        lister.command = spec.argv(base)
        lister.running = true
    }

    function finishList(text, code) {
        const es = spec.read(text, loading)
        listing = { base: loading, entries: es, ok: code === 0 || es.length > 0 }
        lastReq = { base: lastReq.base, at: Date.now() }
        if (queued !== "" && queued !== loading) startList(queued)
        queued = ""
        updated()
    }

    // SplitParser cannot split on NUL, so collect everything. The collector's end of stream and the exit code arrive in
    // either order: publish when both are in.
    property int listDone: 0
    property int listCode: 0
    property string listText: ""
    property var lister: Process {
        stdout: StdioCollector {
            onStreamFinished: { src.listText = text; if (++src.listDone === 2) src.finishList(src.listText, src.listCode) }
        }
        onExited: code => { src.listCode = code; if (++src.listDone === 2) src.finishList(src.listText, code) }
    }

    // ---- streamed lister (find): started 200 ms after the last keystroke, published at most every 120 ms, max 400 read ----
    property string wanted: ""
    property string wantedBase: ""
    property string runningFor: ""
    property string shownFor: ""
    property var found: []
    property var buf: []

    function search(p) {
        if (p.text.length < spec.minText) { wanted = ""; stop(); return [] }
        if (p.text !== wanted) { wanted = p.text; wantedBase = p.base; stop(); debounce.restart() }
        return shownFor === p.text ? spec.rows({ base: p.base, entries: found, ok: true }, p, home) : []
    }

    function stop() { debounce.stop(); if (searcher.running) searcher.running = false }

    property var debounce: Timer {
        interval: 200
        onTriggered: {
            if (src.wanted === "") return
            src.found = []; src.buf = []
            src.runningFor = src.wanted
            src.searcher.command = src.spec.argv(src.wantedBase, src.wanted)
            src.searcher.running = true
        }
    }

    property var searcher: Process {
        stdout: SplitParser {
            onRead: line => {
                if (src.buf.length >= 400) return
                const e = src.spec.readLine(line)
                if (e) { src.buf.push(e); src.pub.restart() }
            }
        }
        onExited: src.pub.restart()
    }

    property var pub: Timer {
        interval: 120
        onTriggered: { src.found = src.buf.slice(); src.shownFor = src.runningFor; src.updated() }
    }

    // ---- actions (every file row, whichever mode made it) ------------------------------------------------------------
    function zellij(item) { Quickshell.execDetached([codeOpen, Fs.zellijTarget(item)]) }

    function run(item) {
        if (item.kind !== "file") return false
        if (item.zellij) zellij(item)
        else Quickshell.execDetached(["xdg-open", item.path])
        return true
    }

    function sh(script, ...args) { Quickshell.execDetached(["sh", "-c", script, "sh"].concat(args)) }

    function action(id, item) {
        if (item.kind !== "file") return false
        const p = item.path
        if (id === "zellij") {
            zellij(item)
        } else if (id === "copypath") {
            sh("printf '%s' \"$1\" | wl-copy; notify-send -a Launcher 'Copied path' \"$1\"", p)
        } else if (id === "openfolder") {
            Quickshell.execDetached(["xdg-open", p])
        } else if (id === "showfolder" || id === "folder") {
            Quickshell.execDetached(["nautilus", "--select", p])
        } else if (id === "term") {
            Quickshell.execDetached(["ghostty", "--working-directory=" + p])
        } else if (id === "edit") {
            sh("exec ghostty --working-directory=\"$(dirname -- \"$1\")\" -e \"${EDITOR:-nvim}\" \"$1\"", p)
        } else if (id === "mpv") {
            Quickshell.execDetached(["mpv", "--", p])
        } else if (id === "copyfile") {
            sh("wl-copy --type \"$(file -b --mime-type -- \"$1\")\" < \"$1\" && notify-send -a Launcher 'Copied to clipboard' \"$(basename -- \"$1\")\"", p)
        } else if (id === "wallpaper") {   // full theme apply (wallpaper + colours + app reloads); images and videos
            sh("notify-send -a Launcher 'Applying wallpaper' \"$(basename -- \"$2\")\"; exec python3 -I \"$1\" apply \"$2\"",
                home + "/.config/theme/theme.py", p)
        } else return false
        return true
    }
}
