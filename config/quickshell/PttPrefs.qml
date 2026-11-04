pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "launcher/js/PttKeys.js" as K
import "launcher/js/DictLangs.js" as D

// Push-to-talk keys (Settings > Voice): the hold-to-talk keys, each a keyboard combo or a mouse button in Hyprland's
// bind syntax (launcher/js/PttKeys.js): "ptt-auto" (always there: dictate in the detected language), and per selected
// language "ptt-<code>" (dictate in it) and, but for English, "ptt-<code>-en" (speak it, type English), and "ptt-auto-en"
// (detect the language, type English)
// (launcher/js/DictLangs.js). The selected languages are Settings > Voice > Languages, Czech and English until changed.
// No default keys: all unset until the user picks them. Saved in ${XDG_STATE_HOME:-~/.local/state}/quickshell/ptt.json (QS_PTT_FILE overrides), this singleton
// is the only writer:
//   { "version": 1, "keys": { "ptt-cs": "SUPER + F9", "ptt-en": "mouse:276" }, "through": { "ptt-en": false },
//     "languages": ["cs", "en", "ja"] }
//   keys      name -> key string; a missing name = no key
//   languages the selected language codes; missing = Czech and English (a file from before languages were selectable)
//             Keys of a language that is not selected stay in the file (no bind is made for them) and return with it.
//   through   name -> the key / click also reaches the focused window (bind option non_consuming); default: on for a
//             mouse button (side buttons keep working as back / forward), off for a key (it would type)
// Applying: every change also rewrites the generated ptt-binds.txt next to it (QS_PTT_BINDS_FILE; one
// "<keys>|quickshell:<name>|<description>[|non_consuming]" line per key), which hypr/hyprland/ptt.lua binds at every
// config load, then runs `hyprctl eval 'ptt_apply()'` so the change works at once (ptt.lua removes only its own binds).
// PttShortcuts.qml registers the global shortcuts (appid "quickshell", the entry names).
// Conflicts (checked before a key is applied, Settings > Voice): `hyprctl binds -j` (another bind on the same
// modifiers + key / button; a `global` dispatcher = another app's global shortcut) and the other two keys; our own binds
// are told apart by their description. `hyprctl globalshortcuts -j` says whether ours are registered.
// The object doubles as a PrefSwitch store for the click-through switches (key "through:<name>").
//   qs ipc call ptt get | set <name> <keys> | unset <name> | reset | refresh | languages | addlang <code> | rmlang <code>
Singleton {
    id: root

    readonly property string appid: "quickshell"
    // [{ name, lang, translate, label, desc, service, pill }]: Auto, then each selected language's keys (DictLangs.entriesFor)
    readonly property var entries: D.entriesFor(languages)
    readonly property var names: entries.map(e => e.name)
    function entry(name) { return entries.find(e => e.name === name) || null }

    readonly property string filePath: {
        const env = Quickshell.env("QS_PTT_FILE")
        return env ? String(env) : Appearance.dir + "/ptt.json"
    }
    readonly property string bindsPath: {
        const env = Quickshell.env("QS_PTT_BINDS_FILE")
        return env ? String(env) : Appearance.dir + "/ptt-binds.txt"
    }
    readonly property string dir: filePath.substring(0, filePath.lastIndexOf("/")) || "/"

    // ---- saved state ----
    property var data: ({ keys: {}, through: {}, languages: null })
    // the selected languages (codes, in the order added); data.languages null = the default Czech + English
    readonly property var languages: languagesOf(data)
    function languagesOf(d) { return d.languages === null || d.languages === undefined ? D.DEFAULTS.slice() : d.languages }
    function hasLanguage(code) { return languages.indexOf(code) >= 0 }
    function setLanguages(list) {
        const l = D.normalize(list)
        const d = copy()
        d.languages = JSON.stringify(l) === JSON.stringify(D.DEFAULTS) ? null : l
        // a removed language keeps its stored keys (no binds are made for it; adding it again brings them back), except
        // one that now collides with the key of an entry that is in use
        const live = D.entriesFor(l).map(e => e.name)
        for (const n of Object.keys(d.keys)) {
            const mine = live.indexOf(n) >= 0 && entries.every(e => e.name !== n)    // an entry this change brings back
            if (mine && live.some(o => o !== n && d.keys[o] && K.same(d.keys[o], d.keys[n]))) delete d.keys[n]
        }
        commit(d)
    }
    function addLanguage(code) { if (D.isCode(code) && !hasLanguage(code)) setLanguages(languages.concat([code])) }
    function removeLanguage(code) { if (hasLanguage(code)) setLanguages(languages.filter(c => c !== code)) }

    function keysOf(name) { return data.keys[name] || "" }
    function throughOf(name) { const t = data.through[name]; return t !== undefined ? t : K.isMouse(keysOf(name)) }
    readonly property bool anySet: entries.some(e => keysOf(e.name) !== "")
    readonly property bool changed: Object.keys(data.keys).length > 0 || Object.keys(data.through).length > 0 || data.languages !== null

    // PrefSwitch store ("through:<name>")
    function value(key) { return throughOf(key.replace(/^through:/, "")) }
    function overridden(key) { return data.through[key.replace(/^through:/, "")] !== undefined }
    function set(key, v) { setThrough(key.replace(/^through:/, ""), !!v) }
    function unset(key) { setThrough(key.replace(/^through:/, ""), undefined) }

    // the checks for `keys` as the key of `name`: { keys, error, duplicate (the other entry's label), conflicts }
    function check(name, text) {
        const p = K.parse(text)
        const out = { keys: p.keys, error: p.error, duplicate: "", conflicts: [] }
        if (p.keys === "") return out
        const other = entries.find(e => e.name !== name && K.same(keysOf(e.name), p.keys))
        if (other) out.duplicate = other.label
        out.conflicts = K.conflicts(p.keys, binds, b => root.isOwn(b))
        return out
    }
    // false = refused (not a key, or another push-to-talk key already has it); conflicts with other binds are the
    // caller's to show first (Settings asks for "Apply anyway")
    function setKeys(name, text) {
        if (!entry(name)) return false
        const c = check(name, text)
        if (c.error !== "" || c.duplicate !== "") return false
        if (c.keys === keysOf(name)) return true
        const d = copy()
        if (c.keys === "") delete d.keys[name]
        else d.keys[name] = c.keys
        commit(d)
        return true
    }
    function setThrough(name, on) {
        if (!entry(name)) return
        const d = copy()
        if (on === undefined || on === K.isMouse(keysOf(name))) delete d.through[name]
        else d.through[name] = on
        commit(d)
    }
    function resetAll() { commit({ keys: {}, through: {}, languages: null }) }
    function copy() { return { keys: Object.assign({}, data.keys), through: Object.assign({}, data.through), languages: data.languages } }

    // ---- files ----
    function parse(text) {
        const out = { keys: {}, through: {}, languages: null }
        if (typeof text !== "string" || text.length > 16384) return out
        let o
        try { o = JSON.parse(text) } catch (e) { return out }
        if (!o || typeof o !== "object") return out
        if (Array.isArray(o.languages)) {
            const l = D.normalize(o.languages)
            out.languages = JSON.stringify(l) === JSON.stringify(D.DEFAULTS) ? null : l
        }
        for (const n of D.entriesFor(D.LANGS.map(x => x[0])).map(e => e.name)) {       // every language: keys outlive a removed language
            if (o.keys && typeof o.keys[n] === "string") { const p = K.parse(o.keys[n]); if (p.keys !== "") out.keys[n] = p.keys }
            if (o.through && typeof o.through[n] === "boolean") out.through[n] = o.through[n]
        }
        return out
    }
    function serialize(d) { return JSON.stringify(Object.assign({ version: 1, keys: d.keys, through: d.through },
                                            Array.isArray(d.languages) ? { languages: d.languages } : {})) + "\n" }
    // the generated file hypr/hyprland/ptt.lua reads
    function bindsText(d) {
        let t = "# generated by Quickshell (PttPrefs.qml) from ptt.json, read by hypr/hyprland/ptt.lua: do not edit\n"
        for (const e of D.entriesFor(languagesOf(d))) {
            const k = d.keys[e.name]
            if (!k) continue
            const through = d.through[e.name] !== undefined ? d.through[e.name] : K.isMouse(k)
            t += k + "|" + appid + ":" + e.name + "|" + e.desc + (through ? "|non_consuming" : "") + "\n"
        }
        return t
    }

    function commit(d) {
        data = d
        if (!saver.running) Quickshell.execDetached(["mkdir", "-p", dir, bindsPath.substring(0, bindsPath.lastIndexOf("/")) || "/"])
        saver.restart()
    }
    property var lastText: null              // the last text written / read (null: nothing yet)
    Timer {
        id: saver
        interval: 200        // mkdir runs detached: a moment before the write
        onTriggered: {
            root.lastText = root.serialize(root.data)
            jsonFile.setText(root.lastText)
            bindsFile.setText(root.bindsText(root.data))
        }
    }
    function applyLoaded(t) {
        if (saver.running || t === lastText) return
        lastText = t
        data = parse(t)
        syncBinds()
    }
    // the binds file differs from ptt.json (first start with an older file, ptt.json edited by hand): rewrite + apply
    function syncBinds() {
        const want = bindsText(data)
        const have = bindsFile.loadedText
        if (have === want || (have === "" && !anySet)) return
        bindsFile.setText(want)
    }

    Component.onCompleted: { bindsFile.loadedText = bindsFile.text(); jsonFile.text(); syncBinds() }
    FileView {
        id: jsonFile
        path: root.filePath
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyLoaded(text())
        onLoadFailed: root.applyLoaded("")
        onSaveFailed: root.applyError = "Could not write " + path
    }
    FileView {
        id: bindsFile
        property string loadedText: ""
        path: root.bindsPath
        blockLoading: true
        printErrors: false
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
        command: [Appearance.hyprctl, "eval", "if ptt_apply then ptt_apply() end"]
        stdout: StdioCollector { id: applyOut }
        onExited: code => {
            const out = applyOut.text.trim()
            root.applyError = code === 0 && !/^error/i.test(out) ? "" : (out || "hyprctl failed")
            if (root.applyError !== "") console.warn("ptt: apply failed: " + root.applyError)
            if (root._again) { root._again = false; root.apply() }
            else root.refresh()
        }
    }

    property var binds: []                   // hyprctl binds -j
    property var shortcuts: []               // registered global shortcut ids (hyprctl globalshortcuts -j)
    property bool loaded: false              // first binds answer arrived
    // ours: any push-to-talk bind (also one of a language that was just removed and is not unbound yet)
    function isOwn(b) { return /\(global\)$/.test(String(b.dispatcher || "")) && /^Push-to-talk: /.test(String(b.description || "")) }
    function bound(name) {
        const e = entry(name), k = keysOf(name)
        const want = K.split(k)
        return k !== "" && binds.some(b => b.description === e.desc && (b.modmask || 0) === want.mask && K.bindKey(b) === want.key)
    }
    function registered(name) { return shortcuts.indexOf(appid + ":" + name) >= 0 }
    function refresh() {
        if (!bindsProc.running) bindsProc.running = true
        if (!gsProc.running) gsProc.running = true
    }
    Process {
        id: bindsProc
        command: [Appearance.hyprctl, "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const a = JSON.parse(text); if (Array.isArray(a)) { root.binds = a; root.loaded = true } } catch (e) {}
            }
        }
    }
    Process {
        id: gsProc
        command: [Appearance.hyprctl, "globalshortcuts", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const a = JSON.parse(text); if (Array.isArray(a)) root.shortcuts = a.map(s => String(s.name)) } catch (e) {}
            }
        }
    }
    // the page is open (Settings > Voice): keep binds fresh across config reloads
    property int watchers: 0
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "configreloaded" && root.watchers > 0) root.refresh() }
    }

    IpcHandler {
        target: "ptt"
        function get(): string { return root.serialize(root.data).trim() }
        function set(name: string, keys: string): string {
            const c = root.check(name, keys)
            if (!root.entry(name)) return "bad name"
            if (c.error !== "") return c.error
            if (c.duplicate !== "") return "same as " + c.duplicate
            root.setKeys(name, keys)
            return c.conflicts.length ? "ok, also used by: " + c.conflicts.map(x => x.text).join(", ") : "ok"
        }
        function unset(name: string): string { return root.setKeys(name, "") ? "ok" : "bad name" }
        function reset(): string { root.resetAll(); return "ok" }
        function languages(): string { return root.languages.join(",") }
        function addlang(code: string): string { if (!D.isCode(code)) return "unknown language"; root.addLanguage(code); return "ok" }
        function rmlang(code: string): string { root.removeLanguage(code); return "ok" }
        function refresh(): void { root.refresh() }
    }
}
