pragma ComponentBehavior: Bound
import QtQuick

// One row of the notification stack (NotifStack): a NotifCard plus everything that happens around it: slide-in /
// slide-out with the gap opening and closing, the toast timeout, the dismiss path. The row is created when its
// notification becomes wanted (a toast, or any tracked notification while the center is open) and removes itself
// from the stack's model (`removeRequested`) after its exit animation.
Item {
    id: slot

    required property int nid                // notification id (the stack's model holds ids, see NotifStack)
    required property int index
    required property bool lead              // created in bulk by opening the list: already at its final place, only slides in
    required property real enterDelay        // ms before a lead row starts to slide in (the stagger, top down)
    required property real stackWidth
    required property bool listMode          // the notification center is open: every tracked notification is wanted
    property bool shown: true                // false: scrolled out of the list (hidden by opacity, nothing is clipped)

    signal removeRequested()
    signal leaveRequested()                  // about to leave: the stack sets `leaveDelay` (stagger while the list closes)
    property real leaveDelay: 0

    // Clear: fly out like a swipe-dismiss after `ms`
    property bool flying: false              // Clear has started to fly it out: it no longer counts as a card of the list
    function sweep(ms) {
        if (ms <= 0) { flyNow(); return }
        sweepTimer.interval = ms
        sweepTimer.restart()
    }
    function flyNow() { flying = true; card.flyOut() }
    Timer { id: sweepTimer; onTriggered: slot.flyNow() }
    signal cardAdded()

    readonly property var n: Notifs.byId[nid]
    property bool dismissing: false          // the user dismissed it: it leaves and the notification is closed afterwards
    readonly property bool listed: listMode ? Notifs.all.values.some(v => v.id === nid) : Notifs.popups.some(p => p.id === nid)
    readonly property bool gone: dismissing || !listed
    readonly property Item cardItem: card
    property real appear: lead ? 1 : 0       // 0 = not there yet, 1 = fully in (drives height too; a lead row is in from the start)
    property real slideX: stackWidth + 40    // distance from its resting place
    // how far in the card is, for its fade: a single new card slides in while its gap opens (the gap drives it); the
    // cards of a list opening are in their place at once (no vertical motion at all) and only slide in from the right
    readonly property real reveal: lead ? 1 - slideX / (stackWidth + 40) : appear

    readonly property real fullHeight: n ? card.implicitHeight + 8 : 0
    width: stackWidth
    height: Math.max(0, Math.round(fullHeight * appear))
    opacity: shown ? 1 : 0
    enabled: shown && !gone

    NotifCard {
        id: card
        visible: slot.n !== undefined && slot.n !== null
        n: slot.n
        showTime: slot.listMode
        width: slot.stackWidth
        height: implicitHeight
        x: slot.slideX
        fade: Math.max(0, Math.min(1, slot.reveal * 1.6))
        Component.onCompleted: slot.cardAdded()

        onDismissRequested: {
            if (slot.dismissing) return
            slot.dismissing = true
            Notifs.dismissPopup(slot.n)
        }
    }

    // Toast timeout: sticky only when critical; apps asking for "never expire" get 7 s on screen (`expireTimeout` is in
    // milliseconds, -1 = the sender has no wish). A transient notification is closed for good when its toast times out
    // (it never reaches the center's history). It runs only while
    // the toast stack is showing: hover / swipe give a fresh timeout on resume (as before), and the center being
    // open PAUSES it: the time already spent is kept (`remaining`) and the rest runs on after the center closes, so
    // looking at the history neither burns nor refunds the toast's time (with the center open no expiry could
    // remove a card from the list anyway, so the toasts are just waiting to be the stack again).
    readonly property real fullMs: card.n && card.n.expireTimeout > 0 ? Math.max(1000, card.n.expireTimeout) : 7000
    readonly property bool counting: !card.critical && !card.hovered && !card.swiping && !slot.gone
    property real remaining: fullMs
    property double startedAt: 0
    onCountingChanged: remaining = fullMs
    onListModeChanged: if (listMode && counting) remaining = Math.max(300, remaining - (Date.now() - startedAt))
    Timer {
        interval: slot.remaining
        running: slot.counting && !slot.listMode
        onRunningChanged: if (running) slot.startedAt = Date.now()
        onTriggered: {
            if (card.n.transient) slot.dismissing = true     // leaves, then is closed (see the exit animation)
            Notifs.dismissPopup(card.n)
        }
    }
    // the app withdrew it: it is being destroyed, so no exit animation
    Connections {
        target: slot.n
        function onClosed() { Notifs.dismissPopup(slot.n); slot.removeRequested() }
    }

    // enter: slide in from the right with a slight overshoot while the space opens up
    function startEnter() { if (lead) enterLead.restart(); else enter.restart() }
    Component.onCompleted: startEnter()
    ParallelAnimation {
        id: enter
        NumberAnimation { target: slot; property: "slideX"; to: 0; duration: 200; easing.type: Easing.OutBack; easing.overshoot: 0.7 }
        NumberAnimation { target: slot; property: "appear"; to: 1; duration: 200; easing.type: Easing.OutCubic }
    }
    SequentialAnimation {
        id: enterLead
        PauseAnimation { duration: slot.enterDelay }
        NumberAnimation { target: slot; property: "slideX"; to: 0; duration: 200; easing.type: Easing.OutBack; easing.overshoot: 0.7 }
    }

    // exit: slide out to the right, then collapse the gap and leave the model (a swiped card is already out: only the
    // gap closes). Wanted again meanwhile (the center closed and opened again): come back from where it is.
    onGoneChanged: {
        if (gone) { enter.stop(); enterLead.stop(); leavePrep.restart() }
        else { leavePrep.stop(); leave.stop(); if (lead) appear = 1; startEnter() }
    }
    // a moment later, once every row has settled on whether it leaves, so the stack can stagger the exits top down
    Timer { id: leavePrep; interval: 1; onTriggered: { slot.leaveRequested(); leave.restart() } }
    SequentialAnimation {
        id: leave
        PauseAnimation { duration: slot.dismissing ? 0 : slot.leaveDelay }
        NumberAnimation { target: slot; property: "slideX"; to: slot.stackWidth + 40; duration: card.swipedOut ? 0 : 200; easing.type: Easing.InQuad }
        NumberAnimation { target: slot; property: "appear"; to: 0; duration: Theme.popupMoveMs; easing.type: Theme.popupEaseClose }
        ScriptAction {
            script: {
                slot.removeRequested()
                // a dismissed notification is closed after its row is gone: closing destroys the object the card draws
                // a replayed stand-in (Notifs.replay) is released once it is no longer a toast (expired, pushed out); only
                // hidden by the open center, it stays and comes back as a toast when the center closes
                const sn = slot.n
                if (slot.dismissing || (sn && sn.standIn === true && Notifs.popups.indexOf(sn) < 0)) Notifs.releaseLater(sn)
            }
        }
    }
}
