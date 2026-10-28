pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "launcher/js/MonitorShown.js" as Shown

// Settings -> Lock screen: the look and motion of the shell's lock (Lock.qml / LockView.qml and their parts read the
// values here, live). Saved in ${XDG_STATE_HOME:-~/.local/state}/quickshell/lock.json next to appearance.json
// (QS_LOCK_FILE overrides the path), the same way as Motion.qml / animations.json: a MISSING key = the built-in
// default (`defaults`), `{}` or no file = the stock look; this singleton is the only writer (debounced save).
//   dim (0-0.7)          wallpaper darkening (Theme.lockDim: blurred backdrop and what the glass refracts)
//   blur (0-64 px)       backdrop blur radius
//   clockSize (0.14-0.34) digit size, share of the screen's short side
//   dotSize (0.06-0.14)  password bead size, share of the digit size
//   showDate, clock24h, clockReveal (digits form after the lock is up), snapshot (desktop snapshot: the ring
//   transitions; off = nothing of the desktop is captured), unlockRing (the ring on unlock), burstOnLock /
//   burstOnType / burstOnSubmit (video wallpaper bursts), seconds (HH:mm:ss), mediaCard (playback card under the
//   password dots while an MPRIS player exists)   all bool
//   morph (0-3)          the digits' morph time, x the default (Animations speed); 0 = a plain swap (ClockFace)
//   clock                the clock at all (default on); with `hidden` = which monitors show the clock, date and playback
//   hidden               card: { "<monitor key>": true } (Appearance.monitorKey). ONE rule, launcher/js/MonitorShown.js (as the
//                        desktop clock; `clock` plays its `enabled`), read through clockOn(screen) by LockView and Settings,
//                        written only through setClockOn / setAllClock (one commit of both keys: on while off everywhere =
//                        that monitor only; off on the last connected one = `clock` false). Files without `clock` read as
//                        before (on, minus `hidden`). Off = the password dots stay where they would be.
//   qs ipc call lockprefs get | set <key> <value> | unset <key> | reset | hideClockOn <monitor key> | showClockOn <monitor key> | clockAll <true|false>
Singleton {
    id: root

    readonly property string filePath: {
        const env = Quickshell.env("QS_LOCK_FILE")
        return env ? String(env) : Appearance.dir + "/lock.json"
    }
    readonly property string dir: filePath.substring(0, filePath.lastIndexOf("/")) || "/"

    // key -> [min, max, decimals] for numbers, "bool" for booleans, "map" for { string: true }
    readonly property var spec: ({
        dim: [0, 0.7, 2], blur: [0, 64, 0], clockSize: [0.14, 0.34, 3], dotSize: [0.06, 0.14, 3],
        showDate: "bool", clock24h: "bool", clockReveal: "bool", snapshot: "bool", unlockRing: "bool",
        burstOnLock: "bool", burstOnType: "bool", burstOnSubmit: "bool",
        seconds: "bool", morph: [0, 3, 2], hidden: "map", mediaCard: "bool", clock: "bool"
    })
    readonly property var keys: Object.keys(spec)
    readonly property var defaults: ({
        dim: 0.5, blur: 0, clockSize: 0.24, dotSize: 0.08,
        showDate: true, clock24h: true, clockReveal: true, snapshot: true, unlockRing: true,
        burstOnLock: true, burstOnType: true, burstOnSubmit: true,
        seconds: false, morph: 1, hidden: ({}), mediaCard: true, clock: true
    })
    readonly property int blurMax: 64           // the largest blur: the lock's backdrop chain is this much larger than the screen

    property var data: ({})
    function overridden(key) { return root.data[key] !== undefined }
    function value(key) { const v = root.data[key]; return v !== undefined ? v : root.defaults[key] }

    readonly property real dim: value("dim")
    readonly property int blur: value("blur")
    readonly property real clockSize: value("clockSize")
    readonly property real dotSize: value("dotSize")
    readonly property bool showDate: value("showDate")
    readonly property bool clock24h: value("clock24h")
    readonly property bool clockReveal: value("clockReveal")
    readonly property bool snapshot: value("snapshot")
    readonly property bool unlockRing: value("unlockRing")
    readonly property bool burstOnLock: value("burstOnLock")
    readonly property bool burstOnType: value("burstOnType")
    readonly property bool burstOnSubmit: value("burstOnSubmit")
    readonly property bool seconds: value("seconds")
    readonly property real morph: value("morph")
    readonly property var hidden: value("hidden")
    readonly property bool mediaCard: value("mediaCard")
    readonly property bool clock: value("clock")
    // per monitor: the clock (and date, playback card) on this screen / monitor key; no screen = the global switch
    function clockOn(screen) { return screen ? clockOnKey(Appearance.monitorKey(screen)) : clock }
    function clockOnKey(monitorKey) { return Shown.shown(clock, hidden, monitorKey) }
    // the connected monitors' keys, and how many of them show the clock
    readonly property var screenKeys: Quickshell.screens.map(s => Appearance.monitorKey(s)).filter(k => k !== "")
    readonly property int clockCount: Shown.shownKeys({ enabled: clock, hidden: hidden }, screenKeys).length
    readonly property bool clockAll: screenKeys.length > 0 && clockCount === screenKeys.length
    // the only writers of `clock` + `hidden` besides set / reset (one commit)
    function setClockOn(monitorKey, on) { applyShown(Shown.toggle({ enabled: clock, hidden: hidden }, screenKeys, monitorKey, on)) }
    function setAllClock(on) { applyShown(Shown.setAll({ enabled: clock, hidden: hidden }, screenKeys, on)) }
    function applyShown(n) {
        const d = Object.assign({}, root.data)
        const vals = { clock: n.enabled, hidden: n.hidden }
        for (const k of ["clock", "hidden"]) {
            const c = clean(k, vals[k])
            if (c === undefined || same(c, root.defaults[k])) delete d[k]
            else d[k] = c
        }
        if (root.serialize(d) !== root.serialize(root.data)) commit(d)
    }

    function clean(key, v) {
        const s = spec[key]
        if (s === undefined) return undefined
        if (s === "bool") return typeof v === "boolean" ? v : undefined
        if (s === "map") {
            if (v === null || typeof v !== "object" || Array.isArray(v)) return undefined
            const o = {}
            for (const k of Object.keys(v)) if (k.length > 0 && k.length <= 200 && v[k] === true) o[k] = true
            return o
        }
        if (typeof v !== "number" || !isFinite(v)) return undefined
        const p = Math.pow(10, s[2])
        return Math.round(Math.max(s[0], Math.min(s[1], v)) * p) / p
    }
    function parse(text) {
        const out = {}
        if (typeof text !== "string" || text.length > 4096) return out
        let o
        try { o = JSON.parse(text) } catch (e) { return out }
        if (o === null || typeof o !== "object" || Array.isArray(o)) return out
        for (const k of keys) {
            if (!Object.prototype.hasOwnProperty.call(o, k)) continue
            const v = clean(k, o[k])
            if (v !== undefined) out[k] = v
        }
        return out
    }
    function serialize(d) {
        const o = {}
        let any = false
        for (const k of keys) if (d[k] !== undefined) { if (!any) o.version = 1; o[k] = d[k]; any = true }
        return JSON.stringify(o) + "\n"
    }

    function same(a, b) { return a === b || (typeof a === "object" && typeof b === "object" && JSON.stringify(a) === JSON.stringify(b)) }
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
        target: "lockprefs"
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
        function hideClockOn(monitor: string): string { root.setClockOn(monitor, false); return "ok" }
        function showClockOn(monitor: string): string { root.setClockOn(monitor, true); return "ok" }
        function clockAll(on: string): string {
            if (on !== "true" && on !== "false") return "bad value"
            root.setAllClock(on === "true")
            return "ok"
        }
    }
}
