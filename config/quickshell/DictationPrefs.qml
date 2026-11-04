pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Dictation preferences (Settings > Voice > Dictation): microphone, GPU and which one, model idle timeout, vocabulary
// hints, pill at the bottom. Saved in
// ${XDG_STATE_HOME:-~/.local/state}/quickshell/dictation-prefs.json (QS_DICTATION_PREFS_FILE overrides), this singleton
// is the only writer (atomic: temp file + rename); the file is watched, so a hand edit shows here too. The dictation
// service (config/dictation) reads the same file at every key press and applies it to the next dictation; a missing or
// malformed file / field = that field's default.
//   { "version": 1, "mic": "", "gpu": true, "gpu_device": 0, "idle_timeout_s": 600, "prompt_hints": false, "pill_bottom": false }
// Keys this file does not know (the service's pause_silence_s / trailing_space, hand-written) are kept when it saves.
//   mic             PipeWire / PulseAudio source name (node.name); "" = follow the system default source
//   gpu             use the GPU (Vulkan); false = CPU
//   gpu_device      which GPU (index of `dictation-whisper --list-devices`, GpuDevices.qml); 0 = the first. Only used with gpu
//   idle_timeout_s  seconds without dictation before the model is unloaded; 0 = never
//   prompt_hints    use the replacement words as recognition hints (transcribe only, never when translating).
//                   THE source of truth for hints: DictationWords mirrors it into dictation-words.json ("hints").
//   pill_bottom     the pill sits at the bottom edge of the screen even with the bar at the top (DictationPill); the service ignores it
// The object is a PrefSwitch / PageReset store for gpu, pill_bottom and prompt_hints (value / set / unset / overridden / changed /
// resetAll); the mic and the timeout are set through the same set().
//   qs ipc call dictationprefs get | set <mic|gpu|device|idle|hints|pill> <value> | reset | sources
Singleton {
    id: dp

    readonly property string filePath: {
        const env = Quickshell.env("QS_DICTATION_PREFS_FILE")
        return env ? String(env) : Appearance.dir + "/dictation-prefs.json"
    }
    readonly property string dir: filePath.substring(0, filePath.lastIndexOf("/")) || "/"
    // test hook: a program printing `pactl --format=json list sources`
    readonly property string pactl: Quickshell.env("QS_DICTATION_PACTL") || "pactl"

    readonly property var defaults: ({ mic: "", gpu: true, gpu_device: 0, idle_timeout_s: 600, prompt_hints: false, pill_bottom: false })
    readonly property var keys: ["mic", "gpu", "gpu_device", "idle_timeout_s", "prompt_hints", "pill_bottom"]
    // idle timeout choices (seconds; 0 = never)
    readonly property var idleValues: [60, 300, 600, 1800, 0]
    readonly property var idleLabels: ["1 min", "5 min", "10 min", "30 min", "Never"]

    property string mic: defaults.mic
    property bool gpu: defaults.gpu
    property int gpuDevice: defaults.gpu_device
    property bool pillBottom: defaults.pill_bottom
    property var extra: ({})          // unknown keys of the file, written back unchanged
    property int idleTimeoutS: defaults.idle_timeout_s
    property bool promptHints: defaults.prompt_hints

    function value(key) {
        return key === "mic" ? mic : key === "gpu" ? gpu : key === "gpu_device" ? gpuDevice : key === "idle_timeout_s" ? idleTimeoutS
            : key === "prompt_hints" ? promptHints : key === "pill_bottom" ? pillBottom : undefined
    }
    function overridden(key) { return value(key) !== defaults[key] }
    function set(key, v) {
        // the same limits as parse(): a value it would drop on the next load is refused here
        if (key === "mic") { if (typeof v !== "string" || v.length > 200 || /[\x00-\x1f]/.test(v)) return false; mic = v }
        else if (key === "gpu") gpu = !!v
        else if (key === "gpu_device") gpuDevice = Math.min(1000, Math.max(0, Math.round(Number(v)) || 0))
        else if (key === "pill_bottom") pillBottom = !!v
        else if (key === "idle_timeout_s") idleTimeoutS = Math.min(604800, Math.max(0, Math.round(Number(v)) || 0))
        else if (key === "prompt_hints") promptHints = !!v
        else return false
        saver.restart()
        return true
    }
    function unset(key) { set(key, defaults[key]) }
    readonly property bool changed: keys.some(k => overridden(k))
    function resetAll() { for (const k of keys) unset(k) }

    // ---- microphones ----
    // [{ name, label }] from `pactl list sources` (monitors of outputs left out); refreshSources() on demand
    property var sources: []
    property bool sourcesLoaded: false
    function sourceLabel(name) {
        const s = sources.find(x => x.name === name)
        return s ? s.label : name
    }
    function refreshSources() {
        if (!lister.running) lister.running = true
    }
    Process {
        id: lister
        command: [dp.pactl, "--format=json", "list", "sources"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const a = JSON.parse(text)
                    if (!Array.isArray(a)) return
                    dp.sources = a.filter(s => typeof s.name === "string" && !/\.monitor$/.test(s.name))
                        .map(s => ({ name: s.name, label: String(s.description || s.name) }))
                    dp.sourcesLoaded = true
                } catch (e) {}
            }
        }
    }

    // ---- file ----
    // as the service reads it: any field that is missing or of the wrong type = its default
    function parse(text) {
        let o = null
        try { o = JSON.parse(text) } catch (e) {}
        const d = o !== null && typeof o === "object" && !Array.isArray(o) ? o : {}
        mic = typeof d.mic === "string" && d.mic.length <= 200 && !/[\x00-\x1f]/.test(d.mic) ? d.mic : defaults.mic
        gpu = typeof d.gpu === "boolean" ? d.gpu : defaults.gpu
        gpuDevice = Number.isInteger(d.gpu_device) ? Math.min(1000, Math.max(0, d.gpu_device)) : defaults.gpu_device
        pillBottom = typeof d.pill_bottom === "boolean" ? d.pill_bottom : defaults.pill_bottom
        const rest = {}
        for (const k of Object.keys(d)) if (k !== "version" && keys.indexOf(k) < 0) rest[k] = d[k]
        extra = rest
        idleTimeoutS = Number.isInteger(d.idle_timeout_s) && d.idle_timeout_s >= 0 && d.idle_timeout_s <= 604800 ? d.idle_timeout_s : defaults.idle_timeout_s
        promptHints = typeof d.prompt_hints === "boolean" ? d.prompt_hints : defaults.prompt_hints
    }
    function serialize() {
        return JSON.stringify(Object.assign({}, extra, { version: 1, mic: mic, gpu: gpu, gpu_device: gpuDevice, idle_timeout_s: idleTimeoutS,
                                                         prompt_hints: promptHints, pill_bottom: pillBottom })) + "\n"
    }
    property string lastText: ""
    Timer {
        id: saver
        interval: 300
        onTriggered: {
            Quickshell.execDetached(["mkdir", "-p", dp.dir])
            writer.restart()
        }
    }
    // mkdir runs detached: a moment before the write
    Timer {
        id: writer
        interval: 150
        onTriggered: { dp.lastText = dp.serialize(); fileView.setText(dp.lastText) }
    }

    Component.onCompleted: fileView.text()
    FileView {
        id: fileView
        path: dp.filePath
        blockLoading: true
        printErrors: false
        watchChanges: true
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: if (!saver.running && !writer.running && text() !== dp.lastText) { dp.lastText = text(); dp.parse(text()) }
        onLoadFailed: if (!saver.running && !writer.running) dp.parse("")
    }

    IpcHandler {
        target: "dictationprefs"
        function get(): string { return dp.serialize().trim() }
        function set(key: string, v: string): string {
            const map = { mic: "mic", gpu: "gpu", device: "gpu_device", idle: "idle_timeout_s", hints: "prompt_hints", pill: "pill_bottom" }
            const k = map[key]
            if (!k) return "unknown key"
            const val = k === "gpu" || k === "prompt_hints" || k === "pill_bottom" ? v === "true" : k === "idle_timeout_s" || k === "gpu_device" ? Number(v) : v
            return dp.set(k, val) ? "ok" : "bad"
        }
        function reset(): string { dp.resetAll(); return "ok" }
        function sources(): string { dp.refreshSources(); return JSON.stringify(dp.sources) }
    }
}
