pragma Singleton
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
    readonly property var all: server.trackedNotifications
    readonly property int count: server.trackedNotifications.values.length

    NotificationServer {
        id: server
        keepOnReload: false
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true
            byId[n.id] = n
            // do-not-disturb silences toasts but still files them away; critical always shows
            if (root.dnd && n.urgency !== NotificationUrgency.Critical) return
            root.popups = [n].concat(root.popups.filter(p => p.id !== n.id)).slice(0, 5)
        }
    }

    function dismissPopup(n) { popups = popups.filter(p => p !== n) }

    // Close the notification after its toast has slid out: closing destroys the object the card is
    // still drawing during the exit animation.
    property var pendingClose: []
    function releaseLater(n) { pendingClose.push(n); closer.restart() }
    Timer {
        id: closer
        interval: 450
        onTriggered: {
            for (const n of root.pendingClose) { try { n.dismiss() } catch (e) {} }
            root.pendingClose = []
        }
    }

    function clearAll() {
        for (const n of server.trackedNotifications.values.slice()) n.dismiss()
        popups = []
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
