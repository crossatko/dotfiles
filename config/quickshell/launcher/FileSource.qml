import QtQuick
import Quickshell
import Quickshell.Io

// Source: files. Two prefix modes:
//  - path browsing: a query starting with "/" or "~/" lists that folder (up to the last "/"; the text after it filters
//    the entries). First row "Open folder", then folders, then files (hidden entries only when the filter starts with ".").
//    One one-shot `find -maxdepth 1` (argv, NUL-separated) per folder, cached 2 s; Enter on a folder descends (see
//    `descend`, handled in Launcher.runItem), Enter on a file opens it with xdg-open. Max 500 rows.
//  - name search: "f <text>": `timeout 3 find` under $HOME 200 ms after the last keystroke (depth <= 6, skips .git,
//    node_modules, .cache, Steam, wine prefixes; at most 30 results, shallowest first).
// Item actions (Ctrl+K / Right) depend on the file type, see actionsFor(). No destructive actions.
QtObject {
    id: src

    signal updated()

    readonly property var items: []
    readonly property string modeTitle: "Files"   // launcher header in prefix mode
    readonly property string modeGlyph: "\uf07b"
    readonly property string home: Quickshell.env("HOME")
    property string wanted: ""
    property string running_q: ""
    property var found: []                 // {type, path}
    property string shownFor: ""

    function pattern(q) {
        let t = q
        if (/^f\s/.test(t)) t = t.slice(2)
        else return null
        return t.trim()
    }

    // path browsing: {dir (with trailing "/"), filter} or null
    function browse(q) {
        let t = q
        if (t.startsWith("~/")) t = home + t.slice(1)
        else if (!t.startsWith("/")) return null
        const i = t.lastIndexOf("/")
        return { dir: t.slice(0, i + 1), filter: t.slice(i + 1) }
    }

    function exclusive(q) { return browse(q) !== null || pattern(q) !== null }

    property var listed: ({ dir: "", entries: [], ok: false })   // last finished listing
    property var lastReq: ({ dir: "", at: 0 })
    property string queued: ""
    property string loadDir: ""
    property var lbuf: []

    function human(n) {
        const u = ["B", "KB", "MB", "GB", "TB"]
        let i = 0
        while (n >= 1024 && i < u.length - 1) { n /= 1024; i++ }
        return (i === 0 ? n : n.toFixed(n < 10 ? 1 : 0)) + " " + u[i]
    }

    readonly property var exts: ({
        image: "png jpg jpeg webp gif bmp avif tif tiff svg ico heic jxl",
        video: "mp4 webm mkv mov avi m4v wmv flv ogv ts",
        audio: "mp3 flac ogg opus wav m4a aac",
        text: "txt md log csv ini conf cfg toml yaml yml json xml lua py js mjs sh zsh bash fish qml css html htm c h cpp hpp rs go java rb php nix kdl rasi tex diff patch service desktop",
        code: "lua py js mjs sh zsh bash fish qml css html htm c h cpp hpp rs go java rb php nix kdl rasi",
        archive: "zip tar gz xz zst bz2 7z rar",
        pdf: "pdf"
    })
    readonly property var textNames: ["makefile", "readme", "license", "dockerfile", "pkgbuild", "changelog"]

    function category(name) {
        const dot = name.lastIndexOf(".")
        const e = dot > 0 ? name.slice(dot + 1).toLowerCase() : ""
        if (e !== "") for (const k of ["image", "video", "audio", "archive", "pdf"])
            if (exts[k].split(" ").indexOf(e) >= 0) return k
        if (e !== "" && exts.code.split(" ").indexOf(e) >= 0) return "code"
        if (e !== "" && exts.text.split(" ").indexOf(e) >= 0) return "text"
        if (textNames.indexOf(name.toLowerCase()) >= 0) return "text"
        return "file"
    }

    readonly property var catInfo: ({
        image: { glyph: "\uf1c5", label: "Image" }, video: { glyph: "\uf1c8", label: "Video" },
        audio: { glyph: "\uf1c7", label: "Audio" }, code: { glyph: "\uf1c9", label: "Code" },
        text: { glyph: "\uf15c", label: "Text" }, archive: { glyph: "\uf1c6", label: "Archive" },
        pdf: { glyph: "\uf1c1", label: "PDF" }, file: { glyph: "\uf15b", label: "File" },
        dir: { glyph: "\uf07b", label: "Folder" }
    })

    // Ctrl+K entries per type; all are non-destructive. "Open" itself is the Enter action (runLabel).
    function actionsFor(cat) {
        if (cat === "dir") return [
            { id: "openfolder", label: "Open folder", glyph: "\uf07c" },
            { id: "term", label: "Open terminal here", glyph: "\uf120" },
            { id: "copypath", label: "Copy path", glyph: "\uf0c5" }
        ]
        const a = []
        if (cat === "image") {
            a.push({ id: "copyfile", label: "Copy image to clipboard", glyph: "\uf03e" })
            a.push({ id: "wallpaper", label: "Set as wallpaper (full theme apply)", glyph: "\uf53f" })
        } else if (cat === "video") {
            a.push({ id: "mpv", label: "Play in mpv", glyph: "\uf04b" })
            a.push({ id: "wallpaper", label: "Set as video wallpaper (full theme apply)", glyph: "\uf53f" })
        } else if (cat === "text" || cat === "code") {
            a.push({ id: "edit", label: "Open in editor", glyph: "\uf044" })
            a.push({ id: "copyfile", label: "Copy contents to clipboard", glyph: "\uf0ea" })
        }
        a.push({ id: "showfolder", label: "Show in folder", glyph: "\uf07c" })
        a.push({ id: "copypath", label: "Copy path", glyph: "\uf0c5" })
        return a
    }

    function tilde(p) { return p.startsWith(home + "/") ? "~" + p.slice(home.length) : p }

    function request(dir) {
        const now = Date.now()
        if (lastReq.dir === dir && now - lastReq.at < 2000) return
        lastReq = { dir: dir, at: now }
        if (listLister.running) { queued = dir; return }
        startList(dir)
    }

    function startList(dir) {
        loadDir = dir; queued = ""; lbuf = []; listDone = 0
        listLister.command = ["timeout", "3", "find", "-H", dir, "-mindepth", "1", "-maxdepth", "1", "-printf", "%Y\\t%s\\t%f\\0"]
        listLister.running = true
    }

    function finishList(code) {
        const es = lbuf.map(e => ({ dir: e.t === "d", size: e.s, name: e.n, lname: e.n.toLowerCase() }))
        es.sort((a, b) => (a.dir === b.dir ? 0 : a.dir ? -1 : 1) || a.lname.localeCompare(b.lname, undefined, { numeric: true }))
        listed = { dir: loadDir, entries: es, ok: code === 0 || es.length > 0 }
        lastReq = { dir: lastReq.dir, at: Date.now() }
        lbuf = []
        if (queued !== "" && queued !== loadDir) startList(queued)
        queued = ""
        updated()
    }

    // NUL-separated records (names may hold newlines); SplitParser cannot split on NUL, so collect everything.
    // The collector's end of stream and the exit code arrive in either order: publish when both are in.
    property int listDone: 0
    property int listCode: 0
    property var listLister: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const recs = text.split("\u0000")
                src.lbuf = []
                for (const rec of recs) {
                    const a = rec.indexOf("\t"), b = rec.indexOf("\t", a + 1)
                    if (a < 0 || b < 0) continue
                    src.lbuf.push({ t: rec.slice(0, a), s: parseInt(rec.slice(a + 1, b)) || 0, n: rec.slice(b + 1) })
                    if (src.lbuf.length >= 20000) break
                }
                if (++src.listDone === 2) src.finishList(src.listCode)
            }
        }
        onExited: code => { src.listCode = code; if (++src.listDone === 2) src.finishList(code) }
    }

    function browseItems(q, b) {
        if (listed.dir !== b.dir) return []
        if (!listed.ok) return [{ id: "file:err:" + b.dir, kind: "info", source: "", name: "Cannot read folder", subtitle: tilde(b.dir), glyph: "\uf071", transient: true }]
        const f = b.filter.toLowerCase(), hidden = f.startsWith(".")
        let es = listed.entries.map((e, i) => Object.assign({ i: i, pre: f !== "" && e.lname.startsWith(f) ? 0 : 1 }, e))
            .filter(e => (hidden ? e.lname.startsWith(f) : !e.name.startsWith(".") && (f === "" || e.lname.includes(f))))
        if (f !== "") es.sort((a, b2) => (a.dir === b2.dir ? 0 : a.dir ? -1 : 1) || a.pre - b2.pre || a.i - b2.i)
        const rows = []
        const exact = f === "" ? null : es.find(e => e.dir && e.lname === f)
        const openPath = f === "" ? b.dir : exact ? b.dir + exact.name : ""
        if (openPath !== "")
            rows.push({
                id: "file:open:" + openPath, name: "Open folder", subtitle: tilde(openPath), kind: "file", source: "Folder",
                glyph: "\uf07c", transient: true, path: openPath, isDir: true, dir: openPath,
                actions: actionsFor("dir")
            })
        const style = q.startsWith("~") ? 1 : 0
        for (const e of es.slice(0, 500)) {
            const path = b.dir + e.name
            const cat = e.dir ? "dir" : category(e.name)
            const ci = catInfo[cat]
            rows.push({
                id: "file:" + path, name: e.dir ? e.name + "/" : e.name, kind: "file", source: ci.label,
                subtitle: e.dir ? "" : human(e.size), glyph: ci.glyph, transient: true,
                path: path, isDir: e.dir, cat: cat, dir: e.dir ? path : b.dir,
                descend: e.dir ? (style ? tilde(path) : path) + "/" : undefined,
                runLabel: e.dir ? "Browse" : "Open",
                actions: actionsFor(cat)
            })
        }
        return rows
    }

    function dynamic(q) {
        const b = browse(q)
        if (b !== null) {
            wanted = ""; stop()
            request(b.dir)
            return browseItems(q, b)
        }
        const t = pattern(q)
        if (t === null) { wanted = ""; return [] }
        if (t.length < 2) { wanted = ""; stop(); return [] }
        if (t !== wanted) { wanted = t; stop(); debounce.restart() }
        if (shownFor !== t) return []
        return found.map(f => {
            const isDir = f.type === "d"
            const slash = f.path.lastIndexOf("/")
            const cat = isDir ? "dir" : category(f.path.slice(slash + 1))
            return {
                id: "file:" + f.path, name: f.path.slice(slash + 1), subtitle: tilde(f.path),
                kind: "file", source: catInfo[cat].label, glyph: catInfo[cat].glyph,
                transient: true, path: f.path, isDir: isDir, cat: cat, dir: isDir ? f.path : f.path.slice(0, slash),
                actions: actionsFor(cat)
            }
        })
    }

    function stop() { debounce.stop(); if (proc.running) proc.running = false }

    function esc(s) { return s.replace(/[\\*?\[\]]/g, "\\$&") }

    property var debounce: Timer {
        interval: 200
        onTriggered: {
            if (src.wanted === "") return
            src.found = []; src.buf = []
            src.running_q = src.wanted
            const h = src.home
            const prune = ["(", "-name", ".git", "-o", "-name", "node_modules", "-o", "-name", ".cache",
                "-o", "-name", ".steam", "-o", "-name", ".wine", "-o", "-name", "drive_c", "-o", "-name", "compatdata",
                "-o", "-name", ".cargo", "-o", "-name", ".rustup", "-o", "-name", ".npm",
                "-o", "-path", h + "/.local/share/Steam", "-o", "-path", h + "/.local/share/lutris",
                "-o", "-path", h + "/.local/share/wineprefixes", "-o", "-path", h + "/.local/share/Trash", ")", "-prune"]
            const t = src.wanted
            const test = t.indexOf("/") >= 0 ? ["-ipath", "*" + src.esc(t) + "*"] : ["-iname", "*" + src.esc(t) + "*"]
            proc.command = ["timeout", "3", "find", h, "-maxdepth", "6"].concat(prune,
                ["-o"], test, ["-printf", "%y\t%p\n"])
            proc.running = true
        }
    }

    property var buf: []

    property var proc: Process {
        stdout: SplitParser {
            onRead: line => {
                const tab = line.indexOf("\t")
                if (tab < 0 || src.buf.length >= 400) return
                src.buf.push({ type: line.slice(0, tab), path: line.slice(tab + 1) })
                pub.restart()
            }
        }
        onExited: pub.restart()
    }

    // publish at most every 120 ms: shallowest first, then by name; max 30
    property var pub: Timer {
        interval: 120
        onTriggered: {
            const depth = p => p.split("/").length
            const all = src.buf.slice().sort((a, b) => depth(a.path) - depth(b.path) || a.path.length - b.path.length)
            src.found = all.slice(0, 30)
            src.shownFor = src.running_q
            src.updated()
        }
    }

    function run(item) {
        if (item.kind !== "file") return false
        Quickshell.execDetached(["xdg-open", item.path])
        return true
    }

    function sh(script, ...args) { Quickshell.execDetached(["sh", "-c", script, "sh"].concat(args)) }

    function action(id, item) {
        if (item.kind !== "file") return false
        const p = item.path
        if (id === "copypath") {
            sh("printf '%s' \"$1\" | wl-copy; notify-send -a Launcher 'Copied path' \"$1\"", p)
        } else if (id === "openfolder") {
            Quickshell.execDetached(["xdg-open", p])
        } else if (id === "showfolder" || id === "folder") {
            Quickshell.execDetached(["nautilus", "--select", p])
        } else if (id === "term") {
            Quickshell.execDetached(["kitty", "--directory", p])
        } else if (id === "edit") {
            sh("exec kitty --directory \"$(dirname -- \"$1\")\" -e \"${EDITOR:-nvim}\" \"$1\"", p)
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
