import QtQuick
import Quickshell
import Quickshell.Io

// Push-to-talk dictation: the keys (PttShortcuts; PttPrefs.entries: Auto, and per selected language its own key and its
// "to English" key) drive the service (DictationClient) and the pill shows it.
// Hold a key: `begin <code>|translate:<code>|auto <selected codes>` and the pill opens on the focused monitor (mode
// <code>, <code>-en or auto, listening; Auto shows the language the service detected once it has); release: `end`, the pill stays until the final text is typed (or nothing was said, or
// typing stopped) and then fades. One session at a time: another key pressed meanwhile is ignored.
// Pill state: listening while quiet, speaking (translate: translating) while the mic level is above `loud` (held
// `quietMs` after the last loud frame); the caption is the service's preview (transcribe: the text being typed, the
// pill shows its end; translate: the English preview, nothing is typed until release). Errors (service `error`
// events, a service that cannot be started, no speech model) turn the pill into its generic error line; the detail goes
// to DictationStatus through the pill (errorText / errorCode).
//   qs ipc call dictation press <code>|<code>-en|auto | release | cancel | status   (the keys' code path, for tests)
Scope {
    id: ctl

    property real loud: 0.3                  // level counted as speech (the service's level: 0 = at the noise floor, speech ~0.6-1)
    property int quietMs: 350
    property int finalLingerMs: 900          // the finished text stays readable this long
    property int errorLingerMs: 2500
    property int finishTimeoutMs: 30000      // no answer after release: close anyway (re-armed while the service is still finishing)

    property string key: ""                  // the key holding the current session ("" = none held)
    property bool session: false             // a session was asked for and has not finished yet
    property bool waiting: false             // released, waiting for the final text
    property bool finishing: false           // ... and the service started its final pass
    readonly property bool translating: /^[a-z]+-en$/.test(pill.mode)

    DictationPill { id: pill }

    Connections {
        target: PttShortcuts
        function onPressed(name) { ctl.press(name) }
        function onReleased(name) { if (name === ctl.key) ctl.release() }
    }

    function press(name) {
        const m = PttPrefs.entry(name)
        if (!m || key !== "" || session) return
        closeTimer.stop()
        key = name
        waiting = false
        if (pill.state !== "error") { pill.errorCode = ""; pill.errorText = "" }   // the same no-model error shown again is not a new record
        pill.captionText = ""
        pill.level = 0
        pill.mode = m.pill
        pill.state = "listening"
        if (pill.state === "error") return    // no usable speech model: the pill said so (SttModels), nothing to record
        session = true
        // Auto picks among the selected languages (none selected = any)
        DictationClient.begin(m.service === "auto" && PttPrefs.languages.length ? "auto " + PttPrefs.languages.join(",") : m.service)
    }
    function release() {
        key = ""
        if (pill.state === "error" || !session) { closeAfter(errorLingerMs); return }
        waiting = true
        finishing = false
        quiet.stop()
        if (pill.state !== "hidden") pill.state = "listening"
        DictationClient.end()
        closeTimer.interval = finishTimeoutMs
        closeTimer.restart()
    }
    function cancel() {
        if (session) DictationClient.cancel()
        key = ""
        done(0)
    }
    function done(lingerMs) {
        session = false
        waiting = false
        closeAfter(lingerMs)
    }
    function closeAfter(ms) {
        quiet.stop()
        closeTimer.interval = Math.max(1, ms)
        closeTimer.restart()
    }
    function fail(message, code) {
        if (pill.state === "hidden") return    // not ours to show (nothing is open)
        if (session) DictationClient.cancel()   // the service may still be recording
        session = false
        waiting = false
        pill.errorCode = code
        pill.errorText = message
        pill.state = "error"
        closeAfter(errorLingerMs)
    }
    Timer {
        id: closeTimer
        onTriggered: {
            if (ctl.key !== "") return         // a key is still held (an error while held): close on release
            // released and the service is still on this session's final pass (a slow pass, a `retry` reloading the
            // worker): keep waiting, its own timeouts end it with `final` or `error` + idle (a dead service = lost())
            if (ctl.waiting && DictationClient.connected
                    && (DictationClient.state === "finishing" || DictationClient.state === "loading")) { restart(); return }
            ctl.session = false
            ctl.waiting = false
            pill.state = "hidden"
        }
    }
    Timer {
        id: quiet
        interval: ctl.quietMs
        onTriggered: if (ctl.key !== "" && pill.state !== "error" && pill.state !== "hidden") pill.state = "listening"
    }

    Connections {
        target: DictationClient
        function onLanguageDetected(code) { if (ctl.session && pill.mode === "auto" && code !== "") pill.mode = code }
        function onLevelEvent(value) {
            if (!ctl.session || pill.state === "error" || pill.state === "hidden") return
            pill.level = value
            if (value >= ctl.loud && ctl.key !== "") {
                pill.state = ctl.translating ? "translating" : "speaking"
                quiet.restart()
            }
        }
        function onPreviewChanged() { if (ctl.session) pill.captionText = DictationClient.preview }
        function onFinished(text) { if (ctl.session) ctl.done(ctl.finalLingerMs) }
        // the focused window changed: the service types nothing more this session (not an error); the session runs on
        // until release (`end` then returns without a final text: finishing -> idle closes the pill)
        function onAborted(reason, message) {
            if (ctl.session && reason !== "focus") ctl.fail("Typing failed" + (message !== "" ? ": " + message : ""), "inject")
        }
        function onFailed(message, code) { if (ctl.session) ctl.fail(message, code) }
        // also while the service was loading or a begin was queued: the session is gone with the connection
        function onLost() { if (ctl.session) ctl.fail("Lost the connection to the dictation service", "service-down") }
        // after release: finishing -> idle without a final text = nothing was said (an idle before finishing is a
        // model reload at begin, not the end of this session)
        function onStateChanged() {
            if (!ctl.waiting) return
            if (DictationClient.state === "finishing") ctl.finishing = true
            else if (DictationClient.state === "idle" && ctl.finishing) ctl.done(0)
        }
    }

    IpcHandler {
        target: "dictation"
        function press(mode: string): string {
            const e = PttPrefs.entries.find(x => x.pill === mode)
            if (!e) return "unknown mode (auto, or a selected language: " + PttPrefs.entries.map(x => x.pill).join(", ") + ")"
            ctl.press(e.name)
            return "ok"
        }
        function release(): void { if (ctl.key !== "") ctl.release() }
        function cancel(): void { ctl.cancel() }
        function status(): string {
            return JSON.stringify({ key: ctl.key, session: ctl.session, waiting: ctl.waiting, pill: pill.state,
                                    mode: pill.mode, caption: pill.captionText, service: DictationClient.state,
                                    connected: DictationClient.connected })
        }
    }
}
