import QtQuick
import Quickshell
import Quickshell.Io

// Source: file search by name under $HOME, prefix mode: query starting with "/", "~/" or "f ".
// Runs `timeout 3 find` (argv, never a shell) 200 ms after the last keystroke; the Process is stopped when the query
// changes. Depth <= 6, skips .git, node_modules, .cache, Steam, wine prefixes; at most 30 results, shallowest first.
// Enter opens with xdg-open. Item actions (Ctrl+K): copy path, open the containing folder.
QtObject {
    id: src

    signal updated()

    readonly property var items: []
    readonly property string home: Quickshell.env("HOME")
    property string wanted: ""
    property string running_q: ""
    property var found: []                 // {type, path}
    property string shownFor: ""

    function pattern(q) {
        let t = q
        if (t.startsWith("~/")) t = t.slice(2)
        else if (t.startsWith("/")) t = t.slice(1)
        else if (/^f\s/.test(t)) t = t.slice(2)
        else return null
        return t.trim()
    }

    function exclusive(q) { return pattern(q) !== null }

    function dynamic(q) {
        const t = pattern(q)
        if (t === null) { wanted = ""; return [] }
        if (t.length < 2) { wanted = ""; stop(); return [] }
        if (t !== wanted) { wanted = t; stop(); debounce.restart() }
        if (shownFor !== t) return []
        return found.map(f => {
            const rel = f.path.startsWith(home + "/") ? "~" + f.path.slice(home.length) : f.path
            const slash = f.path.lastIndexOf("/")
            return {
                id: "file:" + f.path, name: f.path.slice(slash + 1), subtitle: rel,
                kind: "file", source: f.type === "d" ? "Folder" : "File",
                glyph: f.type === "d" ? "\uf07b" : "\uf15b",             // folder / file
                transient: true, path: f.path, dir: f.type === "d" ? f.path : f.path.slice(0, slash),
                actions: [
                    { id: "copypath", label: "Copy path", glyph: "\uf0c5" },            // copy
                    { id: "folder", label: "Open containing folder", glyph: "\uf07c" }      // folder-open
                ]
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

    function action(id, item) {
        if (item.kind !== "file") return false
        if (id === "copypath") {
            Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy; notify-send -a Launcher 'Copied path' \"$1\"", "sh", item.path])
            return true
        }
        if (id === "folder") {
            Quickshell.execDetached(item.kind === "file" && item.dir === item.path
                ? ["xdg-open", item.path] : ["nautilus", "--select", item.path])
            return true
        }
        return false
    }
}
