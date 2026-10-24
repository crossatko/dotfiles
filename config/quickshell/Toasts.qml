pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

// Notification toasts, top-right of the focused monitor (below a top bar if that screen has one).
PanelWindow {
    id: win

    property var bars: ({})
    property var target: Quickshell.screens[0]

    screen: target
    visible: Notifs.popups.length > 0 || items.count > 0   // stays up while the last card is still animating out
    anchors { top: true; right: true }
    margins {
        // Theme.edgeGap from the screen edge, or below a top bar (incl. a floating bar's gap) by the same amount
        top: BarConfig.edgeGapOf(screen) + (bars[(screen ? screen.name : "")] === "top" ? BarConfig.reserveOf(screen) : 0)
        right: 0
    }
    implicitWidth: 400 + BarConfig.edgeGapOf(screen) // the cards + edgeGap of room: the slide-out then leaves through the screen edge
    // The window is NOT sized to the animating column: a layer surface that is resized is shown stretched to its new
    // size until the matching buffer arrives, which squashed and overlapped the cards on every frame of a gap opening
    // or closing (nested frame captures 2026-10-21; a single shrink still squashed one frame). So it is sized to the
    // FULL heights of the cards in the stack (entering ones at once, leaving ones until they leave the model) and,
    // with solid_glass (only the cards are glass, the rest is transparent and outside the input mask), it only grows
    // while toasts are up and shrinks when the stack is empty and the window hides. Without solid_glass the whole
    // window is the blur region, so it follows the stack (one resize after a card has left).
    property real stackHeight: 0
    property real heldHeight: 0
    function updateStack() {
        let h = 0
        for (let i = 0; i < stack.count; i++) {
            const it = stack.itemAt(i)
            if (it) h += it.fullHeight
        }
        stackHeight = h
        heldHeight = stack.count === 0 ? 0 : Math.max(heldHeight, h)
    }
    implicitHeight: Math.max(1, Theme.glass ? heldHeight : stackHeight)
    color: "transparent"
    exclusiveZone: -1                  // ignore the monitor's reserved area (the pinned-video strip), so it stays in the screen corner
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-toast"
    BackgroundEffect.blurRegion: Region { regions: glass.instances }
    Glass { id: glass; root: contentItem; active: visible }
    mask: Region { item: col }      // clicks outside the cards fall through

    // follow focus, but only when a new stack starts (0 -> 1), so a toast never jumps monitors
    property int lastCount: 0
    Connections {
        target: Notifs
        function onPopupsChanged() {
            const n = Notifs.popups.length
            if (win.lastCount === 0 && n > 0) {
                win.target = Popups.focusedScreen()
            }
            win.lastCount = n
        }
    }

    // The stack is a ListModel of notification ids: a JS-array model would rebuild every card on each
    // change and replay the entrance animation on all of them. A card leaves when its id is no longer in
    // Notifs.popups (clicked, expired, DND, cleared), animates out, and only then leaves the model.
    ListModel { id: items }
    Connections {
        target: Notifs
        function onPopupsChanged() {
            const want = Notifs.popups.map(p => p.id)
            const have = []
            for (let i = 0; i < items.count; i++) have.push(items.get(i).nid)
            // newest first; popups is already newest-first, so insert missing ones at the top in order
            const fresh = want.filter(id => have.indexOf(id) < 0)
            for (let i = fresh.length - 1; i >= 0; i--) items.insert(0, { nid: fresh[i] })
        }
    }

    Column {
        id: col
        width: 400
        spacing: 0

        Repeater {
            id: stack
            model: items
            onItemAdded: { glass.refresh(); win.updateStack() }   // the new card has its glass from its first frame
            onItemRemoved: Qt.callLater(win.updateStack)

            Item {
                id: slot
                required property int index
                required property int nid
                readonly property var n: Notifs.byId[nid]
                readonly property bool gone: Notifs.popups.findIndex(p => p.id === nid) < 0
                property real appear: 0              // 0 = not there yet, 1 = fully in (drives height too)
                property real slideX: col.width + 40 // distance from its resting place

                width: col.width
                readonly property real fullHeight: n ? card.implicitHeight + 8 : 0
                onFullHeightChanged: win.updateStack()
                height: Math.round(fullHeight * appear)
                clip: false

                NotifCard {
                    id: card
                    visible: slot.n !== undefined && slot.n !== null
                    n: slot.n
                    toast: true
                    width: col.width
                    height: implicitHeight
                    x: slot.slideX
                    opacity: Math.min(1, slot.appear * 1.6) * card.swipeFade

                    // sticky only when critical; apps asking for "never expire" get 7s on screen
                    Timer {
                        interval: card.n && card.n.expireTimeout > 0 ? card.n.expireTimeout * 1000 : 7000
                        running: !card.critical && !card.hovered && !card.swiping && !slot.gone
                        onTriggered: Notifs.dismissPopup(card.n)
                    }
                    Connections {
                        target: slot.n
                        // the app withdrew it: it is being destroyed, so no exit animation
                        function onClosed() { Notifs.dismissPopup(slot.n); items.remove(slot.index) }
                    }
                }

                // enter: slide in from the right with a slight overshoot while the space opens up
                Component.onCompleted: enter.start()
                ParallelAnimation {
                    id: enter
                    NumberAnimation { target: slot; property: "slideX"; to: 0; duration: 200; easing.type: Easing.OutBack; easing.overshoot: 0.7 }
                    NumberAnimation { target: slot; property: "appear"; to: 1; duration: 200; easing.type: Easing.OutCubic }
                }

                // exit: slide out to the right, then collapse the gap and leave the model (a swiped card is already
                // out: only the gap closes)
                onGoneChanged: if (gone) { enter.stop(); leave.start() }
                SequentialAnimation {
                    id: leave
                    NumberAnimation { target: slot; property: "slideX"; to: col.width + 40; duration: card.swipedOut ? 0 : 200; easing.type: Easing.InCubic }
                    NumberAnimation { target: slot; property: "appear"; to: 0; duration: Theme.popupMoveMs; easing.type: Theme.popupEaseClose }
                    ScriptAction { script: items.remove(slot.index) }
                }
            }
        }
    }
}
