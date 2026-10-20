import QtQuick
import Quickshell
import Quickshell.Io

// Source: clipboard history (cliphist). Exclusive prefix mode: the raw (untrimmed) query is `clip`, `clip <text>`
// or `v <text>` including the single space after `v` (a bare `v` is a normal search, so apps starting with v keep
// working); then only clipboard rows show. Lists the stored entries, newest first, filtered by the text after the prefix (case-insensitive substring of
// the one-line preview). Enter copies the entry back (`cliphist decode <id> | wl-copy`). The id is passed as a
// positional argument to a fixed `sh -c` script, clipboard contents never touch a command line, a log or a toast.
// The history is read each time the launcher opens (`active` follows Launcher.shown). The watchers that fill it
// are started in hypr/hyprland/autostart.lua.
QtObject {
    id: src

    property bool active: false
    signal updated()
    property var items: []          // always empty (entries only show in prefix mode); the launcher redraws on updated()
    property var clips: []          // [{ id, preview, image }], newest first
    readonly property int limit: 50

    onActiveChanged: if (active && !list.running) { raw = []; list.running = true }

    property var raw: []

    property var list: Process {
        command: ["cliphist", "list"]
        stdout: SplitParser {
            onRead: line => src.raw.push(line)
        }
        onExited: {
            const out = []
            for (const line of src.raw) {
                const tab = line.indexOf("\t")
                if (tab < 1) continue
                const id = line.slice(0, tab)
                if (!/^[0-9]+$/.test(id)) continue
                const text = line.slice(tab + 1)
                out.push({ id: id, preview: text, image: /^\[\[ binary data .* \]\]$/.test(text) })
            }
            src.raw = []
            src.clips = out
            src.updated()
        }
    }

    // returns the filter text when the raw query is in prefix mode, else null
    function prefixed(raw) {
        if (typeof raw !== "string") return null
        const m = /^\s*(?:v\s|clip(?:\s|$))(.*)$/i.exec(raw)
        return m ? m[1].trim().toLowerCase() : null
    }

    function exclusive(q, raw) { return prefixed(raw) !== null }

    function dynamic(q, raw) {
        const f = prefixed(raw)
        if (f === null) return []
        const out = []
        for (const c of clips) {
            const one = c.preview.replace(/\s+/g, " ").trim()
            if (f !== "" && one.toLowerCase().indexOf(f) < 0) continue
            out.push({
                id: "clip:" + c.id,
                name: c.image ? "[image]" : (one.length > 90 ? one.slice(0, 90) + "…" : one),
                subtitle: c.image ? one.replace(/^\[\[ binary data (.*) \]\]$/, "$1") : "",
                kind: "clip", source: "Clipboard",
                transient: true, private: true,       // never in usage.json / history.json, no Pin / Hide
                actions: [{ id: "clip-delete", label: "Delete entry", glyph: "" }],
                glyph: c.image ? "" : "",     // image / clipboard
                clipId: c.id
            })
            if (out.length >= limit) break
        }
        return out
    }

    function run(item) {
        if (item.kind !== "clip") return false
        Quickshell.execDetached(["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", String(item.clipId)])
        return true
    }

    // Ctrl+K action; "keep" = the launcher stays open and redraws
    function action(id, item) {
        if (id !== "clip-delete" || item.kind !== "clip") return false
        clips = clips.filter(c => c.id !== item.clipId)      // drop it from the view right away
        del.command = ["sh", "-c", "cliphist list | awk -F'\\t' -v id=\"$1\" '$1 == id' | cliphist delete", "sh", String(item.clipId)]
        del.running = true
        return "keep"
    }

    property var del: Process {
        onExited: if (!src.list.running) { src.raw = []; src.list.running = true }
    }
}
