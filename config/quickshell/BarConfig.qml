pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Per-monitor bar layout: is there a bar on this monitor, and on which edge (top / bottom).
// Saved in ~/.local/state/quickshell/bars.json, keyed by monitor model + serial (connector names such
// as DP-3 change between boots). Monitors without a saved entry fall back to `fallback` below, which
// is the layout from before this was configurable. Changed from the control center's panel settings.
//
// Monitor links (Settings > Bar): bars.json may also carry a reserved top-level "_links": [[keyA, keyB], ...]
// (edges; chained links form one group). Old files without it behave exactly as before, and an old reader
// treats "_links" as a monitor key nobody has. Linked monitors act as one bar: set() writes the field to every
// key in the group (so on/off and the edge follow), and BarWidgets.store() fans layouts out the same way.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.local/state/quickshell"
    readonly property var fallback: ({ "DP-5": "bottom", "DP-3": "bottom", "Virtual-1": "bottom", "HDMI-A-1": "top" })

    property var data: ({})                    // key -> { enabled, edge }, plus the reserved "_links"
    readonly property string linksKey: "_links"
    readonly property var links: {             // [[keyA, keyB], ...], validated: pairs of two different non-empty strings
        const raw = data[linksKey]
        const res = []
        if (!Array.isArray(raw)) return res
        for (const p of raw)
            if (Array.isArray(p) && p.length === 2 && typeof p[0] === "string" && typeof p[1] === "string"
                && p[0] !== "" && p[1] !== "" && p[0] !== p[1]
                && !res.some(q => (q[0] === p[0] && q[1] === p[1]) || (q[0] === p[1] && q[1] === p[0]))) res.push([p[0], p[1]])
        return res
    }

    function keyOf(s) { return s.model ? s.model + "|" + (s.serialNumber || "") : s.name }
    function entry(s) {
        const saved = data[keyOf(s)]
        if (saved) return saved
        const edge = fallback[s.name]
        return { enabled: edge !== undefined, edge: edge || "bottom" }
    }
    function enabled(s) { return entry(s).enabled === true }
    function edge(s) { return entry(s).edge === "top" ? "top" : "bottom" }
    // per bar: docked or floating (Settings > Bar). bars.json `floating` (bool); absent = the default for bars without their own
    // value: Theme.barFloating (appearance.json `barFloating` if present, else theme.toml bar_floating), so old state looks the same.
    // Everything that used the global value reads these per-screen functions (the bar a screen has, or the default for screens without).
    function floating(s) {
        const v = s ? entry(s).floating : undefined
        return typeof v === "boolean" ? v : Theme.barFloating
    }
    function barGapOf(s) { return floating(s) ? Theme.gapOut : 0 }                              // floating bar: distance from the edges
    function radiusOf(s) { return floating(s) ? Theme.radius : 0 }
    function popupGapOf(s) { return floating(s) ? Math.max(4, Theme.gapOut) : 8 }                // popup card <-> bar
    function edgeGapOf(s) { return floating(s) ? Theme.gapOut : 12 }                             // popups / toasts <-> screen edge
    // per bar: no glass / fill / border / blur behind the bar while it is flush with the screen edge (docked, or compacted
    // by a fullscreen window). Absent = false, so old files and other readers behave as before.
    function transparentFlush(s) { return entry(s).transparentFlush === true }
    // "Flush mode": option on and the bar docked. The bar has no backdrop then (Bar.qml), Hyprland's outer gap on the bar's side
    // is 0 on that monitor (hypr/hyprland/managed.lua apply_bar_gaps) and the bar's height follows the window gap: chip height +
    // 3 x the visible gap between windows (2 x gaps_in), clamped to flushPadMin..flushPadMax in total, split evenly above and
    // below the chips (4..16 px per side: chips never touch the edge, a big gap never makes a giant bar). Otherwise the
    // plain bar (Theme.barHeight, 6 px per side). managed.lua bar_height() mirrors this for the pinned video box.
    readonly property int flushPadMin: 8
    readonly property int flushPadMax: 32
    function flushMode(s) { return !!s && enabled(s) && transparentFlush(s) && !floating(s) }
    // bars.json `flushPadding`: absent / "auto" = 3 x gap (clamped), or a number = the total vertical padding in px (0..flushPadManualMax)
    readonly property int flushPadManualMax: 48
    function flushPadding(s) {
        const v = entry(s).flushPadding
        return typeof v === "number" && isFinite(v) ? Math.max(0, Math.min(flushPadManualMax, Math.round(v))) : "auto"
    }
    function autoPad() {
        const t = Math.max(flushPadMin, Math.min(flushPadMax, 3 * 2 * Theme.gapIn))
        return t - t % 2
    }
    function padTotal(s) {
        if (!flushMode(s)) return Theme.barHeight - Theme.chipHeight
        const p = flushPadding(s)
        const t = p === "auto" ? autoPad() : p
        return t - t % 2
    }
    function padSide(s) { return padTotal(s) / 2 }                      // chip inset inside the bar (vertical and horizontal)
    function heightOf(s) { return Theme.chipHeight + padTotal(s) }      // the bar proper
    function reserveOf(s) { return heightOf(s) + barGapOf(s) }         // screen space the bar takes from its edge

    // connector name -> edge, for every screen that has a bar (what Bar, Toasts, Osd and popups consume)
    readonly property var bars: {
        const m = {}
        for (const s of Quickshell.screens) if (enabled(s)) m[s.name] = edge(s)
        return m
    }
    readonly property int enabledCount: Object.keys(bars).length

    // ---- links: monitors in one group share on/off, edge and (BarWidgets) layout ----
    function groupKeys(key) {                  // `key` first, then everything linked to it directly or through a chain
        const g = [key]
        for (let i = 0; i < g.length; i++)
            for (const p of links) {
                if (p[0] === g[i] && g.indexOf(p[1]) < 0) g.push(p[1])
                else if (p[1] === g[i] && g.indexOf(p[0]) < 0) g.push(p[0])
            }
        return g
    }
    function linked(a, b) { return links.some(p => (p[0] === a && p[1] === b) || (p[0] === b && p[1] === a)) }
    function groupOf(s) { return groupKeys(keyOf(s)) }
    function screenFor(key) { return Quickshell.screens.find(s => keyOf(s) === key) || null }
    // can this monitor's group be switched off? Not if that would leave no bar (the last one is the way back into Settings)
    function canDisable(s) {
        if (!enabled(s)) return true
        const g = groupOf(s)
        return Object.keys(bars).length > 0 && Quickshell.screens.some(o => enabled(o) && g.indexOf(keyOf(o)) < 0)
    }

    function set(s, field, value) {
        // never remove the last bar: it is the way back into this very menu. A linked group goes off together, so the
        // rule is about the whole group: refused when no bar would be left outside it
        if (field === "enabled" && value === false && enabled(s) && !canDisable(s)) return
        const base = entry(s)
        const d = JSON.parse(JSON.stringify(data))
        for (const k of groupOf(s)) {
            const sc = screenFor(k)
            d[k] = Object.assign({}, sc ? entry(sc) : (d[k] || base), { [field]: value })
        }
        data = d
        saver.restart()
    }

    // Link a and b (keys). The group they now form takes `from`'s on/off, edge (and, in BarWidgets, layout), so it is
    // consistent at once. If `from` has no bar and no bar would be left outside the group, the group keeps its bars.
    function link(a, b, from) {
        if (a === b || a === "" || b === "") return
        const d = JSON.parse(JSON.stringify(data))
        if (!linked(a, b)) d[linksKey] = links.concat([[a, b]])
        data = d
        const g = groupKeys(a)
        const fs = screenFor(g.indexOf(from) >= 0 ? from : a)
        const src = fs ? entry(fs) : (data[g.indexOf(from) >= 0 ? from : a] || { enabled: true, edge: "bottom" })
        const outside = Quickshell.screens.some(o => enabled(o) && g.indexOf(keyOf(o)) < 0)
        const on = src.enabled === true || !outside
        const d2 = JSON.parse(JSON.stringify(data))
        for (const k of g) d2[k] = { enabled: on, edge: src.edge === "top" ? "top" : "bottom", transparentFlush: src.transparentFlush === true, flushPadding: src.flushPadding, floating: src.floating }
        data = d2
        saver.restart()
    }
    function unlink(a, b) {
        const d = JSON.parse(JSON.stringify(data))
        const rest = links.filter(p => !((p[0] === a && p[1] === b) || (p[0] === b && p[1] === a)))
        if (rest.length > 0) d[linksKey] = rest; else delete d[linksKey]
        data = d
        saver.restart()
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.dir])
    Timer { id: saver; interval: 400; onTriggered: { file.setText(JSON.stringify(root.data, null, 2)); notifier.restart() } }

    // Pinned video windows (PiP / mpv / Twitch player) sit flush with the screen edge when the bar is not
    // under them, so Hyprland has to re-read this file: its Lua config cannot watch it, but a Lua function
    // can be called through `hyprctl dispatch` (hypr/scripts/pip-reserve.lua defines pip_bar_changed). layout_apply (managed.lua)
    // runs first: it sets the bar-side gap of a docked bar with "transparent when flush" and then calls pip_bar_changed itself.
    Timer {
        id: notifier
        interval: 250                    // let the file write land first
        onTriggered: Quickshell.execDetached(["hyprctl", "dispatch",
            "(function() if layout_apply then layout_apply() elseif pip_bar_changed then pip_bar_changed() end return hl.dsp.exec_cmd(\"true\") end)()"])
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
