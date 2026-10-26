pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Notification daemon (replaces swaync). `popups` are the toasts currently on screen;
// everything not dismissed stays tracked and shows up in the notification center.
Singleton {
    id: root

    property bool dnd: false
    property var popups: []
    property var byId: ({})                 // id -> Notification, for the toast stack (ListModel holds ids)
    property var times: ({})                // id -> arrival time (ms), shown on the notification center cards
    property var repeats: ({})              // id -> how many identical notifications it stands for (see dedupe in onNotification)
    property var history: []                // the last `historyMax` notifications as plain data, newest first (also the ones do-not-disturb silenced); replay() shows them again
    readonly property int historyMax: 10
    property real now: Date.now()           // refreshed by `ticker` so relative times stay current
    readonly property var all: server.trackedNotifications
    readonly property int count: server.trackedNotifications.values.length
    // what the notification center shows: the ones already swept out (waiting in `pendingClose` to be closed) no longer count
    readonly property int liveCount: Math.max(0, count - pendingClose.length)

    NotificationServer {
        id: server
        keepOnReload: false
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            // looked up by the notification stack the moment it is tracked, so set before
            byId[n.id] = n
            times[n.id] = Date.now()        // a replacement (same id) counts as new
            // an identical one (same app, summary and body) replaces the older card and counts up instead of stacking
            const key = root.keyOf(n)
            let reps = 1
            for (const o of root.all.values.slice()) {
                if (o.id === n.id || root.keyOf(o) !== key) continue
                reps += root.repeats[o.id] ?? 1
                root.closeNow(o)
            }
            root.repeats[n.id] = reps
            root.record(n, key)
            root.now = Date.now()
            n.tracked = true
            // do-not-disturb silences toasts but still files them away; critical always shows. With the notification
            // center open the new one goes straight into its list (no toast of its own)
            // A transient one (hint `transient`) is never kept: it is closed once its toast is over (NotifSlot), or at
            // once when it gets no toast (do-not-disturb), or when the center closes if it arrived while the list was open.
            if (Popups.name === "notif") return
            if (root.dnd && n.urgency !== NotificationUrgency.Critical) {
                if (n.transient) Qt.callLater(() => root.closeNow(n))
                return
            }
            root.popups = [n].concat(root.popups.filter(p => p.id !== n.id)).slice(0, 5)
        }
    }

    // "now", "5m", "2h", then clock time ("14:05"), with the weekday when not from today
    function ago(id) {
        const t = times[id]
        if (!t) return ""
        const m = Math.floor((now - t) / 60000)
        if (m < 1) return "now"
        if (m < 60) return m + "m"
        if (m < 180) return Math.floor(m / 60) + "h"
        const d = new Date(t)
        return Qt.formatDateTime(d, d.toDateString() === new Date(now).toDateString() ? "HH:mm" : "ddd HH:mm")
    }

    // one shared timer for every card, only while something is tracked
    Timer {
        id: ticker
        interval: 30000
        repeat: true
        running: root.count > 0
        onTriggered: root.now = Date.now()
    }

    function keyOf(n) { return [n.appName, n.summary, n.body].join("\u0001") }

    // newest first, one entry per distinct notification; plain data, because a Notification object dies when it is closed
    function record(n, key) {
        const e = { key: key, appName: n.appName, summary: n.summary, body: n.body, appIcon: n.appIcon, urgency: n.urgency }
        history = [e].concat(history.filter(h => h.key !== key)).slice(0, historyMax)
    }

    // Replay (IPC `notif replay`): the history comes back as toasts (up to the five a toast stack holds), do-not-disturb
    // or not. They are stand-ins without actions: the app that sent them may be gone. Not tracked by the server, so
    // they live only as long as their toast: NotifSlot hands one to releaseLater once its row has left and it is no
    // longer a toast (expired, dismissed, pushed out, DND), which destroys it.
    Component {
        id: standIn
        QtObject {
            readonly property bool standIn: true
            signal closed()                         // never emitted; NotifSlot listens for it on real notifications
            property int id: 0
            property string appName: ""
            property string summary: ""
            property string body: ""
            property string appIcon: ""
            property int urgency: NotificationUrgency.Normal
            readonly property string image: ""
            readonly property string desktopEntry: ""
            readonly property var actions: []
            readonly property var hints: ({})
            readonly property int expireTimeout: -1
            function dismiss() { root.dismissPopup(this) }
        }
    }
    property int standInId: -1
    function replay() {
        if (Popups.name === "notif") return
        const shown = []
        for (const h of history.slice(0, 5)) {
            const id = standInId--
            const n = standIn.createObject(root, { id: id, appName: h.appName, summary: h.summary, body: h.body, appIcon: h.appIcon, urgency: h.urgency })
            byId[id] = n
            times[id] = Date.now()
            shown.push(n)
        }
        root.now = Date.now()
        popups = shown
    }

    function dismissPopup(n) { popups = popups.filter(p => p !== n) }

    // Close the notification after its toast has slid out: closing destroys the object the card is
    // still drawing during the exit animation.
    property var pendingClose: []
    function releaseLater(n) {
        if (n && n.standIn === true) {          // a replayed stand-in: nothing to close, just let it go (not in pendingClose: liveCount counts tracked ones)
            dismissPopup(n)
            delete byId[n.id]
            delete times[n.id]
            n.destroy(closer.interval)
            return
        }
        pendingClose = pendingClose.concat([n]); closer.restart()
    }
    Timer {
        id: closer
        interval: 450
        onTriggered: {
            for (const n of root.pendingClose) { try { n.dismiss() } catch (e) {} }
            root.pendingClose = []
        }
    }

    // Clear (button, IPC): the notification stack sweeps the cards one after another (NotifStack.clearAll) and closes
    // the rest at once
    signal clearRequested()
    function clearAll() { clearRequested() }
    // close a notification now (no animation): out of the toasts and out of the history
    function closeNow(n) {
        dismissPopup(n)
        try { n.dismiss() } catch (e) {}
    }

    // transient notifications that arrived while the center was open have no toast and no timer: they go with the list
    Connections {
        target: Popups
        function onNameChanged() {
            if (Popups.name === "notif") return
            for (const n of root.all.values.slice())
                if (n.transient && !root.popups.some(p => p.id === n.id)) closeLater.queue.push(n)
            closeLater.restart()
        }
    }
    Timer {
        id: closeLater
        property var queue: []
        interval: Math.max(1, Theme.popupCloseMs) + 100       // after the list has slid out
        onTriggered: { for (const n of queue) root.closeNow(n); queue = [] }
    }

    function setDnd(on) {
        dnd = on
        store.setText(on ? "1" : "0")
        if (on) popups = popups.filter(p => p.urgency === NotificationUrgency.Critical)
    }

    // remember do-not-disturb across restarts
    FileView {
        id: store
        path: Quickshell.env("HOME") + "/.cache/qs-dnd"
        printErrors: false
        onLoaded: root.dnd = text().trim() === "1"
    }
}
