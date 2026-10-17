pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Per-monitor bar layout: is there a bar on this monitor, and on which edge (top / bottom).
// Saved in ~/.local/state/quickshell/bars.json, keyed by monitor model + serial (connector names such
// as DP-3 change between boots). Monitors without a saved entry fall back to `fallback` below, which
// is the layout from before this was configurable. Changed from the control center's panel settings.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.local/state/quickshell"
    readonly property var fallback: ({ "DP-5": "bottom", "DP-3": "bottom", "Virtual-1": "bottom", "HDMI-A-1": "top" })

    property var data: ({})                    // key -> { enabled, edge }

    function keyOf(s) { return s.model ? s.model + "|" + (s.serialNumber || "") : s.name }
    function entry(s) {
        const saved = data[keyOf(s)]
        if (saved) return saved
        const edge = fallback[s.name]
        return { enabled: edge !== undefined, edge: edge || "bottom" }
    }
    function enabled(s) { return entry(s).enabled === true }
    function edge(s) { return entry(s).edge === "top" ? "top" : "bottom" }

    // connector name -> edge, for every screen that has a bar (what Bar, Toasts, Osd and popups consume)
    readonly property var bars: {
        const m = {}
        for (const s of Quickshell.screens) if (enabled(s)) m[s.name] = edge(s)
        return m
    }
    readonly property int enabledCount: Object.keys(bars).length

    function set(s, field, value) {
        // never remove the last bar: it is the way back into this very menu
        if (field === "enabled" && value === false && enabled(s) && enabledCount <= 1) return
        const d = JSON.parse(JSON.stringify(data))
        d[keyOf(s)] = Object.assign({}, entry(s), { [field]: value })
        data = d
        saver.restart()
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.dir])
    Timer { id: saver; interval: 400; onTriggered: { file.setText(JSON.stringify(root.data, null, 2)); notifier.restart() } }

    // Pinned video windows (PiP / mpv / Twitch player) sit flush with the screen edge when the bar is not
    // under them, so Hyprland has to re-read this file: its Lua config cannot watch it, but a Lua function
    // can be called through `hyprctl dispatch` (hypr/scripts/pip-reserve.lua defines pip_bar_changed).
    Timer {
        id: notifier
        interval: 250                    // let the file write land first
        onTriggered: Quickshell.execDetached(["hyprctl", "dispatch",
            "(function() if pip_bar_changed then pip_bar_changed() end return hl.dsp.exec_cmd(\"true\") end)()"])
    }

    FileView {
        id: file
        path: root.dir + "/bars.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.data = JSON.parse(text()) } catch (e) {} }
        onLoadFailed: root.data = ({})          // file deleted: back to the fallback layout
    }
}
