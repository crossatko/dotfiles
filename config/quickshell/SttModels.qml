pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Speech models for dictation (whisper.cpp ggml files): the catalog, what is installed, the one running download, and
// which model does which job. All the file work is bin/stt-models (Python; catalog bin/stt-models.json: official
// Hugging Face URLs, sizes, sha256, capabilities). Files live in ${XDG_DATA_HOME:-~/.local/share}/dictation/models/
// ggml-<name>.bin, never in the repo, and nothing is ever downloaded without a click (Download in SttModelsSection).
// QS_STT_HELPER overrides the script, QS_STT_MODELS_FILE the prefs file (tests; the helper also takes
// QS_STT_MODELS_DIR / QS_STT_CATALOG / QS_STT_ALLOW_HTTP, see its header).
//
// Roles, saved in ${XDG_STATE_HOME:-~/.local/state}/quickshell/stt-models.json (this singleton is the only writer; a
// missing key = the default; watched, so a hand edit shows here too). The dictation service reads the same file
// (config/dictation, whisper.chosen_models: same defaults and name check) at every key press and reloads when the pair
// of the session's mode differs from the loaded one: a chosen model that is not installed is its `no-model` error,
// never another model. The choice is per mode (en = English, cs = Czech and every other language, translate = speak
// Czech, type English); only explicit choices are saved, so a default can follow what is installed:
//   { "version": 2, "en": { "live": "futo-small-en", "final": "large-v3-turbo" }, "cs": { ... }, "translate": { ... } }
//   live   the fast model: the live (streaming) passes while a key is held
//   final  the full model: the pass after release (and translation: only a model that can translate)
// Defaults: en live = futo-small-en when installed, else large-v3-turbo, full large-v3-turbo; cs and translate: large-v3-turbo / large-v3.
// An English-only model (catalog "english") is refused for cs and translate. A version 1 file ({live, final}) is read
// for every mode and rewritten as version 2 at the next change.
// The object doubles as the prefs store of the Settings controls: keys are "<mode>.<role>" (value / set / unset /
// overridden / keys / changed / resetAll).
//
// For the pill: `noneInstalled`, `missingMessage` ("Download a speech model in settings"), `statusFor(modeKey)` (what to
// show instead of recording, "" = ready), `modeKeyOf(serviceMode)`, `pathOf(name)`. Call `refresh()` once when you need
// fresh install state (the section does when it opens); `loaded` is false until the first answer.
//   qs ipc call sttmodels get | list | download <name> | cancel | remove <name> | role <en|cs|translate> <live|final> <name>
Singleton {
    id: sm

    readonly property string script: Quickshell.env("QS_STT_HELPER") || (Quickshell.shellDir + "/bin/stt-models")
    readonly property string filePath: {
        const env = Quickshell.env("QS_STT_MODELS_FILE")
        return env ? String(env) : Appearance.dir + "/stt-models.json"   // next to appearance.json
    }
    readonly property string dir: filePath.substring(0, filePath.lastIndexOf("/")) || "/"

    readonly property string missingMessage: "Download a speech model in settings"

    // ---- roles (prefs store interface) ----
    readonly property string englishFast: "futo-small-en"
    readonly property var modes: [
        { key: "en", label: "English" },
        { key: "cs", label: "Czech", info: "Czech and every other language, and auto." },
        { key: "translate", label: "Czech to English", info: "Speak Czech, type English (translate)." }
    ]
    readonly property var roles: ["live", "final"]
    readonly property var keys: modes.flatMap(m => roles.map(r => m.key + "." + r))
    property var choice: ({})                     // explicit choices only: { en: { live: NAME, final: NAME }, ... }
    function defaultOf(mode, role) {
        if (role === "final") return mode === "en" ? "large-v3-turbo" : "large-v3"
        const f = model(englishFast)       // as the service: the file exists (the service has no catalog to check its size)
        return mode === "en" && f !== null && f.diskBytes > 0 ? englishFast : "large-v3-turbo"
    }
    function pick(mode, role) { return (choice[mode] && choice[mode][role]) || defaultOf(mode, role) }
    function _split(key) { const i = key.indexOf("."); return [key.substring(0, i), key.substring(i + 1)] }
    function value(key) { const k = _split(key); return pick(k[0], k[1]) }
    function overridden(key) { const k = _split(key); return !!(choice[k[0]] && choice[k[0]][k[1]]) && value(key) !== defaultOf(k[0], k[1]) }
    function unset(key) { const k = _split(key); applyRole(k[0], k[1], "") }
    readonly property bool changed: keys.some(k => overridden(k))
    function resetAll() { choice = ({}); notice = ""; saver.restart() }
    // set() is the store call: it refuses what roleProblem() refuses (the section shows the reason in `notice`)
    function set(key, name) { const k = _split(key); return setRole(k[0], k[1], name) === "" }
    // the service mode ("en", "cs", "auto", "translate:cs", ...) -> the key above (as whisper.model_mode)
    function modeKeyOf(serviceMode) { return serviceMode === "en" ? "en" : /^translate/.test(serviceMode) ? "translate" : "cs" }

    // ---- catalog + install state (the helper's `list`) ----
    property var models: []                    // [{name,label,file,size,vramGb,translate,english,local,czech,recommended,note,installed,damaged,diskBytes,partialBytes}]
    property string modelsDir: ""
    property bool loaded: false
    property string listError: ""
    function model(name) { return models.find(m => m.name === name) || null }
    function labelOf(name) { const m = model(name); return m ? m.label : name }
    function isInstalled(name) { const m = model(name); return m !== null && m.installed }
    readonly property bool anyInstalled: models.some(m => m.installed)
    readonly property bool noneInstalled: loaded && !anyInstalled
    function pathOf(name) { return modelsDir !== "" && model(name) ? modelsDir + "/" + model(name).file : "" }

    // what the pill shows instead of recording in a mode: "" = both jobs have an installed model that fits
    function problemOf(mode, role) {
        const name = pick(mode, role)
        if (!loaded) return ""
        if (noneInstalled) return missingMessage
        const m = model(name)
        if (!m) return "Unknown speech model " + name
        if (!m.installed) return m.label + " is not installed, pick or add one in settings"
        return fitProblem(mode, role, m)
    }
    function statusFor(mode) { return problemOf(mode, "live") || problemOf(mode, "final") }

    // ---- role changes ----
    property string notice: ""                 // the reason the last role change was refused (cleared by the next good one / a timer)
    Timer { id: noticeTimer; interval: 8000; onTriggered: sm.notice = "" }
    // "" = fine, else why model `m` cannot do `role` in `mode` (installed or not): English-only models serve English
    // only; the full pass of translate mode translates
    function fitProblem(mode, role, m) {
        if (m.english && mode !== "en") return m.label + " is English only."
        if (mode === "translate" && role === "final" && !m.translate)
            return m.label + " cannot translate, and the full pass translates. Pick Large v3 or its q5_0 version."
        return ""
    }
    // "" = fine, else why `name` cannot do `role` in `mode`
    function roleProblem(mode, role, name) {
        const m = model(name)
        if (!m) return "Unknown model"
        const fit = fitProblem(mode, role, m)
        if (fit !== "") return fit
        if (!m.installed) return m.local ? m.label + " is not installed. Copy your file to " + (pathOf(name) || m.file) + "."
                                         : m.label + " is not installed yet. Download it first."
        return ""
    }
    function setRole(mode, role, name) {
        if (!modes.some(x => x.key === mode) || roles.indexOf(role) < 0) return "Unknown role"
        const p = roleProblem(mode, role, name)
        notice = p
        if (p !== "") { noticeTimer.restart(); return p }
        noticeTimer.stop()
        applyRole(mode, role, name)
        return ""
    }
    // name "" = back to the default
    function applyRole(mode, role, name) {
        const c = Object.assign({}, choice)
        const e = Object.assign({}, c[mode] || {})
        if (name === "") delete e[role]; else e[role] = name
        if (Object.keys(e).length === 0) delete c[mode]; else c[mode] = e
        choice = c
        saver.restart()
    }

    // ---- listing ----
    function refresh() {
        if (lister.running) { _listAgain = true; return }
        lister.command = ["python3", "-I", script, "list"]
        lister.running = true
    }
    property bool _listAgain: false
    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    sm.models = d.models
                    sm.modelsDir = d.dir
                    sm.listError = ""
                    sm.loaded = true
                } catch (e) {
                    sm.listError = "model helper failed"     // `loaded` stays as it was: no false "no model"
                }
            }
        }
        onExited: if (sm._listAgain) { sm._listAgain = false; sm.refresh() }
    }

    // ---- the one running download ----
    // phase: "" | "downloading" | "retrying" | "verifying"; progress 0..1 (verifying: hashing progress)
    property string downloading: ""            // model name, "" = none
    property string phase: ""
    property real progress: 0
    property real bytes: 0
    property real bps: 0
    property real eta: -1                      // seconds, -1 unknown
    property string retryNote: ""
    property var failures: ({})                // name -> { code, message, resumable } of its last failed download
    readonly property bool busy: downloading !== ""

    function download(name) {
        if (busy || !model(name)) return false
        const f = Object.assign({}, failures); delete f[name]; failures = f
        downloading = name; phase = "downloading"; progress = 0; bytes = 0; bps = 0; eta = -1; retryNote = ""
        _terminal = false
        dl.command = ["python3", "-I", script, "download", name]
        dl.running = true
        return true
    }
    // SIGTERM to the exact helper process: it keeps the partial file so a later Download resumes
    function cancel() { if (dl.running) dl.signal(15) }
    function discardPartial(name) { runSimple(["discard", name]) }
    function remove(name) { if (name !== downloading) runSimple(["delete", name]) }
    function runSimple(args) {
        const p = simpleComp.createObject(sm, { command: ["python3", "-I", script].concat(args) })
        p.running = true
    }
    Component {
        id: simpleComp
        Process {
            onExited: { sm.refresh(); destroy() }
        }
    }

    property bool _terminal: false             // the helper reported done / error / cancelled
    function onEvent(e) {
        if (e.event === "start") { bytes = e.from; progress = e.total > 0 ? e.from / e.total : 0 }
        else if (e.event === "progress") {
            phase = "downloading"; retryNote = ""
            progress = e.pct / 100; bytes = e.bytes; bps = e.bps; eta = e.eta === null ? -1 : e.eta
        } else if (e.event === "retry") { phase = "retrying"; retryNote = e.message }
        else if (e.event === "verifying") { phase = "verifying"; progress = e.pct / 100 }
        else if (e.event === "done") _terminal = true
        else if (e.event === "cancelled") _terminal = true
        else if (e.event === "error") {
            _terminal = true
            const f = Object.assign({}, failures)
            f[e.name || downloading] = { code: e.code, message: e.message, resumable: e.resumable === true }
            failures = f
        }
    }
    Process {
        id: dl
        stdout: SplitParser {
            onRead: line => { try { sm.onEvent(JSON.parse(line)) } catch (e) {} }
        }
        onExited: (code, status) => {
            if (!sm._terminal && sm.downloading !== "") {          // killed or crashed without a word
                const f = Object.assign({}, sm.failures)
                f[sm.downloading] = { code: "io", message: "The download helper stopped unexpectedly", resumable: true }
                sm.failures = f
            }
            sm.downloading = ""; sm.phase = ""
            sm.refresh()
        }
    }

    // ---- format helpers (shared by the section and the rows) ----
    function gb(bytes) { return (bytes / 1e9).toFixed(bytes >= 1e10 ? 0 : 1) + " GB" }
    function mb(bytes) { return Math.round(bytes / 1e6) + " MB" }
    function sizeText(bytes) { return bytes >= 1e9 ? gb(bytes) : mb(bytes) }
    function speedText(b) { return b >= 1e6 ? (b / 1e6).toFixed(1) + " MB/s" : Math.round(b / 1e3) + " kB/s" }
    function etaText(s) { return s < 0 ? "" : s < 60 ? s + " s left" : s < 3600 ? Math.round(s / 60) + " min left" : (s / 3600).toFixed(1) + " h left" }

    // ---- prefs file ----
    // as the service reads it (whisper.chosen_models): unreadable / missing / malformed = that role's default
    function parse(text) {
        let o = null
        try { o = JSON.parse(text) } catch (e) {}
        const isObj = v => v !== null && typeof v === "object" && !Array.isArray(v)
        const ok = (src, k) => isObj(src) && typeof src[k] === "string" && /^[A-Za-z0-9._-]{1,64}$/.test(src[k])
        const c = {}
        for (const m of modes) {
            for (const r of roles) {
                // the mode's own entry, else a version 1 file's top level (applies to every mode)
                const src = ok(o && o[m.key], r) ? o[m.key] : ok(o, r) ? o : null
                if (src) { c[m.key] = c[m.key] || {}; c[m.key][r] = src[r] }
            }
        }
        choice = c
    }
    Timer {
        id: saver
        interval: 300
        onTriggered: {
            Quickshell.execDetached(["mkdir", "-p", sm.dir])
            writer.start()
        }
    }
    // mkdir runs detached: give it a moment before the write
    Timer { id: writer; interval: 150; onTriggered: fileView.setText(JSON.stringify(Object.assign({ version: 2 }, sm.choice)) + "\n") }

    Component.onCompleted: { fileView.text(); refresh() }
    FileView {
        id: fileView
        path: sm.filePath
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: if (!saver.running && !writer.running) sm.parse(text())    // a pending own write wins
        onLoadFailed: if (!saver.running && !writer.running) sm.parse("")
    }

    IpcHandler {
        target: "sttmodels"
        function get(): string { return JSON.stringify({ choice: Object.fromEntries(sm.modes.map(m => [m.key, { live: sm.pick(m.key, "live"), final: sm.pick(m.key, "final") }])), installed: sm.models.filter(m => m.installed).map(m => m.name), status: Object.fromEntries(sm.modes.map(m => [m.key, sm.statusFor(m.key)])), downloading: sm.downloading, phase: sm.phase, progress: sm.progress }) }
        function list(): string { return JSON.stringify(sm.models) }
        function download(name: string): string { return sm.download(name) ? "ok" : "busy or unknown" }
        function cancel(): string { sm.cancel(); return "ok" }
        function remove(name: string): string { sm.remove(name); return "ok" }
        function role(mode: string, role: string, name: string): string { return sm.setRole(mode, role, name) || "ok" }
    }
}
