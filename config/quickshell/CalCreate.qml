import QtQuick
import Quickshell
import Quickshell.Io
import "launcher/js/CalEvent.js" as CalEvent

// Runs `omacal events create` for the calendar popup (argv built in launcher/js/CalEvent.js, user text never
// touches a shell) and `omacal <date>` to open the app on a day. QS_OMACAL overrides the binary (tests use a stub).
// Exit 5 = omacal is not running: start it hidden (`--autostart`, detached), wait, retry once.
// Emits created() on success; `error` holds the message otherwise.
Item {
    id: c
    readonly property string bin: Quickshell.env("QS_OMACAL") || "omacal"
    property bool busy: false
    property string error: ""
    property int startWaitMs: 4000
    property var args: []
    property bool retried: false
    property string out: ""
    signal created()

    function create(title, date, start, end, allDay, endDate, calendarId) {
        if (busy) return
        error = ""
        retried = false
        args = CalEvent.createArgs(bin, title, date, start, end, allDay, endDate, calendarId)
        run()
    }
    function openDay(date) { Quickshell.execDetached([bin, date]) }
    function run() { out = ""; busy = true; proc.command = args; proc.running = true }

    function finished(code) {
        if (code === 5 && !retried) {
            retried = true
            error = "Starting omacal…"
            Quickshell.execDetached([bin, "--autostart"])
            wait.restart()
            return
        }
        busy = false
        if (code === 5) { error = "omacal is not running"; return }
        const r = CalEvent.parseResult(out, code)
        error = r.ok ? "" : r.message
        if (r.ok) created()
    }

    Process {
        id: proc
        stdout: StdioCollector { onStreamFinished: c.out = text }
        onExited: code => Qt.callLater(() => c.finished(code))
    }
    Timer { id: wait; interval: c.startWaitMs; onTriggered: { c.error = ""; c.run() } }
}
