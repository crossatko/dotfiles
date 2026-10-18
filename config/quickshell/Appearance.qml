pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// User overrides for corner radius, window gaps, border and bar mode (Settings -> Appearance).
// Saved in ${XDG_STATE_HOME:-~/.local/state}/quickshell/appearance.json (QS_APPEARANCE_FILE overrides
// the path for tests). A MISSING key means "use the theme default" (theme.toml [settings] via
// palette.json, see Theme.qml); `{}` or no file = all defaults. This singleton is the only writer.
// Hyprland reads the same file in hypr/hyprland/managed.lua and is poked after every save.
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

    // key -> [min, max] for numbers, "bool" for booleans. Same ranges as hypr/hyprland/managed.lua.
    readonly property var spec: ({
        radius: [0, 32], gap: [0, 32], edgeGap: [0, 40], border: [0, 6],
        barFloating: "bool", smartGaps: "bool"
    })
    readonly property var keys: ["radius", "gap", "edgeGap", "border", "barFloating", "smartGaps"]

    // Current overrides, only valid keys (never `version`). Replaced as a whole on every change so bindings update.
    property var data: ({})

    // Raw overrides: undefined when the key is not set (= theme default).
    readonly property var radius: data.radius
    readonly property var gap: data.gap
    readonly property var edgeGap: data.edgeGap
    readonly property var border: data.border
    readonly property var barFloating: data.barFloating
    readonly property var smartGaps: data.smartGaps

    function overridden(key) { return root.data[key] !== undefined }
    // override if set, else `fallback`
    function pick(key, fallback) { const v = root.data[key]; return v === undefined ? fallback : v }

    // -> sanitized value, or undefined when it has to be ignored
    function clean(key, value) {
        const s = spec[key]
        if (s === undefined) return undefined
        if (s === "bool") return typeof value === "boolean" ? value : undefined
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

    function commit(d) {
        root.data = d
        if (!saver.running) Quickshell.execDetached(["mkdir", "-p", root.dir])
        saver.restart()
    }

    // text last written or loaded, to recognise our own write coming back through the watcher
    property string lastText: ""
    property bool initialized: false
    // smartGaps override as last told to Hyprland: a change needs a config reload (workspace rules)
    property string notifiedSmart: ""
    function smartKey() { return String(root.data.smartGaps) }

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
