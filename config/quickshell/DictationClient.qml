pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The one connection to the dictation service (config/dictation, README "Control interface"): a unix socket at
// $XDG_RUNTIME_DIR/dictation.sock (QS_DICTATION_SOCKET overrides), newline JSON events in, word commands out. Knows
// nothing about keys or the pill (DictationController wires those).
// Connects at start and when the service went away retries with a backoff (1 s doubling, 6 tries: the service came up
// after the shell, or restarted); after that a key press connects (and starts the service when needed). A command while
// not connected is queued and starts the service once: `systemctl --user start dictation.service`, or the command line
// in QS_DICTATION_START (run with sh -c; it must return, e.g. `setsid -f <dotfiles>/config/dictation/bin/dictation
// serve`, for development without the unit), then it retries the socket every 250 ms for `startTimeout`. A start that
// fails or times out drops the queue and reports `failed(<detail>, "service-down")`.
//   state     the service's: "" (not connected) | loading | idle | listening | finishing | error
//   mode      cs | en | translate while a session runs
//   level     the last mic level 0..1 (levelEvent(v) fires for every one, also a repeated value)
//   preview   the session's text so far (translate: the English preview); cleared when a session starts
//   serviceError / serviceCode   why the service is not ready (state error: a missing model, a broken worker)
// Signals: failed(message, code) (an `error` event, a start that failed), lost() (the connection dropped), finished(text)
// (`final`), aborted(reason, message) (typing stopped: focus moved / injection failed).
//   qs ipc call dictation-client status
Singleton {
    id: root

    readonly property string socketPath: {
        const env = Quickshell.env("QS_DICTATION_SOCKET")
        if (env) return String(env)
        return String(Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/dictation.sock"
    }
    readonly property var startCommand: {
        const env = Quickshell.env("QS_DICTATION_START")
        return env ? ["sh", "-c", String(env)] : ["systemctl", "--user", "start", "dictation.service"]
    }
    property int startTimeout: 10000         // ms from the start command to a connected socket

    readonly property bool connected: sock.connected
    property string state: ""
    property string mode: ""
    property real level: 0
    property string preview: ""
    property string serviceError: ""
    property string serviceCode: ""

    signal levelEvent(real value)
    signal failed(string message, string code)
    signal lost()
    signal finished(string text)
    signal aborted(string reason, string message)

    function begin(mode) { send("begin " + mode) }
    function end() { send("end") }
    function cancel() { if (sock.connected) send("cancel"); else queue = [] }   // not connected: drop what waits, start nothing

    // ---- commands ----
    property var queue: []                   // lines waiting for the connection
    function send(line) {
        if (sock.connected) { sock.write(line + "\n"); sock.flush(); return }
        queue = queue.concat([line])
        ensureService()
    }
    property bool starting: false            // waiting for the socket until the deadline
    property bool launched: false            // the start command ran for this wait
    property real deadline: 0
    function ensureService() {
        if (starting) return
        starting = true
        launched = false
        deadline = Date.now() + startTimeout
        // the service may be up and only the connection missing (it started after the last retry): try that first,
        // the start command runs at the first poll that is still not connected
        sock.connected = true
        poll.restart()
    }
    function giveUp(detail) {
        starting = false
        poll.stop()
        if (queue.length === 0) return
        queue = []
        failed(detail, "service-down")
    }
    Process {
        id: starter
        command: root.startCommand
        stderr: StdioCollector { id: startErr }
        onExited: code => {
            if (code !== 0 && !sock.connected && root.starting)
                root.giveUp("The dictation service could not be started (" + root.startCommand.join(" ") + ", exit code " + code
                            + (startErr.text.trim() !== "" ? ": " + startErr.text.trim() : "") + ")")
        }
    }
    Timer {
        id: poll
        interval: 250
        repeat: true
        onTriggered: {
            if (sock.connected) { stop(); return }
            if (!root.launched) { root.launched = true; starter.running = true }
            if (Date.now() > root.deadline) {
                root.giveUp("The dictation service did not answer on " + root.socketPath + " within "
                            + Math.round(root.startTimeout / 1000) + " s")
                return
            }
            sock.connected = true
        }
    }

    // ---- connection ----
    Socket {
        id: sock
        path: root.socketPath
        onConnectedChanged: {
            if (connected) {
                root.starting = false
                poll.stop()
                backoff.stop()
                const q = root.queue
                root.queue = []
                for (const line of q) write(line + "\n")
                if (q.length) flush()
                return
            }
            root.state = ""
            root.mode = ""
            root.lost()
            if (!root.starting) root.retryLater()
        }
        parser: SplitParser {
            onRead: line => {
                let e
                try { e = JSON.parse(line) } catch (err) { return }
                if (e && typeof e === "object") root.handle(e)
            }
        }
    }
    // background reconnect: the service restarted, or came up after the shell
    Timer {
        id: backoff
        property int tries: 0
        interval: 1000
        onTriggered: {
            sock.connected = true
            if (!sock.connected && !root.starting && ++tries < 6) { interval *= 2; start() }
        }
    }
    function retryLater() { backoff.tries = 0; backoff.interval = 1000; backoff.restart() }
    Component.onCompleted: { sock.connected = true; if (!sock.connected) retryLater() }

    function handle(e) {
        switch (e.event) {
        case "status":
            state = String(e.state || "")
            mode = String(e.mode || "")
            serviceError = String(e.error || "")
            serviceCode = String(e.code || "")
            break
        case "state":
            state = String(e.state || "")
            if (state === "listening") { mode = String(e.mode || ""); preview = ""; level = 0 }
            if (state === "idle") mode = ""
            break
        case "level":
            level = Number(e.value) || 0
            levelEvent(level)
            break
        case "preview":
            preview = String(e.text || "")
            break
        case "final":
            finished(String(e.text || ""))
            break
        case "aborted":
            aborted(String(e.reason || ""), String(e.message || ""))
            break
        case "error":
            failed(String(e.message || "Dictation failed"), String(e.code || "error"))
            break
        }
    }

    IpcHandler {
        target: "dictation-client"
        function status(): string {
            return JSON.stringify({ connected: root.connected, state: root.state, mode: root.mode, preview: root.preview,
                                    serviceError: root.serviceError, serviceCode: root.serviceCode, queued: root.queue,
                                    starting: root.starting, socket: root.socketPath })
        }
    }
}
