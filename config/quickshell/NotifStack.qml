pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

// THE notification stack: toasts and the notification center are this one item in two modes.
//  - toast mode (`open: false`): one NotifSlot per active toast (Notifs.popups), newest on top.
//  - list mode (`open: true`, the clock chip's popup `notif`): a header (title, count, Clear) opens above the cards and
//    every tracked notification is wanted, newest first. The toasts that are already there stay (same rows, nothing
//    is rebuilt: only the header pushes them down while it opens), the older ones slide in below them. Closing makes
//    every row that is not an active toast leave again.
// The rows are a ListModel of notification ids (a JS-array model would rebuild every card on each change and replay
// the entrance animation on all of them). A row leaves when its id is no longer wanted (clicked, expired, DND,
// cleared, list closed), animates out, and only then leaves the model.
// The list scrolls by WHOLE cards (mouse wheel): Glass.qml cannot see into scrolling views or clip regions, so it is
// not a ListView/Flickable but a Column that moves up; a card that does not fit completely is hidden (opacity 0), so no
// half-visible glass is left behind. Nothing is clipped on purpose: a card that slides out fades out together with its
// glass instead of being cut off by a clip while its blur box stays.
Item {
    id: stack

    property bool open: false
    property real maxHeight: 600            // room for header + cards
    readonly property real cardWidth: 400
    signal cardAdded()                      // a card was created: the window refreshes its glass regions at once

    width: cardWidth
    height: headBlock + view.height

    // 0..1 while the list mode fades / folds in and out
    property real progress: open ? 1 : 0
    Behavior on progress { NumberAnimation { duration: Theme.popupMoveMs; easing.type: Easing.OutCubic } }
    // the header's room is reserved for as long as it is on screen (no unfolding: everything below sits at its final y
    // from the first frame; the header only slides in x)
    readonly property real headBlock: progress > 0.001 ? head.implicitHeight + 8 : 0
    readonly property bool animating: progress > 0.001      // the header is still sliding: the window must stay up
    // stagger between cards that enter / leave one after another (top down); Settings > Animations scales it
    readonly property real stagger: Theme.popupMs(Motion.baseMs * 0.2)
    // rows that are not on their way out (Clear and closing animations are still running for the others)
    property int liveRows: 0
    function recount() {
        let n = 0
        for (let i = 0; i < rep.count; i++) { const it = rep.itemAt(i); if (it && !it.gone && !it.flying) n++ }
        liveRows = n
    }
    // delay for row `i` to leave while the list closes: its place among the visible rows that leave, top down
    function leaveDelayOf(i) {
        let k = 0
        for (let j = 0; j < i; j++) { const o = rep.itemAt(j); if (o && o.gone && !o.dismissing && o.shown) k++ }
        return Math.min(k, sweepMax) * stagger
    }

    property int scroll: 0                                   // index of the first card shown
    readonly property bool overflow: open && column.height - tail > view.height + 1
    readonly property real tail: items.count > 0 ? 8 : 0     // the last slot's trailing gap
    // the largest `scroll` that still fills the view (no gap at the bottom after the last card)
    function maxFirst() {
        void column.height; void view.height
        for (let i = 0; i < rep.count; i++) {
            const it = rep.itemAt(i)
            if (it && column.height - tail - it.y <= view.height + 1) return i
        }
        return Math.max(0, rep.count - 1)
    }
    readonly property int first: Math.max(0, Math.min(scroll, maxFirst()))
    onOpenChanged: { if (!open) scroll = 0; sync(open) }

    // --- model ---
    ListModel { id: items }
    function sync(bulk) {          // bulk: the rows come from opening the list
        const vals = Notifs.all.values
        const rank = {}                                      // id -> position in the history, newest first
        for (let i = 0; i < vals.length; i++) rank[vals[vals.length - 1 - i].id] = i
        const want = open ? vals.slice().reverse() : Notifs.popups
        const have = {}
        for (let i = 0; i < items.count; i++) have[items.get(i).nid] = true
        const closing = Notifs.pendingClose.map(p => p.id)   // dismissed, closed a moment later: do not bring them back
        let k = 0
        for (const m of want) {
            if (have[m.id] || closing.indexOf(m.id) >= 0) continue
            const r = rank[m.id] ?? -1
            let at = 0
            while (at < items.count) {
                const o = rank[items.get(at).nid]
                if (o !== undefined && o > r) break
                at++
            }
            // opening the list: the rows slide in one after another from the top, already in their final place
            items.insert(at, { nid: m.id, lead: bulk === true, enterDelay: bulk === true ? Math.min(k++, sweepMax) * stagger : 0 })
        }
    }
    Connections { target: Notifs; function onPopupsChanged() { stack.sync(false) } }
    Connections { target: Notifs.all; function onValuesChanged() { stack.sync(false) } }
    readonly property alias count: items.count

    // Clear: the cards that are on screen now fly out one after another from the top one down (like a swipe-dismiss,
    // the gap closing behind each), with a short stagger from the motion tokens (Settings > Animations scales it) and
    // at most `sweepMax` of them, so the whole thing stays brief; everything else (scrolled out, past the cap, the
    // history behind the toasts) is closed at once. Only what is there when Clear is pressed: a notification arriving
    // meanwhile is not in the snapshot.
    readonly property int sweepMax: 8
    // After Clear empties the list the center closes (once the last card has flown out); a notification arriving
    // during the sweep keeps it open, and `clearing` lapses on its own.
    property bool clearing: false
    Timer { id: clearLapse; interval: 3000; onTriggered: stack.clearing = false }
    Timer { id: clearClose; interval: Math.max(1, Theme.popupCloseMs); onTriggered: Popups.close() }
    Connections {
        target: Notifs
        function onCountChanged() {
            if (stack.clearing && Notifs.count === 0) { stack.clearing = false; clearLapse.stop(); clearClose.restart() }
        }
    }
    function clearAll() {
        clearing = Popups.name === "notif"
        if (clearing) clearLapse.restart()
        const animated = {}
        let k = 0
        for (let i = first; i < rep.count && k < sweepMax; i++) {
            const it = rep.itemAt(i)
            if (!it || it.gone || !it.shown) continue
            animated[it.nid] = true
            it.sweep(k * stagger)
            k++
        }
        for (const n of Notifs.all.values.slice())
            if (!animated[n.id]) Notifs.closeNow(n)
    }
    Connections { target: Notifs; function onClearRequested() { stack.clearAll() } }

    // --- header (list mode) ---
    NotifHeader {
        id: head
        y: 0
        x: (1 - stack.progress) * (stack.width + 40)  // slides in from / out to the right like the cards
        width: stack.width
        opacity: Math.min(1, stack.progress * 1.6)
        visible: stack.animating
        overflow: stack.overflow
    }

    // --- cards ---
    Item {
        id: view
        y: stack.headBlock
        width: stack.width
        // list mode: as tall as the cards, up to the room there is; toast mode: the toasts
        height: stack.open ? Math.min(Math.max(column.height - stack.tail, emptyStrip.visible ? emptyStrip.implicitHeight : 0), Math.max(0, stack.maxHeight - head.implicitHeight - 8)) : column.height
        readonly property real topY: { void rep.count; const it = rep.itemAt(stack.first); return it ? it.y : 0 }

        NotifEmpty {
            id: emptyStrip
            width: view.width
            x: (1 - stack.progress) * (view.width + 40)        // slides with the header
            opacity: (stack.open || stack.animating) && stack.liveRows === 0 ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        Column {
            id: column
            width: view.width
            y: -view.topY
            Repeater {
                id: rep
                model: items
                onItemAdded: { stack.cardAdded(); if (stack.open) Qt.callLater(() => stack.scroll = 0) }   // a new one lands on top: show it
                delegate: NotifSlot {
                    id: row
                    stackWidth: column.width
                    listMode: stack.open
                    // whole cards only: the first one shown always, others when they fit completely
                    shown: !stack.open || index === stack.first
                        || (y >= view.topY - 1 && y + cardItem.implicitHeight <= view.topY + view.height + 1)
                    onRemoveRequested: items.remove(index)
                    onGoneChanged: stack.recount()
                    onFlyingChanged: stack.recount()
                    onLeaveRequested: leaveDelay = stack.leaveDelayOf(index)
                    Component.onCompleted: stack.recount()
                    Component.onDestruction: Qt.callLater(stack.recount)
                    onCardAdded: stack.cardAdded()
                }
            }
        }

        WheelHandler {
            enabled: stack.open
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            property real acc: 0
            onWheel: ev => {
                acc += ev.angleDelta.y
                while (Math.abs(acc) >= 120) {
                    stack.scroll = Math.max(0, Math.min(stack.first + (acc < 0 ? 1 : -1), stack.maxFirst()))
                    acc += acc < 0 ? 120 : -120
                }
            }
        }
    }
}
