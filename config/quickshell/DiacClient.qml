pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The diacritics pill's one connection to the service (config/diacritics): subscribes to `$XDG_RUNTIME_DIR/diacritics.sock`
// (QS_DIACRITICS_SOCKET overrides) with `{"op":"subscribe"}` and follows its newline-JSON `state` events. It never starts the service
// (the key flow does, on demand) and never sends anything else: while the service is not running it keeps trying to connect
// every `retryMs`, and a lost connection clears the state.
//   state   "" (not connected) | idle | loading | working | done | failed | unsupported
//   text    the text being fixed (sent while working; kept until the next idle)
//   fixed   the fixed text, when the service sends it (field `fixed` of a state event): the pill then shows it, marks and all
//   qs ipc call diacritics-client status
Singleton {
    id: root

    readonly property string socketPath: {
        const env = Quickshell.env("QS_DIACRITICS_SOCKET")
        if (env) return String(env)
        return String(Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/diacritics.sock"
    }
    property int retryMs: 2000
    readonly property bool connected: sock.connected
    property string state: ""
    property string text: ""
    property string fixed: ""

    Socket {
        id: sock
        path: root.socketPath
        onConnectedChanged: {
            if (connected) {
                write(JSON.stringify({ op: "subscribe" }) + "\n")
                flush()
                return
            }
            root.state = ""
            root.text = ""
            root.fixed = ""
        }
        parser: SplitParser {
            onRead: line => {
                let e
                try { e = JSON.parse(line) } catch (err) { return }
                if (e && typeof e === "object" && e.event === "state") root.handle(e)
            }
        }
    }
    // not connected: look for the socket file every retryMs and connect when it exists (no connect attempts, so a stopped service
    // does not fill the log with socket errors)
    Process {
        id: probe
        command: ["test", "-S", root.socketPath]
        onExited: code => { if (code === 0 && !sock.connected) sock.connected = true }
    }
    Timer {
        interval: root.retryMs
        repeat: true
        running: !sock.connected
        triggeredOnStart: true
        onTriggered: if (!probe.running) probe.running = true
    }

    function handle(e) {
        const s = String(e.state || "")
        if (s === "idle") { text = ""; fixed = "" }
        else {
            if (typeof e.text === "string" && e.text !== "" && e.text !== text) { text = e.text; fixed = "" }   // a new text: the old result is gone
            if (typeof e.fixed === "string") fixed = e.fixed
        }
        state = s
    }

    IpcHandler {
        target: "diacritics-client"
        function status(): string {
            return JSON.stringify({ connected: root.connected, state: root.state, text: root.text, fixed: root.fixed, socket: root.socketPath })
        }
    }
}
