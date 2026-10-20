import QtQuick
import Quickshell
import Quickshell.Io

// Source: script commands (Raycast style). Executable files in ~/.config/launcher/commands (repo:
// config/launcher/commands), any language. Header comment, first 30 lines, `# @launcher.key value` or `// @launcher.key value`:
//   title      display name (default: file name without extension)
//   subtitle   second line
//   icon       freedesktop icon name (optional; a terminal glyph is shown otherwise)
//   aliases    comma-separated extra search terms
//   mode       silent (default) | toast (first stdout line as a notification) | terminal (runs in kitty)
//   argument   present = the launcher asks for text after selection, passed as $1 (value = prompt label)
// The directory is rescanned each time the launcher opens (`active` follows Launcher.shown).
// Override the directory with $LAUNCHER_COMMANDS_DIR.
QtObject {
    id: src

    property bool active: false
    property var items: []

    readonly property string dir: Quickshell.env("LAUNCHER_COMMANDS_DIR")
        || Quickshell.env("HOME") + "/.config/launcher/commands"
    readonly property string scanner: String(Qt.resolvedUrl("bin/scan-commands")).replace(/^file:\/\//, "")

    onActiveChanged: if (active && !scan.running) { raw = []; scan.running = true }

    property var raw: []

    property var scan: Process {
        command: ["bash", src.scanner, src.dir]
        stdout: SplitParser {
            onRead: line => src.raw.push(line)
        }
        onExited: {
            const next = src.parse(src.raw)
            if (JSON.stringify(next) !== JSON.stringify(src.items)) src.items = next
        }
    }

    function parse(lines) {
        const out = []
        let cur = null
        const flush = () => { if (cur) out.push(cur.item) }
        for (const line of lines) {
            const tab = line.indexOf("\t")
            if (tab < 0) continue
            const k = line.slice(0, tab), v = line.slice(tab + 1)
            if (k === "@") { flush(); cur = { file: v, meta: {}, item: null }; cur.item = build(cur); continue }
            if (!cur) continue
            if (!(k in cur.meta)) cur.meta[k] = v
            cur.item = build(cur)
        }
        flush()
        return out
    }

    function build(c) {
        const m = c.meta
        const base = c.file.replace(/\.[^.]*$/, "") || c.file
        const mode = ["silent", "toast", "terminal"].indexOf(m.mode) >= 0 ? m.mode : "silent"
        const aliases = (m.aliases || "").split(",").map(s => s.trim()).filter(s => s.length > 0)
        return {
            id: "script:" + c.file,
            name: m.title || base,
            subtitle: m.subtitle || "",
            aliases: aliases,
            kind: "script",
            source: "Script",
            icon: m.icon || "",
            glyph: mode === "terminal" ? "" : "",     // terminal / code
            file: c.file,
            mode: mode,
            argument: ("argument" in m) ? (m.argument || "Argument") : ""
        }
    }

    function run(item, arg) {
        if (item.kind !== "script") return false
        const path = dir + "/" + item.file
        const args = (item.argument && arg !== undefined && arg !== "") ? [arg] : []
        if (item.mode === "terminal") {
            Quickshell.execDetached(["kitty", "--title", item.name, "-e", path].concat(args))
        } else if (item.mode === "toast") {
            // first line of stdout (stderr too when it failed) becomes a notification; the script env is never shown
            Quickshell.execDetached(["sh", "-c",
                "t=$1; shift; o=$(\"$@\" 2>&1); rc=$?; " +
                "if [ \"$rc\" -ne 0 ]; then m=\"failed ($rc): $(printf '%s' \"$o\" | head -n1)\"; " +
                "else m=$(printf '%s' \"$o\" | head -n1); fi; " +
                "[ -n \"$m\" ] && exec notify-send -a Launcher \"$t\" \"$m\"",
                "sh", item.name, path].concat(args))
        } else {
            Quickshell.execDetached([path].concat(args))
        }
        return true
    }
}
