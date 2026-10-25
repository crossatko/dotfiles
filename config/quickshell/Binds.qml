pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Keybind cheat sheet data: `hyprctl binds -j`, one-shot Process (never a loop). Fetched when the launcher's "binds" section is
// entered (load()), and again on Hyprland's `configreloaded` event once it was loaded, so edits to binds.lua show up after a reload.
// Names come from each bind's `description` (set in hypr/hyprland/binds.lua); without one the dispatcher is shown.
// `items` = launcher rows { id, name, subtitle, keywords, kind: "bind", keys: ["Super", "Shift", "E"], ... }.
// $QS_BINDS_JSON = path of a JSON file used instead of hyprctl (tests).
QtObject {
    id: root

    property var items: []
    property bool loaded: false              // first answer arrived
    property bool wanted: false              // section was opened once: keep fresh on config reloads
    readonly property string fake: Quickshell.env("QS_BINDS_JSON")

    function load() {
        wanted = true
        if (!proc.running) proc.running = true
    }

    // modmask bits: SHIFT 1, CAPS 2, CTRL 4, ALT 8, MOD2 (Num) 16, MOD3 32, SUPER 64, MOD5 128
    readonly property var modNames: [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"], [2, "Caps"], [16, "Num"], [32, "Mod3"], [128, "Mod5"]]
    function modList(mask) { return modNames.filter(m => (mask & m[0]) !== 0).map(m => m[1]) }

    function keyLabel(k) {
        const mouse = { "mouse:272": "Left click", "mouse:273": "Right click", "mouse:274": "Middle click" }
        if (mouse[k]) return mouse[k]
        if (k === "mouse_down") return "Wheel down"
        if (k === "mouse_up") return "Wheel up"
        const named = { slash: "/", backslash: "\\", comma: ",", period: ".", semicolon: ";", minus: "-", equal: "=", space: "Space", Return: "Enter", TAB: "Tab", Escape: "Esc" }
        if (named[k]) return named[k]
        if (k.indexOf("XF86") === 0) return k.slice(4).replace(/([a-z])([A-Z])/g, "$1 $2")
        return k.length === 1 ? k.toUpperCase() : k
    }

    // name for a bind without a description: the dispatcher ("HL.Dispatcher(exec_cmd)" -> "exec_cmd"), Lua closures are opaque
    function fallbackName(b) {
        const m = /^HL\.Dispatcher\((.*)\)$/.exec(b.dispatcher || "")
        if (m) return m[1].replace(/_/g, " ")
        return /^function:/.test(b.dispatcher || "") ? "Lua function" : (b.dispatcher || "Unnamed bind")
    }

    function build(arr) {
        const rows = []
        arr.forEach((b, i) => {
            if (b.non_consuming || b.catch_all) return           // passthrough helpers (Esc closes popups), not shortcuts
            const mods = modList(b.modmask || 0)
            const key = keyLabel(b.key || "")
            if (key === "") return
            const flags = []
            if (b.submap) flags.push("submap " + b.submap)
            if (b.locked) flags.push("works when locked")
            if (b.repeat) flags.push("repeats")
            if (b.release) flags.push("on release")
            if (b.longPress) flags.push("long press")
            const desc = b.description || ""
            const keys = mods.concat([key])
            rows.push({
                id: "bind:" + i,
                name: desc !== "" ? desc : fallbackName(b),
                subtitle: flags.join(" · "),
                keywords: keys.concat(keys.join(" "), [b.key || ""]),
                kind: "bind", source: "", glyph: "", transient: true, private: true,
                keys: keys,
                _group: b.mouse ? 3 : b.locked ? 2 : ((b.modmask || 0) & 64) ? 0 : 1, _mods: mods.length, _key: key
            })
        })
        rows.sort((a, c) => a._group - c._group || a._mods - c._mods || natCmp(a._key, c._key) || natCmp(a.name, c.name))
        return rows
    }

    // natural order: digit runs compare as numbers, so 2 < 10 and F2 < F10
    function natCmp(a, b) {
        const ra = String(a).match(/\d+|\D+/g) || [], rb = String(b).match(/\d+|\D+/g) || []
        for (let i = 0; i < Math.min(ra.length, rb.length); i++) {
            const na = /^\d/.test(ra[i]), nb = /^\d/.test(rb[i])
            const d = na && nb ? parseInt(ra[i], 10) - parseInt(rb[i], 10)
                               : (ra[i] < rb[i] ? -1 : ra[i] > rb[i] ? 1 : 0)
            if (d !== 0) return d
        }
        return ra.length - rb.length
    }

    signal refreshed()

    property var proc: Process {
        command: root.fake !== "" ? ["cat", root.fake] : ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let arr = []
                try { arr = JSON.parse(text) } catch (e) { return }
                root.items = root.build(arr)
                root.loaded = true
                root.refreshed()
            }
        }
    }

    property var conn: Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "configreloaded" && root.wanted) root.load() }
    }
}
