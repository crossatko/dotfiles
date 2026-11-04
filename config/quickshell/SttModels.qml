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
// (config/dictation, whisper.chosen_models: same defaults and name check) at every key press and reloads on a change:
// a chosen model that is not installed is its `no-model` error, never another model.
//   { "version": 1, "live": "large-v3-turbo", "final": "large-v3" }
//   live   the model of the live (streaming) passes while a key is held; any model, speed matters
//   final  the model of the pass after release AND of translation; only a model that can translate
// The object doubles as the prefs store of the Settings controls (value / set / unset / overridden / defaults / keys /
// changed / resetAll).
//
// For the pill: `noneInstalled`, `missingMessage` ("Download a speech model in settings"), `statusMessage` (what to show
// instead of recording, "" = ready), `pathOf(name)`, `liveModel` / `finalModel`. Call `refresh()` once when you need
// fresh install state (the section does when it opens); `loaded` is false until the first answer.
//   qs ipc call sttmodels get | list | download <name> | cancel | remove <name> | role <live|final> <name>
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
    readonly property var defaults: ({ live: "large-v3-turbo", final: "large-v3" })
    readonly property var keys: ["live", "final"]
    property string live: defaults.live
    property string final_: defaults.final        // `final` is reserved in QML
    readonly property string liveModel: live
    readonly property string finalModel: final_
    function value(key) { return key === "live" ? live : key === "final" ? final_ : undefined }
    function overridden(key) { return value(key) !== defaults[key] }
    function unset(key) { applyRole(key, defaults[key]) }
    readonly property bool changed: keys.some(k => overridden(k))
    function resetAll() { for (const k of keys) unset(k); notice = "" }
    // set() is the store call: it refuses what roleProblem() refuses (the section shows the reason in `notice`)
    function set(key, name) { return setRole(key, name) === "" }

    // ---- catalog + install state (the helper's `list`) ----
    property var models: []                    // [{name,label,file,size,vramGb,translate,czech,recommended,note,installed,damaged,diskBytes,partialBytes}]
    property string modelsDir: ""
    property bool loaded: false
    property string listError: ""
    function model(name) { return models.find(m => m.name === name) || null }
    function labelOf(name) { const m = model(name); return m ? m.label : name }
    function isInstalled(name) { const m = model(name); return m !== null && m.installed }
    readonly property bool anyInstalled: models.some(m => m.installed)
    readonly property bool noneInstalled: loaded && !anyInstalled
    function pathOf(name) { return modelsDir !== "" && model(name) ? modelsDir + "/" + model(name).file : "" }

    // what the pill shows instead of recording: "" = both jobs have an installed model
    function problemOf(role) {
        const name = value(role)
        if (!loaded) return ""
        if (noneInstalled) return missingMessage
        if (!model(name)) return "Unknown speech model " + name
        if (!isInstalled(name)) return labelOf(name) + " is not installed, pick or download one in settings"
        return ""
    }
    readonly property string statusMessage: problemOf("live") || problemOf("final")

    // ---- role changes ----
    property string notice: ""                 // the reason the last role change was refused (cleared by the next good one / a timer)
    Timer { id: noticeTimer; interval: 8000; onTriggered: sm.notice = "" }
    // "" = fine, else why `name` cannot do `role`
    function roleProblem(role, name) {
        const m = model(name)
        if (!m) return "Unknown model"
        if (role === "final" && !m.translate)
            return m.label + " cannot translate, and the final pass also translates. Pick Large v3 or its q5_0 version."
        if (!m.installed) return m.label + " is not installed yet. Download it first."
        return ""
    }
    function setRole(role, name) {
        if (keys.indexOf(role) < 0) return "Unknown role"
        const p = roleProblem(role, name)
        notice = p
        if (p !== "") { noticeTimer.restart(); return p }
        noticeTimer.stop()
        applyRole(role, name)
        return ""
    }
    function applyRole(role, name) {
        if (role === "live") live = name
        else final_ = name
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
        const ok = k => o !== null && typeof o === "object" && typeof o[k] === "string" && /^[A-Za-z0-9._-]{1,64}$/.test(o[k])
        live = ok("live") ? o.live : defaults.live
        final_ = ok("final") ? o.final : defaults.final
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
    Timer { id: writer; interval: 150; onTriggered: fileView.setText(JSON.stringify({ version: 1, live: sm.live, final: sm.final_ }) + "\n") }

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
        function get(): string { return JSON.stringify({ live: sm.live, final: sm.final_, installed: sm.models.filter(m => m.installed).map(m => m.name), status: sm.statusMessage, downloading: sm.downloading, phase: sm.phase, progress: sm.progress }) }
        function list(): string { return JSON.stringify(sm.models) }
        function download(name: string): string { return sm.download(name) ? "ok" : "busy or unknown" }
        function cancel(): string { sm.cancel(); return "ok" }
        function remove(name: string): string { sm.remove(name); return "ok" }
        function role(role: string, name: string): string { return sm.setRole(role, name) || "ok" }
    }
}
