pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Settings -> Desktop clock: the opt-in glass clock on the desktop (DeskClock.qml / DeskClockView.qml read the values
// here, live). Saved in ${XDG_STATE_HOME:-~/.local/state}/quickshell/deskclock.json next to appearance.json
// (QS_DESKCLOCK_FILE overrides the path), the same way as LockPrefs / lock.json: a MISSING key = the built-in default,
// `{}` or no file = off; this singleton is the only writer (debounced save).
//   enabled                 show it at all (default off)
//   size (0.08-0.30)        digit size, share of the screen's short side
//   posX, posY (0-1)        where the clock box sits: 0 = left / top edge, 1 = right / bottom edge (a 3 % margin kept)
//   clock24h, showDate      bool
//   hidden                  { "<monitor key>": true } monitors without the clock (Appearance.monitorKey)
//   qs ipc call deskclock get | set <key> <value> | unset <key> | reset | hideOn <monitor key> | showOn <monitor key>
Singleton {
    id: root

    readonly property string filePath: {
        const env = Quickshell.env("QS_DESKCLOCK_FILE")
        return env ? String(env) : Appearance.dir + "/deskclock.json"
    }
    readonly property string dir: filePath.substring(0, filePath.lastIndexOf("/")) || "/"

    // key -> [min, max, decimals] for numbers, "bool" for booleans, "map" for { string: true }
    readonly property var spec: ({
        enabled: "bool", size: [0.08, 0.3, 3], posX: [0, 1, 3], posY: [0, 1, 3],
        clock24h: "bool", showDate: "bool", hidden: "map"
    })
    readonly property var keys: Object.keys(spec)
    readonly property var defaults: ({
        enabled: false, size: 0.16, posX: 0.04, posY: 0.9,
        clock24h: true, showDate: true, hidden: ({})
    })

    property var data: ({})
    function overridden(key) { return root.data[key] !== undefined }
    function value(key) { const v = root.data[key]; return v !== undefined ? v : root.defaults[key] }

    readonly property bool enabled: value("enabled")
    readonly property real size: value("size")
    readonly property real posX: value("posX")
    readonly property real posY: value("posY")
    readonly property bool clock24h: value("clock24h")
    readonly property bool showDate: value("showDate")
    readonly property var hidden: value("hidden")
    function shownOn(screen) { return enabled && !!screen && hidden[Appearance.monitorKey(screen)] !== true }

    function clean(key, v) {
        const s = spec[key]
        if (s === undefined) return undefined
        if (s === "bool") return typeof v === "boolean" ? v : undefined
        if (s === "map") {
            if (v === null || typeof v !== "object" || Array.isArray(v)) return undefined
            const o = {}
            for (const k of Object.keys(v)) if (typeof k === "string" && k.length > 0 && k.length <= 200 && v[k] === true) o[k] = true
            return o
        }
        if (typeof v !== "number" || !isFinite(v)) return undefined
        const p = Math.pow(10, s[2])
        return Math.round(Math.max(s[0], Math.min(s[1], v)) * p) / p
    }
    function same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }
    function parse(text) {
        const out = {}
        if (typeof text !== "string" || text.length > 8192) return out
        let o
        try { o = JSON.parse(text) } catch (e) { return out }
        if (o === null || typeof o !== "object" || Array.isArray(o)) return out
        for (const k of keys) {
            if (!Object.prototype.hasOwnProperty.call(o, k)) continue
            const v = clean(k, o[k])
            if (v !== undefined && !(spec[k] === "map" && Object.keys(v).length === 0)) out[k] = v
        }
        return out
    }
    function serialize(d) {
        const o = {}
        let any = false
        for (const k of keys) if (d[k] !== undefined) { if (!any) o.version = 1; o[k] = d[k]; any = true }
        return JSON.stringify(o) + "\n"
    }

    function set(key, v) {
        const c = clean(key, v)
        if (c === undefined || same(root.data[key], c)) return
        const d = Object.assign({}, root.data)
        if (same(c, root.defaults[key])) delete d[key]          // the default is not an override
        else d[key] = c
        commit(d)
    }
    function unset(key) {
        if (root.data[key] === undefined) return
        const d = Object.assign({}, root.data)
        delete d[key]
        commit(d)
    }
    function reset() { commit({}) }
    // per monitor (Appearance.monitorKey)
    function setShownOn(monitorKey, on) {
        const h = Object.assign({}, hidden)
        if (on) delete h[monitorKey]
        else h[monitorKey] = true
        set("hidden", h)
    }

    function commit(d) {
        root.data = d
        if (!saver.running) Quickshell.execDetached(["mkdir", "-p", root.dir])
        saver.restart()
    }
    property string lastText: ""
    Timer {
        id: saver
        interval: 300
        onTriggered: { const t = root.serialize(root.data); root.lastText = t; fileView.setText(t) }
    }
    function applyLoaded(t) {
        if (saver.running || t === root.lastText) return
        root.lastText = t
        const d = root.parse(t)
        if (root.serialize(d) !== root.serialize(root.data)) root.data = d
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
        target: "deskclock"
        function get(): string { return root.serialize(root.data).trim() }
        function set(key: string, value: string): string {
            const s = root.spec[key]
            if (s === undefined || s === "map") return "bad key"
            const v = s === "bool" ? (value === "true" ? true : value === "false" ? false : undefined) : Number(value)
            if (root.clean(key, v) === undefined) return "bad value"
            root.set(key, v)
            return "ok"
        }
        function unset(key: string): string { root.unset(key); return "ok" }
        function reset(): string { root.reset(); return "ok" }
        function hideOn(monitor: string): string { root.setShownOn(monitor, false); return "ok" }
        function showOn(monitor: string): string { root.setShownOn(monitor, true); return "ok" }
    }
}
