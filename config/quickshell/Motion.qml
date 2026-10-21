pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Settings -> Animations: speed / curve / style of the bar popups (PopupHost.qml via the Theme.popup* tokens)
// and speed / curve / on-off of every Hyprland animation (applied by hypr/hyprland/managed.lua).
// Saved in ${XDG_STATE_HOME:-~/.local/state}/quickshell/animations.json next to appearance.json
// (QS_ANIM_FILE overrides the path). A MISSING key = today's built-in value; `{}` or no file = all defaults.
// This singleton is the only writer. Flat keys (managed.lua parses them with patterns):
//   popupSpeed (0.25-10, higher = faster), popupCurve (cubic|quint|expo|back|linear), popupStyle (scale|slide|fade|none)
//   launcherMotion (bool, default false): the launcher card (ModalMenu `animated`) uses the popup speed / curve / style
//   hyprEnabled (bool), hyprSpeed (0.25-10), hyprCurve (config|smooth|snappy|overshoot|linear|spring)
//   <group>Enabled / <group>Speed (multiplies hyprSpeed) / <group>Curve, group in `groups` below
// After a save that changed a Hyprland key: hyprctl eval "if anim_apply then anim_apply() end".
Singleton {
    id: root

    readonly property string filePath: {
        const env = Quickshell.env("QS_ANIM_FILE")
        return env ? String(env) : Appearance.dir + "/animations.json"
    }
    readonly property string dir: filePath.substring(0, filePath.lastIndexOf("/")) || "/"

    // what 1x means, for the shell AND Hyprland: an animation at 1x takes baseMs. MUST equal A.BASE_MS in
    // hypr/hyprland/animations.lua (Hyprland's side; the Lua config cannot read this file)
    readonly property int baseMs: 200
    readonly property var speedRange: [0.25, 10]          // every speed key; same as managed.lua M.ANIM_SPEED
    readonly property var popupCurves: ["cubic", "quint", "expo", "back", "linear"]
    readonly property var popupStyles: ["scale", "slide", "fade", "none"]
    readonly property var hyprCurves: ["config", "smooth", "snappy", "overshoot", "linear", "spring"]
    // id -> label; same leaves as managed.lua M.ANIM_GROUPS
    readonly property var groups: [
        { id: "windows", label: "Windows" },
        { id: "layers", label: "Layers" },
        { id: "fade", label: "Fade" },
        { id: "workspaces", label: "Workspaces" },
        { id: "specialWorkspace", label: "Scratchpad" },
        { id: "border", label: "Border" }
    ]
    readonly property var keys: {
        const k = ["popupSpeed", "popupCurve", "popupStyle", "launcherMotion", "hyprEnabled", "hyprSpeed", "hyprCurve"]
        for (const g of groups) k.push(g.id + "Enabled", g.id + "Speed", g.id + "Curve")
        return k
    }
    // key -> "speed" | "bool" | [allowed strings]
    function kind(key) {
        if (key === "launcherMotion") return "bool"
        if (key.endsWith("Speed")) return "speed"
        if (key.endsWith("Enabled")) return "bool"
        if (key === "popupCurve") return popupCurves
        if (key === "popupStyle") return popupStyles
        if (key.endsWith("Curve")) return hyprCurves
        return undefined
    }
    readonly property var defaults: ({ popupSpeed: 1, popupCurve: "cubic", popupStyle: "scale", launcherMotion: false,
                                       hyprEnabled: true, hyprSpeed: 1, hyprCurve: "config" })

    // overrides, only valid keys; replaced as a whole so bindings update
    property var data: ({})
    function overridden(key) { return root.data[key] !== undefined }
    // override, else the default (a group's Curve defaults to "" = follows hyprCurve)
    function value(key) {
        const v = root.data[key]
        if (v !== undefined) return v
        if (defaults[key] !== undefined) return defaults[key]
        if (key.endsWith("Speed")) return 1
        if (key.endsWith("Enabled")) return true
        return ""
    }

    // ---- effective popup values (Theme.qml turns these into the popup* tokens) ----
    readonly property real popupSpeed: value("popupSpeed")
    readonly property string popupCurve: value("popupCurve")
    readonly property string popupStyle: value("popupStyle")
    readonly property bool launcherMotion: value("launcherMotion")
    // Quickshell-only keys (bar popups + launcher); everything else goes to Hyprland
    function isShellKey(k) { return k.startsWith("popup") || k.startsWith("launcher") }

    function clean(key, v) {
        const k = kind(key)
        if (k === undefined) return undefined
        if (k === "bool") return typeof v === "boolean" ? v : undefined
        if (k === "speed") {
            if (typeof v !== "number" || !isFinite(v)) return undefined
            return Math.round(Math.max(speedRange[0], Math.min(speedRange[1], v)) * 100) / 100
        }
        return typeof v === "string" && k.indexOf(v) >= 0 ? v : undefined
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

    function set(key, v) {
        const c = clean(key, v)
        if (c === undefined || root.data[key] === c) return
        const d = Object.assign({}, root.data)
        d[key] = c
        commit(d)
    }
    function unset(key) {
        if (root.data[key] === undefined) return
        const d = Object.assign({}, root.data)
        delete d[key]
        commit(d)
    }
    // prefix "popup" (popups + launcher) | "hypr" (also every group key) | "" = everything
    function reset(prefix) {
        const d = {}
        for (const k of Object.keys(root.data)) {
            const isPopup = root.isShellKey(k)
            if (prefix === "popup" ? !isPopup : prefix === "hypr" ? isPopup : false) d[k] = root.data[k]
        }
        commit(d)
    }
    function anyOverridden(prefix) {
        return Object.keys(root.data).some(k => prefix === "popup" ? root.isShellKey(k) : !root.isShellKey(k))
    }

    function hyprKey(d) {
        const o = {}
        // launcherMotion also matters to Hyprland (managed.lua switches the qs-launcher layer fade off with it)
        for (const k of keys) if ((!root.isShellKey(k) || k === "launcherMotion") && d[k] !== undefined) o[k] = d[k]
        return JSON.stringify(o)
    }
    property string notifiedHypr: ""

    function commit(d) {
        root.data = d
        if (!saver.running) Quickshell.execDetached(["mkdir", "-p", root.dir])
        saver.restart()
    }
    property string lastText: ""
    property bool initialized: false

    Timer {
        id: saver
        interval: 300
        onTriggered: {
            const t = root.serialize(root.data)
            root.lastText = t
            fileView.setText(t)
            if (root.hyprKey(root.data) !== root.notifiedHypr) notifier.restart()
        }
    }
    // Hyprland's Lua config cannot watch the file; anim_apply() (hypr/hyprland/managed.lua) re-reads it
    Timer {
        id: notifier
        interval: 200                    // let the file write land first
        onTriggered: {
            root.notifiedHypr = root.hyprKey(root.data)
            Quickshell.execDetached([Appearance.hyprctl, "eval", "if anim_apply then anim_apply() end"])
        }
    }

    function applyLoaded(t) {
        if (saver.running) return
        if (root.initialized && t === root.lastText) return
        root.lastText = t
        const d = root.parse(t)
        if (root.serialize(d) !== root.serialize(root.data)) root.data = d
        if (!root.initialized) {
            root.initialized = true
            root.notifiedHypr = root.hyprKey(d)       // Hyprland read the same file at its own config load
        } else if (root.hyprKey(d) !== root.notifiedHypr) {
            notifier.restart()                        // edited by hand: tell Hyprland too
        }
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

    //   qs ipc call anim get | set <key> <value> | unset <key> | reset [popup|hypr|all]
    IpcHandler {
        target: "anim"
        function get(): string { return root.serialize(root.data).trim() }
        function set(key: string, value: string): string {
            const k = root.kind(key)
            if (k === undefined) return "bad key"
            const v = k === "speed" ? Number(value) : k === "bool" ? (value === "true" ? true : value === "false" ? false : undefined) : value
            if (root.clean(key, v) === undefined) return "bad value"
            root.set(key, v)
            return "ok"
        }
        function unset(key: string): string { root.unset(key); return "ok" }
        function reset(which: string): string { root.reset(which === "all" ? "" : which); return "ok" }
    }
}
