pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "launcher/js/PttKeys.js" as K

// Czech diacritics on a key (Settings > Diacritics): the key, the model, the idle unload, the ignored window classes and
// whether the pill shows the real text. Saved in ${XDG_STATE_HOME:-~/.local/state}/quickshell/diacritics.json
// (QS_DIACRITICS_FILE overrides), this singleton is the only writer (atomic); the file is watched. The diacritics service
// reads the same file; a missing or malformed file / field = that field's default. A missing file is written with all the
// defaults at start. The default ignored_classes list must stay equal to DEFAULT_IGNORED_CLASSES in
// diacritics/lib/diacritics/prefs.py (the key flow's own default; a unit test compares the two).
//   { "version": 1, "key": "SUPER + SHIFT + D", "model": "<file>.gguf", "idle_timeout_s": 600,
//     "ignored_classes": ["kitty", "foot"], "show_text": true }
//   key              Hyprland bind syntax (PttKeys.js); "" = no key (cleared on purpose); missing = the default key
//   model            a file name in modelsDir (${XDG_DATA_HOME:-~/.local/share}/diacritics/models, QS_DIACRITICS_MODELS_DIR)
//   idle_timeout_s   seconds without a run before the model is unloaded; 0 = never
//   ignored_classes  lower-case window classes where the key does nothing (matched case-insensitively); missing = defaults
//   show_text        the pill shows the real words being fixed; false = a generic animation
// Applying the key: every change also rewrites the generated diacritics-binds.txt next to it (QS_DIACRITICS_BINDS_FILE;
// one "<keys>|<description>" line), which hypr/hyprland/diacritics.lua binds at every config load, then runs
// `hyprctl eval 'diacritics_apply()'` so it works at once. The command the bind runs is set in diacritics.lua only.
// The default key is written to the binds file at start, so it works without opening Settings (shell.qml references
// this singleton). The object is a PrefSwitch / PageReset store (value / set / unset / overridden / changed / resetAll)
// and the key store of PttKeyRow (keysOf / check / setKeys / applyError / loaded / bound / registered / appid).
//   qs ipc call diacritics get | key <keys> | model <file> | idle <s> | show <true|false> | reset | refresh
Singleton {
    id: root

    readonly property string appid: "diacritics"        // no global shortcut: the bind runs a command (PttKeyRow asks anyway)
    readonly property string keyName: "diacritics"
    readonly property string keyDesc: "Fix Czech diacritics"
    readonly property var entry: ({ name: keyName, label: "Fix text", desc: keyDesc })

    readonly property string filePath: {
        const env = Quickshell.env("QS_DIACRITICS_FILE")
        return env ? String(env) : Appearance.dir + "/diacritics.json"
    }
    readonly property string dir: filePath.substring(0, filePath.lastIndexOf("/")) || "/"
    readonly property string bindsPath: {
        const env = Quickshell.env("QS_DIACRITICS_BINDS_FILE")
        return env ? String(env) : dir + "/diacritics-binds.txt"
    }
    readonly property string modelsDir: {
        const env = Quickshell.env("QS_DIACRITICS_MODELS_DIR")
        if (env) return String(env)
        const x = Quickshell.env("XDG_DATA_HOME")
        return (x ? String(x) : Quickshell.env("HOME") + "/.local/share") + "/diacritics/models"
    }

    // SUPER + SHIFT + D: Super+D is the launcher, so the Shift variant is the nearest free key that is easy to remember
    // (no bind of the config uses it; the Settings key row checks the live binds before it applies another key)
    readonly property var defaults: ({
        key: "SUPER + SHIFT + D",
        model: "gemma-4-12B-it-qat-UD-Q4_K_XL.gguf",
        idle_timeout_s: 600,
        ignored_classes: ["kitty", "foot", "footclient", "alacritty", "ghostty", "com.mitchellh.ghostty", "org.wezfurlong.wezterm",
                          "wezterm", "konsole", "org.kde.konsole", "xterm", "uxterm", "urxvt", "st", "terminator",
                          "gnome-terminal-server", "org.gnome.ptyxis", "com.gexperts.tilix", "tilix",
                          "com.herdr.terminal", "dotfiles.scratchpad"],
        show_text: true
    })
    // idle unload choices (seconds); any other saved number is accepted and shown as Custom
    readonly property var idleValues: [30, 60, 300, 600, 1800, 3600]
    readonly property var idleLabels: ["30 sec", "1 min", "5 min", "10 min", "30 min", "1 hour"]
    readonly property var keys: ["key", "model", "idle_timeout_s", "ignored_classes", "show_text"]
    readonly property int maxClasses: 100
    readonly property int maxClassLen: 80

    property string key: defaults.key
    property string model: defaults.model
    property int idleTimeoutS: defaults.idle_timeout_s
    property var ignoredClasses: defaults.ignored_classes.slice()
    property bool showText: defaults.show_text
    property var extra: ({})          // unknown keys of the file, written back unchanged

    // ---- PrefSwitch / PageReset store ----
    function value(k) { return k === "show_text" ? showText : k === "idle_timeout_s" ? idleTimeoutS : k === "model" ? model : k === "key" ? key : ignoredClasses }
    function overridden(k) { return JSON.stringify(value(k)) !== JSON.stringify(defaults[k]) }
    function set(k, v) {
        if (k === "show_text") showText = !!v
        else if (k === "idle_timeout_s") idleTimeoutS = Math.min(604800, Math.max(0, Math.round(Number(v)) || 0))
        else if (k === "model") { if (!validModel(v)) return false; model = v }
        else return false
        commit()
        return true
    }
    function unset(k) {
        if (k === "key") setKeys(keyName, defaults.key)
        else if (k === "ignored_classes") restoreClasses()
        else set(k, defaults[k])
    }
    readonly property bool changed: keys.some(k => overridden(k))
    function resetAll() { for (const k of keys) unset(k) }
    function validModel(v) { return typeof v === "string" && /^[^\/\x00-\x1f]{1,200}\.gguf$/.test(v) && v !== "." && v !== ".." }

    // ---- ignored window classes ----
    function normalizeClass(t) { return String(t).trim().toLowerCase() }
    // -> "" (added) or why not
    function addClass(t) {
        const c = normalizeClass(t)
        if (c === "") return "Type a window class"
        if (c.length > maxClassLen) return "Too long"
        if (!/^[a-z0-9_.+-]+$/.test(c)) return "Letters, digits and . _ + - only (no spaces)"
        if (ignoredClasses.indexOf(c) >= 0) return "Already in the list"
        if (ignoredClasses.length >= maxClasses) return "The list is full"
        ignoredClasses = ignoredClasses.concat([c])
        commit()
        return ""
    }
    function removeClass(c) { ignoredClasses = ignoredClasses.filter(x => x !== c); commit() }
    function restoreClasses() { ignoredClasses = defaults.ignored_classes.slice(); commit() }

    // ---- models ----
    property var models: []           // file names of modelsDir, sorted
    property bool modelsLoaded: false
    function refreshModels() { if (!lister.running) lister.running = true }
    Process {
        id: lister
        command: ["find", root.modelsDir, "-maxdepth", "1", "-name", "*.gguf", "-printf", "%f\\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.models = text.split("\n").filter(n => n !== "").sort()
                root.modelsLoaded = true
            }
        }
    }

    // ---- key ----
    function keysOf(name) { return name === keyName ? key : "" }
    // the checks for `text` as the key: { keys, error, duplicate (the push-to-talk key it is), conflicts }
    function check(name, text) {
        const p = K.parse(text)
        const out = { keys: p.keys, error: p.error, duplicate: "", conflicts: [] }
        if (p.keys === "") return out
        const ptt = PttPrefs.entries.find(e => K.same(PttPrefs.keysOf(e.name), p.keys))
        if (ptt) out.duplicate = ptt.label
        out.conflicts = K.conflicts(p.keys, PttPrefs.binds, b => root.isOwn(b))
        return out
    }
    // false = refused (not a key, or a push-to-talk key already has it); conflicts with other binds are the caller's to show
    function setKeys(name, text) {
        if (name !== keyName) return false
        const c = check(name, text)
        if (c.error !== "" || c.duplicate !== "") return false
        if (c.keys === key) return true
        key = c.keys
        commit()
        return true
    }
    function isOwn(b) { return String(b.description || "") === keyDesc }
    function bound(name) {
        const want = K.split(key)
        return key !== "" && PttPrefs.binds.some(b => root.isOwn(b) && (b.modmask || 0) === want.mask && K.bindKey(b) === want.key)
    }
    function registered(name) { return true }
    readonly property bool loaded: PttPrefs.loaded

    // ---- files ----
    function parse(text) {
        let o = null
        try { o = JSON.parse(text) } catch (e) {}
        const d = o !== null && typeof o === "object" && !Array.isArray(o) ? o : {}
        const p = typeof d.key === "string" ? K.parse(d.key) : null
        key = p !== null && p.error === "" ? p.keys : defaults.key
        model = validModel(d.model) ? d.model : defaults.model
        idleTimeoutS = Number.isInteger(d.idle_timeout_s) && d.idle_timeout_s >= 0 && d.idle_timeout_s <= 604800 ? d.idle_timeout_s : defaults.idle_timeout_s
        showText = typeof d.show_text === "boolean" ? d.show_text : defaults.show_text
        if (Array.isArray(d.ignored_classes)) {
            const l = []
            for (const c of d.ignored_classes) {
                const n = typeof c === "string" ? normalizeClass(c) : ""
                if (n !== "" && n.length <= maxClassLen && /^[a-z0-9_.+-]+$/.test(n) && l.indexOf(n) < 0 && l.length < maxClasses) l.push(n)
            }
            ignoredClasses = l
        } else ignoredClasses = defaults.ignored_classes.slice()
        const rest = {}
        for (const k of Object.keys(d)) if (k !== "version" && keys.indexOf(k) < 0) rest[k] = d[k]
        extra = rest
    }
    function serialize() {
        return JSON.stringify(Object.assign({}, extra, { version: 1, key: key, model: model, idle_timeout_s: idleTimeoutS,
                                                         ignored_classes: ignoredClasses, show_text: showText })) + "\n"
    }
    // the generated file hypr/hyprland/diacritics.lua reads
    function bindsText() {
        return "# generated by Quickshell (DiacriticsPrefs.qml) from diacritics.json, read by hypr/hyprland/diacritics.lua: do not edit\n"
            + (key !== "" ? key + "|" + keyDesc + "\n" : "")
    }

    function commit() { saver.restart() }
    property string lastText: ""
    Timer {
        id: saver
        interval: 250
        onTriggered: {
            Quickshell.execDetached(["mkdir", "-p", root.dir, root.bindsPath.substring(0, root.bindsPath.lastIndexOf("/")) || "/"])
            writer.restart()
        }
    }
    // mkdir runs detached: a moment before the write
    Timer {
        id: writer
        interval: 150
        onTriggered: {
            root.lastText = root.serialize()
            jsonFile.setText(root.lastText)
            bindsFile.setText(root.bindsText())
        }
    }
    // the binds file differs from the key (first start, json edited by hand): rewrite + apply
    function syncBinds() {
        const want = bindsText()
        if (bindsFile.loadedText === want) return
        Quickshell.execDetached(["mkdir", "-p", bindsPath.substring(0, bindsPath.lastIndexOf("/")) || "/"])
        bindsSync.restart()
    }
    Timer { id: bindsSync; interval: 150; onTriggered: bindsFile.setText(root.bindsText()) }

    Component.onCompleted: { bindsFile.loadedText = bindsFile.text(); jsonFile.text(); syncBinds(); refreshModels() }
    FileView {
        id: jsonFile
        path: root.filePath
        blockLoading: true
        printErrors: false
        watchChanges: true
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: if (!saver.running && !writer.running && text() !== root.lastText) { root.lastText = text(); root.parse(text()); root.syncBinds() }
        onLoadFailed: if (!saver.running && !writer.running) { root.parse(""); root.syncBinds(); root.commit() }
        onSaveFailed: root.applyError = "Could not write " + path
    }
    FileView {
        id: bindsFile
        property string loadedText: ""
        path: root.bindsPath
        blockLoading: true
        printErrors: false
        atomicWrites: true
        onLoaded: loadedText = text()
        onSaved: { loadedText = text(); root.apply() }
        onSaveFailed: root.applyError = "Could not write " + path
    }

    // ---- compositor ----
    property string applyError: ""
    property bool _again: false
    function apply() {
        applyError = ""
        if (applyProc.running) { _again = true; return }
        applyProc.running = true
    }
    Process {
        id: applyProc
        command: [Appearance.hyprctl, "eval", "if diacritics_apply then diacritics_apply() end"]
        stdout: StdioCollector { id: applyOut }
        onExited: code => {
            const out = applyOut.text.trim()
            root.applyError = code === 0 && !/^error/i.test(out) ? "" : (out || "hyprctl failed")
            if (root.applyError !== "") console.warn("diacritics: apply failed: " + root.applyError)
            if (root._again) { root._again = false; root.apply() }
            else PttPrefs.refresh()       // the bind list the row's status and the conflict check read
        }
    }

    IpcHandler {
        target: "diacritics"
        function get(): string { return root.serialize().trim() }
        function key(keys: string): string {
            const c = root.check(root.keyName, keys)
            if (c.error !== "") return c.error
            if (c.duplicate !== "") return "same as " + c.duplicate
            root.setKeys(root.keyName, keys)
            return c.conflicts.length ? "ok, also used by: " + c.conflicts.map(x => x.text).join(", ") : "ok"
        }
        function model(file: string): string { return root.set("model", file) ? "ok" : "bad" }
        function idle(s: string): string { return root.set("idle_timeout_s", Number(s)) ? "ok" : "bad" }
        function show(v: string): string { return root.set("show_text", v === "true") ? "ok" : "bad" }
        function reset(): string { root.resetAll(); return "ok" }
        function refresh(): void { root.refreshModels(); PttPrefs.refresh() }
    }
}
