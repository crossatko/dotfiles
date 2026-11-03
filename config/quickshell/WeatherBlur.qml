pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Weather blur (Settings > Weather > Weather blur, off by default): hands the current weather to the compositor, which
// picks the blur variant. Nothing is decided here: this singleton only writes the state file and pokes Hyprland.
//   Weather.qml (answer, switch, thresholds) -> weather-blur.json (next to glass.json, QS_WEATHER_BLUR_FILE overrides)
//   -> `hyprctl eval weather_blur_apply()` -> managed.lua + blurweather.lua (pure, tested) decide the variant (a weather rule,
//   else the default: solid glass where Hyprland has it, else kawase) and apply it ON TOP of the saved glass.json blur,
//   which is never written. Switch off / weather unavailable = the file says enabled:false
//   and the saved blur (else settings.lua's) is applied again. A config reload re-reads the same file (managed.lua).
//   {"version":1,"enabled":true,"at":<epoch s>,"kind":"rain","tempC":12.5,"isDay":false,"aurora":false,"coldC":0,"hotC":28}
// "aurora" = geomagnetic activity strong enough for the user's latitude (bin/weather --kp), the coordinates never get here.
// Written 1.5 s after the last change (a units change drops the answer for a moment: no flicker back to the saved blur),
// and not at all while the switch has been off since the shell started. The payload is Weather.blurState(). A state is
// acted on for 3 h (blurweather.lua MAX_AGE_S); managed.lua re-checks it by an hl.timer when it expires, so a dead shell
// cannot leave the weather's blur on.
Singleton {
    id: wb

    readonly property string filePath: {
        const env = Quickshell.env("QS_WEATHER_BLUR_FILE")
        if (env) return String(env)
        const g = GlassTuneCtl.stateFile      // managed.lua looks next to glass.json
        return g.substring(0, g.lastIndexOf("/")) + "/weather-blur.json"
    }
    readonly property bool usable: Weather.blur && Weather.ok && !Weather.stale
    property bool _wasOn: false            // the switch was on at some point: turning it off must write the "off" state

    function snapshot() { return Weather.blurState(usable) }
    signal applied()                       // weather_blur_apply ran (BlurTuneCtl reads the live variant back)
    function schedule() {
        if (Weather.blur) _wasOn = true
        if (!_wasOn) return
        // no answer yet after the start: the file of the last session stays (it expires by itself)
        if (Weather.blur && !Weather.loaded) return
        debounce.restart()
    }
    Connections {
        target: Weather
        function onBlurChanged() { wb.schedule() }
        function onDataChanged() { wb.schedule() }
        function onColdCChanged() { wb.schedule() }
        function onHotCChanged() { wb.schedule() }
    }
    Component.onCompleted: schedule()
    // a file left "on" by an earlier session (shell gone before the "off" write) is switched off at the first chance
    FileView {
        path: wb.filePath
        printErrors: false
        onLoaded: if (!Weather.blur && text().indexOf('"enabled":true') >= 0) { wb._wasOn = true; wb.schedule() }
    }

    Timer {
        id: debounce
        interval: 1500
        onTriggered: {
            Quickshell.execDetached(["mkdir", "-p", wb.filePath.substring(0, wb.filePath.lastIndexOf("/")) || "/"])
            writer.restart()
        }
    }
    // mkdir runs detached: give it a moment before the write
    Timer { id: writer; interval: 200; onTriggered: file.setText(JSON.stringify(wb.snapshot()) + "\n") }
    FileView {
        id: file
        path: wb.filePath
        printErrors: false
        onSaved: wb.apply()
    }

    property bool _queued: false
    function apply() {
        if (!GlassTuneCtl.reachable) { _queued = true; return }
        if (proc.running) { _queued = true; return }
        proc.running = true
    }
    Connections {
        target: GlassTuneCtl
        function onReachableChanged() { if (GlassTuneCtl.reachable && wb._queued) { wb._queued = false; wb.apply() } }
    }
    Process {
        id: proc
        command: ["hyprctl", "eval", "if weather_blur_apply then weather_blur_apply() end"]
        environment: ({ HYPRLAND_INSTANCE_SIGNATURE: GlassTuneCtl.sig })
        stdout: StdioCollector {}
        onExited: {
            Theme.checkGlass()         // Theme.glass is true for solid_glass only: re-read after a variant change
            if (wb._queued) { wb._queued = false; wb.apply() }
            else wb.applied()
        }
    }

    IpcHandler {
        target: "weatherblur"
        function get(): string { return JSON.stringify(wb.snapshot()) }
        function apply(): void { wb.schedule(); wb.apply() }
    }
}
