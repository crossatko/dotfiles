pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "launcher/js/PillPos.js" as P

// Dictation preferences (Settings > Voice > Dictation): microphone, GPU and which one, model idle timeout, vocabulary
// hints, where the pill sits. Saved in
// ${XDG_STATE_HOME:-~/.local/state}/quickshell/dictation-prefs.json (QS_DICTATION_PREFS_FILE overrides), this singleton
// is the only writer (atomic: temp file + rename); the file is watched, so a hand edit shows here too. The dictation
// service (config/dictation) reads the same file at every key press and applies it to the next dictation; a missing or
// malformed file / field = that field's default.
//   { "version": 1, "mic": "", "gpu": true, "gpu_device": 0, "idle_timeout_s": 600, "prompt_hints": false,
//     "pill_edge": "bar", "pill_gap": 2, "pill_x": 0.5, "pill_screen": "", "pill_bottom": false }
// Keys this file does not know (the service's pause_silence_s / trailing_space, hand-written) are kept when it saves.
//   mic             PipeWire / PulseAudio source name (node.name); "" = follow the system default source
//   gpu             use the GPU (Vulkan); false = CPU
//   gpu_device      which GPU (index of `dictation-whisper --list-devices`, GpuDevices.qml); 0 = the first. Only used with gpu
//   idle_timeout_s  seconds without dictation before the model is unloaded; 0 = never
//   prompt_hints    use the replacement words as recognition hints (transcribe only, never when translating).
//                   THE source of truth for hints: DictationWords mirrors it into dictation-words.json ("hints").
//   pill_edge / pill_gap / pill_x / pill_screen  where the pill sits (launcher/js/PillPos.js, PillPlacement); the service ignores them
//   pill_bottom     legacy: read only while pill_edge is missing (true = "bottom"); written as pill_edge === "bottom" for older shells
// The object is a PrefSwitch / PrefSlider / PageReset store (value / set / unset / overridden / defaults / spec / changed /
// resetAll); the mic, the timeout and the pill keys are set through the same set().
//   qs ipc call dictationprefs get | set <mic|gpu|device|idle|hints|pill|edge|gap|x|screen> <value> | reset | sources
Singleton {
    id: dp

    readonly property string filePath: {
        const env = Quickshell.env("QS_DICTATION_PREFS_FILE")
        return env ? String(env) : Appearance.dir + "/dictation-prefs.json"
    }
    readonly property string dir: filePath.substring(0, filePath.lastIndexOf("/")) || "/"
    // test hook: a program printing `pactl --format=json list sources`
    readonly property string pactl: Quickshell.env("QS_DICTATION_PACTL") || "pactl"

    readonly property var defaults: Object.assign({ mic: "", gpu: true, gpu_device: 0, idle_timeout_s: 600, prompt_hints: false }, P.DEFAULTS)
    readonly property var keys: ["mic", "gpu", "gpu_device", "idle_timeout_s", "prompt_hints"].concat(P.KEYS)
    readonly property var spec: P.SPEC
    readonly property var pillKeys: P.KEYS
    // idle timeout choices (seconds; 0 = never)
    readonly property var idleValues: [60, 300, 600, 1800, 0]
    readonly property var idleLabels: ["1 min", "5 min", "10 min", "30 min", "Never"]

    property string mic: defaults.mic
    property bool gpu: defaults.gpu
    property int gpuDevice: defaults.gpu_device
    property var pill: P.parse({})            // the pill_* keys (launcher/js/PillPos.js), replaced as a whole
    readonly property string pillEdge: pill.pill_edge
    readonly property real pillGap: pill.pill_gap
    readonly property real pillX: pill.pill_x
    readonly property string pillScreen: pill.pill_screen
    readonly property bool pillBottom: pillEdge === "bottom"
    property var extra: ({})          // unknown keys of the file, written back unchanged
    property int idleTimeoutS: defaults.idle_timeout_s
    property bool promptHints: defaults.prompt_hints

    function value(key) {
        return key === "mic" ? mic : key === "gpu" ? gpu : key === "gpu_device" ? gpuDevice : key === "idle_timeout_s" ? idleTimeoutS
            : key === "prompt_hints" ? promptHints : P.KEYS.indexOf(key) >= 0 ? pill[key] : undefined
    }
    function overridden(key) { return value(key) !== defaults[key] }
    function set(key, v) {
        // the same limits as parse(): a value it would drop on the next load is refused here
        if (key === "mic") { if (typeof v !== "string" || v.length > 200 || /[\x00-\x1f]/.test(v)) return false; mic = v }
        else if (key === "gpu") gpu = !!v
        else if (key === "gpu_device") gpuDevice = Math.min(1000, Math.max(0, Math.round(Number(v)) || 0))
        else if (P.KEYS.indexOf(key) >= 0) { const n = P.withKey(pill, key, v); if (!n) return false; pill = n }
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
        pill = P.parse(d, d.pill_bottom === true ? "bottom" : "bar")
        const rest = {}
        for (const k of Object.keys(d)) if (k !== "version" && k !== "pill_bottom" && keys.indexOf(k) < 0) rest[k] = d[k]
        extra = rest
        idleTimeoutS = Number.isInteger(d.idle_timeout_s) && d.idle_timeout_s >= 0 && d.idle_timeout_s <= 604800 ? d.idle_timeout_s : defaults.idle_timeout_s
        promptHints = typeof d.prompt_hints === "boolean" ? d.prompt_hints : defaults.prompt_hints
    }
    function serialize() {
        return JSON.stringify(Object.assign({}, extra, { version: 1, mic: mic, gpu: gpu, gpu_device: gpuDevice, idle_timeout_s: idleTimeoutS,
                                                         prompt_hints: promptHints }, pill, { pill_bottom: pillBottom })) + "\n"
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
            if (key === "pill") return dp.set("pill_edge", v === "true" ? "bottom" : "bar") ? "ok" : "bad"   // the old switch
            const map = { mic: "mic", gpu: "gpu", device: "gpu_device", idle: "idle_timeout_s", hints: "prompt_hints",
                          edge: "pill_edge", gap: "pill_gap", x: "pill_x", screen: "pill_screen" }
            const k = map[key]
            if (!k) return "unknown key"
            const val = k === "gpu" || k === "prompt_hints" ? v === "true" : k === "idle_timeout_s" || k === "gpu_device" || k === "pill_gap" || k === "pill_x" ? Number(v) : v
            return dp.set(k, val) ? "ok" : "bad"
        }
        function reset(): string { dp.resetAll(); return "ok" }
        function sources(): string { dp.refreshSources(); return JSON.stringify(dp.sources) }
    }
}
