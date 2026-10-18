pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// User overrides for corner radius, window gaps, border and bar mode (Settings -> Appearance).
// Saved in ${XDG_STATE_HOME:-~/.local/state}/quickshell/appearance.json (QS_APPEARANCE_FILE overrides
// the path for tests). A MISSING key means "use the theme default" (theme.toml [settings] via
// palette.json, see Theme.qml); `{}` or no file = all defaults. This singleton is the only writer.
// Hyprland reads the same file in hypr/hyprland/managed.lua and is poked after every save.
// smartMonitors = per-monitor smartGaps {"<monitor key>": bool}; a monitor without an entry follows
// smartGaps. Monitor key = Hyprland's monitor description (Hyprland.monitorFor(screen).description, the
// same string managed.lua gets from hl.get_monitors()), else the connector name; see monitorKey().
Singleton {
    id: root

    readonly property string filePath: {
        const env = Quickshell.env("QS_APPEARANCE_FILE")
        if (env) return String(env)
        const xdg = Quickshell.env("XDG_STATE_HOME")
        return (xdg ? String(xdg) : Quickshell.env("HOME") + "/.local/state") + "/quickshell/appearance.json"
    }
    readonly property string dir: filePath.substring(0, filePath.lastIndexOf("/")) || "/"
    readonly property string hyprctl: Quickshell.env("QS_HYPRCTL") ? String(Quickshell.env("QS_HYPRCTL")) : "hyprctl"

    // key -> [min, max] for numbers, "bool" for booleans, "map" for smartMonitors. Same ranges and limits
    // as hypr/hyprland/managed.lua (SMART_KEY_MAX, SMART_MAP_MAX).
    readonly property var spec: ({
        radius: [0, 32], gap: [0, 32], edgeGap: [0, 40], border: [0, 6],
        barFloating: "bool", smartGaps: "bool", smartMonitors: "map"
    })
    readonly property var keys: ["radius", "gap", "edgeGap", "border", "barFloating", "smartGaps", "smartMonitors"]
    readonly property int smartKeyMax: 96
    readonly property int smartMapMax: 16

    // Current overrides, only valid keys (never `version`). Replaced as a whole on every change so bindings update.
    property var data: ({})

    // Raw overrides: undefined when the key is not set (= theme default).
    readonly property var radius: data.radius
    readonly property var gap: data.gap
    readonly property var edgeGap: data.edgeGap
    readonly property var border: data.border
    readonly property var barFloating: data.barFloating
    readonly property var smartGaps: data.smartGaps
    readonly property var smartMonitors: data.smartMonitors

    function overridden(key) { return root.data[key] !== undefined }
    // override if set, else `fallback`
    function pick(key, fallback) { const v = root.data[key]; return v === undefined ? fallback : v }

    // smartMonitors key: 1..96 printable ASCII characters without '"' and '\' (managed.lua parses the map
    // with patterns, so nothing that needs a JSON escape)
    function validKey(k) {
        return typeof k === "string" && k.length >= 1 && k.length <= root.smartKeyMax && /^[\x20-\x7e]*$/.test(k) && !/["\\]/.test(k)
    }
    // smartMonitors value -> a fresh {key: bool} copy, or undefined when empty or ANY entry is invalid
    // (bad key, non-boolean, more than 16 entries): the whole map is ignored, as in managed.lua
    function cleanMap(value) {
        if (value === null || typeof value !== "object" || Array.isArray(value)) return undefined
        const ks = Object.keys(value)
        if (ks.length === 0 || ks.length > root.smartMapMax) return undefined
        const out = {}
        for (const k of ks) {
            if (!validKey(k) || typeof value[k] !== "boolean") return undefined
            out[k] = value[k]
        }
        return out
    }
    // -> sanitized value, or undefined when it has to be ignored
    function clean(key, value) {
        const s = spec[key]
        if (s === undefined) return undefined
        if (s === "bool") return typeof value === "boolean" ? value : undefined
        if (s === "map") return cleanMap(value)
        if (typeof value !== "number" || !isFinite(value)) return undefined
        return Math.max(s[0], Math.min(s[1], Math.round(value)))
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

    function set(key, value) {
        const v = clean(key, value)
        if (v === undefined || root.data[key] === v) return
        const d = Object.assign({}, root.data)
        d[key] = v
        commit(d)
    }
    function unset(key) {
        if (root.data[key] === undefined) return
        const d = Object.assign({}, root.data)
        delete d[key]
        commit(d)
    }
    function reset() { commit({}) }

    // ---- per-monitor smart gaps ----
    // ShellScreen -> its smartMonitors key ("" when it has none: then it cannot get its own setting)
    function monitorKey(screen) {
        if (!screen) return ""
        const hm = Hyprland.monitorFor(screen)
        const desc = hm && hm.description ? String(hm.description) : ""
        if (validKey(desc)) return desc
        const name = screen.name ? String(screen.name) : ""
        return validKey(name) ? name : ""
    }
    function smartOverridden(key) {
        const m = root.data.smartMonitors
        return m !== undefined && typeof m[key] === "boolean"
    }
    // effective value for one monitor: its own entry, else smartGaps, else `fallback` (the theme default)
    function smartFor(key, fallback) {
        if (smartOverridden(key)) return root.data.smartMonitors[key]
        return root.data.smartGaps !== undefined ? root.data.smartGaps : fallback
    }
    function setSmartFor(key, value) {
        if (!validKey(key) || typeof value !== "boolean") return
        const m = Object.assign({}, root.data.smartMonitors || {})
        if (m[key] === value) return
        m[key] = value
        if (Object.keys(m).length > root.smartMapMax) return
        const d = Object.assign({}, root.data)
        d.smartMonitors = m
        commit(d)
    }
    function unsetSmartFor(key) {
        if (!smartOverridden(key)) return
        const m = Object.assign({}, root.data.smartMonitors)
        delete m[key]
        const d = Object.assign({}, root.data)
        if (Object.keys(m).length) d.smartMonitors = m
        else delete d.smartMonitors
        commit(d)
    }
    // every monitor (also ones connected later): sets smartGaps and drops the per-monitor entries
    function setSmartAll(value) {
        if (typeof value !== "boolean") return
        if (root.data.smartGaps === value && root.data.smartMonitors === undefined) return
        const d = Object.assign({}, root.data)
        d.smartGaps = value
        delete d.smartMonitors
        commit(d)
    }

    function commit(d) {
        root.data = d
        if (!saver.running) Quickshell.execDetached(["mkdir", "-p", root.dir])
        saver.restart()
    }

    // text last written or loaded, to recognise our own write coming back through the watcher
    property string lastText: ""
    property bool initialized: false
    // smartGaps + smartMonitors as last told to Hyprland: a change needs a config reload (workspace rules)
    property string notifiedSmart: ""
    function smartKey() { return JSON.stringify([root.data.smartGaps, root.data.smartMonitors]) }

    // Monitor hot-plug: managed.lua registers rules for a new monitor itself (monitor.added); as a safety net
    // the shell also runs layout_apply() once when the set of screens changes while per-monitor entries exist.
    readonly property string screenSig: Quickshell.screens.map(s => s.name).sort().join(",")
    property string seenScreens: ""
    onScreenSigChanged: {
        if (!root.initialized || root.seenScreens === "" || root.screenSig === "") { root.seenScreens = root.screenSig; return }
        if (root.screenSig === root.seenScreens) return
        root.seenScreens = root.screenSig
        if (root.data.smartMonitors !== undefined) hotplug.restart()
    }
    Timer {
        id: hotplug
        interval: 1500                   // let Hyprland finish adding the output
        onTriggered: if (!saver.running && !notifier.running)
            Quickshell.execDetached([root.hyprctl, "eval", "if layout_apply then layout_apply() end"])
    }

    Timer {
        id: saver
        interval: 400
        onTriggered: {
            const t = root.serialize(root.data)
            root.lastText = t
            fileView.setText(t)
            notifier.restart()
        }
    }

    // Hyprland's Lua config cannot watch the file; layout_apply() (hypr/hyprland/managed.lua) re-reads it.
    Timer {
        id: notifier
        interval: 250                    // let the file write land first
        onTriggered: {
            const sk = root.smartKey()
            if (sk !== root.notifiedSmart) {
                root.notifiedSmart = sk
                Quickshell.execDetached([root.hyprctl, "reload", "config-only"])
            } else {
                Quickshell.execDetached([root.hyprctl, "eval", "if layout_apply then layout_apply() end"])
            }
        }
    }

    function applyLoaded(t) {
        if (saver.running) return            // a local change is pending and will overwrite the file
        if (root.initialized && t === root.lastText) return
        root.lastText = t
        const d = root.parse(t)
        if (root.serialize(d) !== root.serialize(root.data)) root.data = d
        if (!root.initialized) {
            root.initialized = true
            root.notifiedSmart = root.smartKey()   // Hyprland read the same file at its own start
            root.seenScreens = root.screenSig
        } else {
            notifier.restart()                     // edited by hand: tell Hyprland too
        }
    }

    // Read once synchronously so the first frame (and every hot reload) already has the saved layout:
    // an async load would map the bar docked and move it a moment later. (A FIFO here does not block.)
    Component.onCompleted: fileView.text()

    FileView {
        id: fileView
        path: root.filePath
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyLoaded(text())
        onLoadFailed: root.applyLoaded("")       // missing / unreadable / directory: all defaults
    }
}
