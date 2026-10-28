pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// The PRIMARY MONITOR: the one lists put first and defaults fall back to (Settings opening, popup / OSD / launcher
// fallbacks, wallpaper theme source). New code asks this singleton instead of indexing Quickshell.screens.
//   ordered            screens, primary first, then by x, y, name (stable: hot-plug never reshuffles the rest)
//   primary            the primary ShellScreen (null while there is none); primaryName its connector, primaryKey its key
//   isPrimary(screen)  label(screen) connector name; title(screen) model, else connector
//   setPrimary(screen) / clearPrimary()   save the choice / go back to the automatic one
//   selected / select(screen | name)   the monitor the Settings pages edit (MonitorSection, the Monitors map): one shared
//                      pick, so switching on one page carries to the others; "" / a monitor that went away = the primary.
//                      Not saved; Settings resets it when it opens.
// Choice: ${XDG_STATE_HOME:-~/.local/state}/quickshell/monitors.json (QS_MONITORS_FILE overrides) =
// { "version": 1, "primary": "<monitor key>" } (Appearance.monitorKey: Hyprland description, so it survives connector
// renumbering). Not connected (or no file) = automatic: highest refresh rate, then most pixels, then connector name.
// This singleton is the only writer. `qs ipc call monitors get | set <connector> | clear`.
Singleton {
    id: root

    readonly property string filePath: {
        const env = Quickshell.env("QS_MONITORS_FILE")
        return env ? String(env) : Appearance.dir + "/monitors.json"
    }
    readonly property string dir: filePath.substring(0, filePath.lastIndexOf("/")) || "/"

    property string saved: ""                                   // the chosen monitor key, "" = automatic
    readonly property var screens: Quickshell.screens.filter(s => s && s.name)

    function rate(s) {
        const hm = Hyprland.monitorFor(s)
        const o = hm ? hm.lastIpcObject : null
        return o && o.refreshRate ? Number(o.refreshRate) : 0
    }
    function byPosition(a, b) { return (a.x - b.x) || (a.y - b.y) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0) }
    function byAuto(a, b) {
        return (rate(b) - rate(a)) || (b.width * b.height - a.width * a.height) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0)
    }
    // the automatic pick, ignoring any saved choice
    readonly property var autoScreen: screens.length ? screens.slice().sort(byAuto)[0] : null
    readonly property bool custom: saved !== "" && screens.some(s => Appearance.monitorKey(s) === saved)
    readonly property var primary: (custom ? screens.find(s => Appearance.monitorKey(s) === saved) : null) || autoScreen
    readonly property string primaryName: primary ? primary.name : ""
    readonly property string primaryKey: primary ? Appearance.monitorKey(primary) : ""
    readonly property var ordered: primary ? [primary].concat(screens.filter(s => s.name !== primary.name).sort(byPosition)) : []

    function isPrimary(s) { return !!s && !!primary && s.name === primary.name }
    function label(s) { return s ? s.name : "" }
    function title(s) { return s ? (s.model || s.name) : "" }
    function byName(n) { return screens.find(s => s.name === n) || null }

    property string selectedName: ""
    readonly property var selected: byName(selectedName) || primary
    function select(s) { selectedName = typeof s === "string" ? s : (s ? s.name : "") }
    onScreensChanged: if (selectedName !== "" && !byName(selectedName)) selectedName = ""
    // the mode: physical px = the screen's logical size x scale (always current), Hz and scale from Hyprland's last monitor
    // report (Hyprland.refreshMonitors() renews it; before the first one: devicePixelRatio, no Hz)
    function mode(s) {
        if (!s) return { w: 0, h: 0, hz: 0, scale: 1 }
        const hm = Hyprland.monitorFor(s)
        const o = hm ? hm.lastIpcObject : null
        const sc = o && o.scale ? Number(o.scale) : (s.devicePixelRatio || 1)
        return { w: Math.round(s.width * sc), h: Math.round(s.height * sc), hz: rate(s), scale: sc }
    }
    function modeText(s) { const m = mode(s); return m.w + "×" + m.h + (m.hz > 0 ? " @ " + Math.round(m.hz) + " Hz" : "") }
    function scaleText(s) { return "×" + Number(mode(s).scale.toFixed(2)) }

    function setPrimary(s) {
        const k = Appearance.monitorKey(s)
        if (k === "" || k === root.saved) return
        commit(k)
    }
    function clearPrimary() { if (root.saved !== "") commit("") }

    function parse(text) {
        if (typeof text !== "string" || text.length > 4096) return ""
        let o
        try { o = JSON.parse(text) } catch (e) { return "" }
        return o !== null && typeof o === "object" && Appearance.validKey(o.primary) ? o.primary : ""
    }
    function serialize(k) { return JSON.stringify(k === "" ? {} : { version: 1, primary: k }) + "\n" }

    function commit(k) {
        root.saved = k
        if (!saver.running) Quickshell.execDetached(["mkdir", "-p", root.dir])
        saver.restart()
    }
    property string lastText: ""
    Timer {
        id: saver
        interval: 300
        onTriggered: { const t = root.serialize(root.saved); root.lastText = t; fileView.setText(t) }
    }
    function applyLoaded(t) {
        if (saver.running || t === root.lastText) return
        root.lastText = t
        root.saved = root.parse(t)
    }

    Component.onCompleted: fileView.text()
    FileView {
        id: fileView
        path: root.filePath
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyLoaded(text())
        onLoadFailed: root.applyLoaded("")
    }

    IpcHandler {
        target: "monitors"
        function get(): string { return root.ordered.map(s => s.name + (root.isPrimary(s) ? "*" : "")).join(" ") + " | saved=" + (root.saved !== "") }
        function set(connector: string): string {
            const s = root.byName(connector)
            if (!s) return "no such monitor"
            root.setPrimary(s)
            return "ok"
        }
        function clear(): string { root.clearPrimary(); return "ok" }
        // the monitor the Settings pages edit (test hook): `select <connector>` ("" = back to the primary), `selected`
        function select(connector: string): string {
            if (connector !== "" && !root.byName(connector)) return "no such monitor"
            root.select(connector)
            return "ok"
        }
        function selected(): string { return root.selected ? root.selected.name : "" }
    }
}
