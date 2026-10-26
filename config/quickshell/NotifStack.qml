pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

// THE notification stack: toasts and the notification center are this one item in two modes.
//  - toast mode (`open: false`): one NotifSlot per active toast (Notifs.popups), newest on top.
//  - list mode (`open: true`, the clock chip's popup `notif`): every tracked notification is wanted, newest first. The
//    toasts that are already there stay exactly where they are (same rows, nothing is rebuilt, nothing is pushed:
//    the list has no header), the older ones slide in below them from the right, one after another, and a plain
//    bottom row (count, scroll hint, Clear: NotifHeader.qml, historical name) slides in after the last card, under the
//    last card that is shown. Closing makes every row that is not an active toast, then the bottom row, slide out.
// The rows are a ListModel of notification ids (a JS-array model would rebuild every card on each change and replay
// the entrance animation on all of them). A row leaves when its id is no longer wanted (clicked, expired, DND,
// cleared, list closed), animates out, and only then leaves the model.
// In the list, cards of one app are kept together (see sync): a repeated notification from an app joins that app's group.
// The list scrolls by WHOLE cards (mouse wheel): Glass.qml cannot see into scrolling views or clip regions, so it is
// not a ListView/Flickable but a Column that moves up; a card that does not fit completely is hidden (opacity 0), so no
// half-visible glass is left behind. Nothing is clipped on purpose: a card that slides out fades out together with its
// glass instead of being cut off by a clip while its blur box stays.
Item {
    id: stack

    property bool open: false
    property real maxHeight: 600            // room for the cards + the bottom row
    readonly property real cardWidth: 400
    signal cardAdded()                      // a card was created: the window refreshes its glass regions at once

    width: cardWidth
    height: footProgress > 0.001 ? foot.y + foot.implicitHeight : view.height

    // 0..1 while the list mode slides in and out (the empty strip)
    property real progress: open ? 1 : 0
    Behavior on progress { NumberAnimation { duration: Theme.popupMoveMs; easing.type: Easing.OutCubic } }
    // the bottom row: wanted while the list is open and has cards; it slides in after the last card has come in and out
    // after the last one has left (`footDelay`, set just before the change by whoever knows how many cards move)
    property real footProgress: 0
    property bool footTarget: false
    property real footDelay: 0
    function syncFoot() {
        const want = open && items.count > 0 && !clearing       // Clear: the row leaves first, then the cards sweep
        if (want === footTarget) return
        footTarget = want
        footAnim.stop()
        footTo.to = want ? 1 : 0
        footPause.duration = footDelay
        footDelay = 0
        footAnim.start()
    }
    SequentialAnimation {
        id: footAnim
        PauseAnimation { id: footPause }
        NumberAnimation { id: footTo; target: stack; property: "footProgress"; duration: Theme.popupMoveMs; easing.type: Easing.OutCubic }
    }
    Connections { target: items; function onCountChanged() { stack.syncFoot() } }
    readonly property real footFull: foot.implicitHeight + 8
    // the window must stay up while anything is still sliding
    readonly property bool animating: progress > 0.001 || footProgress > 0.001
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
    // bottom of the last card that is shown (view coordinates): the bottom row sits right under it, not under hidden ones
    readonly property real shownBottom: {
        void column.height; void view.topY; void first; void items.count; void view.height
        let b = 0
        for (let i = 0; i < rep.count; i++) {
            const it = rep.itemAt(i)
            if (it && it.shown) b = Math.max(b, it.y + Math.max(0, it.height - 8) - view.topY)
        }
        return b
    }
    property bool sawRows: false      // a card showed up since the center opened (the list fills just after it opens; an empty one only opens for do-not-disturb / IPC)
    onOpenChanged: {
        if (open) {
            sawRows = items.count > 0
            footDelay = Math.min(Math.max(0, Notifs.all.values.length - items.count), sweepMax) * stagger
        } else {
            // rows that are about to slide out (not an active toast), top down, before the bottom row follows
            let k = 0
            for (let i = first; i < rep.count && k < sweepMax; i++) {
                const it = rep.itemAt(i)
                if (it && !it.gone && !Notifs.popups.some(p => p.id === it.nid)) k++
            }
            footDelay = k * stagger
            scroll = 0
        }
        sync(open)
        syncFoot()
    }

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
            // cards of one app sit together, ordered by arrival among themselves (a new one goes above its app's group); an
            // app without a group yet goes by arrival, and never lands inside another app's group
            let at = 0
            let firstSame = -1, lastSame = -1, above = -1
            for (let i = 0; i < items.count; i++) {
                if (items.get(i).app !== m.appName) continue
                if (firstSame < 0) firstSame = i
                lastSame = i
                const o = rank[items.get(i).nid]
                if (above < 0 && o !== undefined && o > r) above = i
            }
            if (open && firstSame >= 0) at = above >= 0 ? above : lastSame + 1
            else {
                while (at < items.count) {
                    const o = rank[items.get(at).nid]
                    if (o !== undefined && o > r) break
                    at++
                }
                while (open && at > 0 && at < items.count && items.get(at - 1).app === items.get(at).app) at++
            }
            // opening the list: the rows slide in one after another from the top, already in their final place
            items.insert(at, { nid: m.id, app: m.appName, lead: bulk === true, enterDelay: bulk === true ? Math.min(k++, sweepMax) * stagger : 0 })
        }
    }
    Connections { target: Notifs; function onPopupsChanged() { stack.sync(false) } }
    Connections { target: Notifs.all; function onValuesChanged() { stack.sync(false) } }
    readonly property alias count: items.count

    // Clear: the cards that are on screen now fly out one after another from the BOTTOM one up, starting right above
    // where the Clear button was (like a swipe-dismiss, the gap closing behind each), with a short stagger from the motion tokens (Settings > Animations scales it) and
    // at most `sweepMax` of them, so the whole thing stays brief; everything else (scrolled out, past the cap, the
    // history behind the toasts) is closed at once. Only what is there when Clear is pressed: a notification arriving
    // meanwhile is not in the snapshot.
    readonly property int sweepMax: 8
    // After Clear empties the list the center closes as soon as the last card is gone; a notification arriving during
    // the sweep keeps it open, and `clearing` lapses on its own.
    property bool clearing: false
    onClearingChanged: syncFoot()
    // while Clear is in progress the bottom row slides out first; the cards start once it has (mostly) gone
    readonly property real sweepBase: clearing && footProgress > 0.001 ? Theme.popupMoveMs * 0.7 : 0
    Timer { id: clearLapse; interval: 3000; onTriggered: { stack.clearing = false } }
    Connections {
        target: items
        function onCountChanged() {
            if (stack.clearing && items.count === 0) { stack.clearing = false; clearLapse.stop(); Popups.close() }
            // the last card dismissed one by one: the center closes instead of showing the empty strip (do-not-disturb keeps it)
            if (stack.open && items.count > 0) stack.sawRows = true
            else if (stack.open && stack.sawRows && items.count === 0 && !stack.clearing && !Notifs.dnd) Popups.close()
        }
    }
    function clearAll() {
        clearing = Popups.name === "notif"
        if (clearing) clearLapse.restart()
        const animated = {}
        let k = 0
        for (let i = rep.count - 1; i >= first && k < sweepMax; i--) {      // bottom up
            const it = rep.itemAt(i)
            if (!it || it.gone || !it.shown) continue
            animated[it.nid] = true
            it.sweep(sweepBase + k * stagger)
            k++
        }
        for (const n of Notifs.all.values.slice())
            if (!animated[n.id]) Notifs.closeNow(n)
    }
    Connections { target: Notifs; function onClearRequested() { stack.clearAll() } }

    // --- bottom row (list mode): count, scroll hint, Clear; plain, no glass ---
    NotifHeader {
        id: foot
        y: stack.shownBottom + 8
        x: (1 - stack.footProgress) * (stack.width + 40)  // slides in from / out to the right like the cards
        width: stack.width
        opacity: Math.min(1, stack.footProgress * 1.6)
        visible: stack.footProgress > 0.001
        overflow: stack.overflow
    }

    // --- cards ---
    Item {
        id: view
        y: 0                                  // the cards start where the toasts sit
        width: stack.width
        // list mode: as tall as the cards, up to the room there is (less the bottom row); toast mode: the toasts
        height: stack.open ? Math.min(Math.max(column.height - stack.tail, 0), Math.max(0, stack.maxHeight - stack.footFull)) : column.height
        readonly property real topY: { void rep.count; const it = rep.itemAt(stack.first); return it ? it.y : 0 }

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
                    // whole cards only: the first one shown always, others when they fit completely; closing keeps what
                    // was shown (a row that was scrolled out of the list does not appear just to slide out)
                    property bool wasShown: true
                    onShownChanged: if (stack.open) wasShown = shown
                    shown: stack.open ? (index === stack.first
                        || (y >= view.topY - 1 && y + cardItem.implicitHeight <= view.topY + view.height + 1)) : wasShown
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
