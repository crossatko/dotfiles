pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// One countdown reminder (bar chip ReminderChip.qml, popup ReminderPanel.qml). The end time is an absolute timestamp saved
// in ${XDG_STATE_HOME:-~/.local/state}/quickshell/reminder.json (QS_REMINDER_FILE overrides), so a shell restart keeps it;
// one that ran out while the shell was down ends at the next start.
// ONE notification card stands for a running reminder, sent with `notify-send` and marked by the private hint
// `x-qs-reminder` (the reminder's token; never matched by app name). Notifs.qml hands every card with that hint to adopt():
// while it runs the card is low urgency, without a toast or a history entry, and NotifCard draws it as a reminder card
// (ReminderCardBody.qml) that reads the time left from here, so it counts down without new notifications. At the end the
// same card is replaced in place (`notify-send -r <id>`: the daemon updates the same Notification object, onNotification
// does NOT fire again) with a critical one: when that notify-send exits, Notifs.repop() gives it a sticky toast, a fresh
// age and a history entry. The end card offers snoozes (snoozeTable) and Dismiss. One notify-send runs at a time (queue):
// the next update waits for the id the last one printed. Dismissing the running card (swipe, close, Clear) cancels the
// reminder; our own close (Cancel) does not reach that path.
// Sound only at the end: one play through pw-play / paplay (a tracked Process, killed by its own handle when the end card
// is dismissed or snoozed, or Dismiss / Cancel in the popup); none while do-not-disturb is on.
// Env hooks (tests): QS_REMINDER_FILE, QS_REMINDER_SOUND (a sound file).
Singleton {
    id: root

    readonly property string filePath: {
        const env = Quickshell.env("QS_REMINDER_FILE")
        if (env) return String(env)
        const xdg = Quickshell.env("XDG_STATE_HOME")
        return (xdg ? String(xdg) : Quickshell.env("HOME") + "/.local/state") + "/quickshell/reminder.json"
    }
    readonly property string soundFile: Quickshell.env("QS_REMINDER_SOUND") || "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"
    readonly property real maxMinutes: 24 * 60
    readonly property int extendMinutes: 5           // the running popup's "+5 min"
    readonly property int labelMax: 80               // the reminder's text, characters (the popup's field too)
    readonly property int postTimeoutMs: 5000        // a notify-send that has not reported back by then is given up
    // Snoozes the end card and the popup offer, by the reminder's first length in minutes (a snooze keeps that length,
    // so a snoozed 60 min reminder still offers +30). The one table: snoozeFor() is what both read.
    readonly property var snoozeTable: [
        { upTo: 10, steps: [5] },
        { upTo: 45, steps: [5, 15] },
        { upTo: Infinity, steps: [5, 30] }
    ]
    function snoozeFor(minutes) {
        for (const r of snoozeTable) if (minutes <= r.upTo) return r.steps
        return []
    }
    // private hints of the reminder's cards: the reminder's token, its first length (minutes), its text
    readonly property string hintToken: "x-qs-reminder"
    readonly property string hintMinutes: "x-qs-reminder-minutes"
    readonly property string hintLabel: "x-qs-reminder-label"

    property double endAt: 0              // ms since epoch, 0 = no reminder
    property double startedAt: 0          // ms; the length of the running countdown is endAt - startedAt (progress)
    property string label: ""
    property int baseMinutes: 0           // the first length (snoozeTable); a snooze keeps it
    property string token: ""             // this reminder's cards carry it in hintToken
    property double now: Date.now()       // ticks once a second while active
    readonly property bool active: endAt > 0
    readonly property int remaining: active ? Math.max(0, Math.ceil((endAt - now) / 1000)) : 0   // seconds
    readonly property real total: active ? (endAt - startedAt) / 1000 : 0                          // seconds
    readonly property real progress: active && total > 0 ? Math.max(0, Math.min(1, 1 - remaining / total)) : 0
    // the reminder that ended and is not dismissed / snoozed yet: { token, label, minutes }
    property var expired: null
    readonly property bool isExpired: expired !== null
    property bool loaded: false

    // "5:00", "59:59", "1:05:00"
    function fmt(sec) {
        const s = Math.max(0, Math.round(sec)), h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), r = s % 60
        const p = n => (n < 10 ? "0" : "") + n
        return h > 0 ? h + ":" + p(m) + ":" + p(r) : m + ":" + p(r)
    }
    // a length: "30 min", "2 h"
    function lengthText(sec) {
        const m = Math.max(1, Math.round(sec / 60))
        return m >= 60 && m % 60 === 0 ? m / 60 + " h" : m + " min"
    }

    // minutes may be fractional (tests); returns "" = started, else why not
    function start(minutes, text) { return begin(minutes, text, minutes) }
    function begin(minutes, text, base) {
        const m = Number(minutes)
        if (!isFinite(m) || m <= 0) return "Enter a number of minutes"
        if (m > maxMinutes) return "At most " + maxMinutes + " minutes"
        if (root.active) closeNote()                      // a start while one runs (IPC) replaces it
        if (root.isExpired) dismissExpired()              // ... and so does one while an ended one waits
        const t = Date.now()
        root.now = t; root.startedAt = t; root.endAt = t + Math.round(m * 60000)
        root.label = String(text || "").trim().slice(0, labelMax)
        root.baseMinutes = Math.max(1, Math.ceil(Number(base) || m))
        root.token = "r" + t + "-" + (++root.serial)
        save()
        post("run")
        return ""
    }
    property int serial: 0
    function extend(minutes) {
        if (!active) return
        root.endAt += Math.round(Number(minutes) * 60000)
        save()
        post("run")
    }
    // the popup's Cancel / IPC: stops a running reminder and closes its card; an ended one goes too
    function cancel() {
        stopSound()
        if (active) { stopRunning(); closeNote() }
        dismissExpired()
    }
    function stopRunning() {
        const tok = root.token
        root.queue = root.queue.filter(j => j.token !== tok || j.kind === "end")     // its waiting card updates are moot
        root.endAt = 0; root.startedAt = 0; root.label = ""; root.baseMinutes = 0; root.token = ""
        save()
    }

    // the popup's / IPC Dismiss of the ended reminder: the sound stops at once, its card goes
    function dismissExpired() {
        const n = root.expiredNote
        clearExpired()
        if (n) Notifs.closeNow(n)
    }
    function clearExpired() { stopSound(); root.expired = null; root.expiredNote = null; save() }
    // Snooze: the same reminder (text, first length) again for `step` minutes; the end card goes. `n` = the end card whose
    // button was clicked (it animates itself out); without one (popup, IPC) the current end card is closed here.
    function snooze(step, n) {
        stopSound()
        const card = n || root.expiredNote
        const text = card ? cardLabel(card) : root.expired ? root.expired.label : ""
        const base = card ? cardMinutes(card) : root.expired ? root.expired.minutes : step
        if (!n || n === root.expiredNote) clearExpired()
        begin(step, text, base)
        if (!n && card) Notifs.closeNow(card)
    }

    // ---- the cards ----
    property var note: null              // the running reminder's card (adopt)
    property var expiredNote: null       // the end card of `expired` (the same object, replaced in place)

    function owns(n) { return !!n && !!n.hints && n.hints[hintToken] !== undefined }
    function cardLabel(n) { return owns(n) && n.hints[hintLabel] !== undefined ? String(n.hints[hintLabel]) : "" }
    function cardMinutes(n) { return owns(n) ? Math.max(1, Number(n.hints[hintMinutes]) || 1) : 1 }

    // Notifs.qml calls this for every card with the private hint; true = quiet (no toast, no history entry). A card of no
    // running / ended reminder of ours (a stray, an old one) is closed at once.
    function adopt(n) {
        const tok = String(n.hints[hintToken])
        if (n.urgency === NotificationUrgency.Critical && root.expired && tok === root.expired.token) {
            root.expiredNote = n                       // the end card as a new one (no running card to replace): toast + history as usual
            return false
        }
        if (n.urgency !== NotificationUrgency.Critical && root.expired && tok === root.expired.token) {
            root.expiredNote = n                       // its running card, still on its way when it ended: the end post replaces it
            return true
        }
        if (n.urgency !== NotificationUrgency.Critical && root.active && tok === root.token) {
            if (root.note && root.note !== n) { const old = root.note; root.note = null; Notifs.closeNow(old) }
            root.note = n
            return true
        }
        Qt.callLater(() => Notifs.closeNow(n))
        return true
    }
    function closeNote() { const n = root.note; root.note = null; if (n) Notifs.closeNow(n) }

    // NotifCard calls this the moment a reminder card is dismissed (close, swipe, right click, Clear, its own buttons),
    // before it animates out: the sound stops now, a dismissed running card cancels its reminder
    function cardDismissed(n) {
        if (n === root.expiredNote) clearExpired()
        else if (n === root.note) { root.note = null; stopRunning() }
    }
    Connections {
        target: root.note
        function onClosed(reason) {
            const running = root.active
            if (running) delete root.cardIds[root.token]      // gone: the next post of this reminder makes a new card
            root.note = null
            if (running && reason === NotificationCloseReason.Dismissed) root.stopRunning()      // closed without the card (IPC, Clear)
        }
    }
    Connections {
        target: root.expiredNote
        // closed some other way (Clear of a card out of view, D-Bus): forgotten; saved only when the user closed it
        function onClosed(reason) {
            root.stopSound(); root.expired = null; root.expiredNote = null
            if (reason === NotificationCloseReason.Dismissed) root.save()
        }
    }

    // ---- notify-send, one at a time ----
    // A post is a snapshot of what a card says ("run" = the running card, "end" = the end card); a waiting post of the same
    // card is replaced by the newer one. The id each notify-send prints (-p) is the card the next post of that token
    // replaces (-r), so Start and +5 a moment later stay one card; a new reminder has a new token and never reuses an
    // open end card's id.
    property var queue: []
    property var cardIds: ({})           // token -> notification id of its card
    function post(kind) {
        const job = kind === "end"
            ? { kind: kind, token: root.expired.token, label: root.expired.label, minutes: root.expired.minutes, total: root.expired.total }
            : { kind: kind, token: root.token, label: root.label, minutes: root.baseMinutes, total: root.total }
        // the end supersedes every waiting post of its reminder
        root.queue = root.queue.filter(j => !(j.token === job.token && (j.kind === job.kind || kind === "end"))).concat([job])
        pump()
    }
    function pump() {
        if (sender.running || sender.job || root.queue.length === 0) return
        const j = root.queue[0]
        root.queue = root.queue.slice(1)
        const end = j.kind === "end"
        const rid = root.cardIds[j.token]
        const args = ["notify-send", "-p", "-a", "Reminder", "-i", "alarm-symbolic", "-u", end ? "critical" : "low",
                      "-h", "string:" + hintToken + ":" + j.token, "-h", "int:" + hintMinutes + ":" + j.minutes]
            .concat(j.label !== "" ? ["-h", "string:" + hintLabel + ":" + j.label] : [])
            .concat(rid !== undefined ? ["-r", String(rid)] : [])
            .concat(["--", j.label !== "" ? j.label : end ? "Time is up" : "Reminder",
                     end ? lengthText(j.total) + " reminder ended" : lengthText(j.total) + " reminder"])
        sender.job = j
        sender.replaces = rid !== undefined
        sender.gotOut = false; sender.gotExit = false; sender.out = ""; sender.timedOut = false
        sender.command = args
        sender.running = true
        senderGuard.restart()
    }
    // a notify-send that never reports back (no daemon, not installed) must not hold up the queue
    Timer { id: senderGuard; interval: root.postTimeoutMs; onTriggered: if (sender.job) { sender.timedOut = true; sender.gotOut = true; sender.gotExit = true; sender.finish() } }
    Process {
        id: sender
        property var job: null
        property bool replaces: false
        property bool gotOut: false
        property bool gotExit: false
        property bool timedOut: false
        property string out: ""
        stdout: StdioCollector { onStreamFinished: { sender.out = text; sender.gotOut = true; sender.finish() } }
        onExited: { gotExit = true; finish() }
        function finish() {
            if (!job) { if (!running) Qt.callLater(root.pump); return }      // given up earlier (senderGuard): now it has exited
            if (!gotOut || !gotExit) return
            const j = job
            job = null
            senderGuard.stop()
            const id = timedOut ? NaN : parseInt(out, 10)
            if (isFinite(id) && id > 0) {
                root.cardIds[j.token] = id
                // the end card replaced the running one in place: now it is news (toast, age, history)
                if (j.kind === "end" && replaces) {
                    const n = Notifs.byId[id]
                    if (n && root.expired && root.expired.token === j.token) { root.expiredNote = n; Notifs.repop(n) }
                }
            }
            Qt.callLater(root.pump)
        }
    }

    // ---- sound ----
    // `exec` makes the shell the player itself, so the handle (and processId) is the player's
    Process {
        id: player
        command: ["bash", "-c", "f=\"$1\"; [ -r \"$f\" ] || exit 0; for p in pw-play paplay; do command -v \"$p\" >/dev/null && exec \"$p\" \"$f\"; done",
                  "reminder-sound", root.soundFile]
    }
    readonly property int soundPid: player.running ? player.processId : 0
    function playSound() {
        if (Notifs.dnd) return
        stopSound()
        player.running = true
    }
    function stopSound() {
        if (!player.running) return
        player.signal(15)
        player.running = false
    }

    // the end: the running card becomes the end card (or a new one after a restart), the sound plays once
    function fire() {
        root.expired = { token: root.token, label: root.label, minutes: root.baseMinutes, total: root.total }
        root.expiredNote = root.note
        root.note = null
        stopRunning()
        post("end")
        playSound()
    }

    function save() {
        if (!loaded) return
        const e = root.expired
        file.setText(JSON.stringify({ version: 2, endAt: root.endAt, startedAt: root.startedAt, label: root.label, baseMinutes: root.baseMinutes,
                                      expired: e ? { label: e.label, minutes: e.minutes, total: e.total } : null }))
    }

    Timer {
        interval: 1000; repeat: true; running: root.active
        onTriggered: { root.now = Date.now(); if (root.now >= root.endAt) root.fire() }
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.filePath.replace(/\/[^/]*$/, "")])
    // a start before the file has loaded (IPC right after the shell started) wins over the saved state
    function finishLoad(d) {
        const early = root.active
        if (!early && d && typeof d.endAt === "number" && d.endAt > 0) {
            root.startedAt = typeof d.startedAt === "number" ? d.startedAt : Date.now()
            root.label = typeof d.label === "string" ? d.label : ""
            root.baseMinutes = typeof d.baseMinutes === "number" && d.baseMinutes > 0 ? d.baseMinutes : Math.max(1, Math.ceil((d.endAt - root.startedAt) / 60000))
            root.token = "r" + root.startedAt + "-" + (++root.serial)
            root.now = Date.now()
            root.endAt = d.endAt
        }
        // an ended reminder not dismissed / snoozed before the restart: its end card again, without the sound
        const e = d && d.expired
        if (!early && !root.active && !root.isExpired && e && typeof e.minutes === "number") {
            root.expired = { token: "r" + Date.now() + "-" + (++root.serial), label: typeof e.label === "string" ? e.label : "",
                             minutes: Math.max(1, e.minutes), total: typeof e.total === "number" ? e.total : e.minutes * 60 }
            post("end")
        }
        root.loaded = true
        if (early) { save(); return }
        if (root.active && root.now >= root.endAt) root.fire()      // ran out while the shell was down
        else if (root.active) post("run")                           // the card is gone after a restart: post it again
    }
    FileView {
        id: file
        path: root.filePath
        printErrors: false
        onLoaded: { let d = null; try { d = JSON.parse(text()) } catch (e) {} root.finishLoad(d) }
        onLoadFailed: root.finishLoad(null)                         // no file yet
    }

    IpcHandler {
        target: "reminder"
        function get(): string {
            return JSON.stringify({ loaded: root.loaded, active: root.active, remaining: root.remaining, label: root.label, expired: root.isExpired,
                                    card: root.note ? root.note.id : 0, endCard: root.expiredNote ? root.expiredNote.id : 0,
                                    cards: Notifs.all.values.filter(n => root.owns(n)).map(n => n.id),
                                    soundPid: root.soundPid, posting: sender.running, queued: root.queue.length })
        }
        function start(minutes: string, text: string): string { return root.start(parseFloat(minutes), text) || "ok" }
        // tests: a short run that acts like one of `base` minutes (its snoozes)
        function startAs(minutes: string, base: string, text: string): string { return root.begin(parseFloat(minutes), text, parseFloat(base)) || "ok" }
        function extend(minutes: string): void { root.extend(parseFloat(minutes)) }
        function snooze(minutes: string): void { if (root.isExpired) root.snooze(parseFloat(minutes), null) }
        function dismiss(): void { root.dismissExpired() }
        function cancel(): void { root.cancel() }
    }
}
