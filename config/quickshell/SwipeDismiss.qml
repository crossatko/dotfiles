pragma ComponentBehavior: Bound
import QtQuick

// Swipe-to-dismiss for a card (notification toasts and the notification center list): press and drag the card to
// the right with the mouse, it follows the pointer 1:1 and fades with the distance; left is a short rubber band.
// On release past `distanceFrac` of the card width, or after a fast flick to the right, it flies off to the right and
// fades out, then `swiped()` fires (the owner runs its normal dismiss path); otherwise it springs back to 0.
//
// Usage, inside the card:
//     SwipeDismiss { id: swipe; onSwiped: card.dismiss() }
//     transform: Translate { x: swipe.offset }      // not `x`: the owner may animate x itself (toast slide-in)
//     opacity: swipe.fade
// The DragHandler sits on the card itself (re-parented, like HoverGlow's HoverHandler), x axis only, threshold
// `dragThreshold` px: a press-release with less movement stays a click (the card's TapHandlers), and child controls
// with their own MouseArea (close, action buttons) keep their presses. Axis lock: a gesture that is more vertical than
// horizontal when the threshold is crossed is ignored (and lets a ListView take it over); a ListView that crosses its
// own (larger) threshold first takes the gesture before this handler activates. Durations / easing follow the popup
// motion tokens (Settings > Animations speed / curve).
Item {
    id: sw

    property Item target: parent
    property bool swipeEnabled: true
    property real distanceFrac: 0.38        // release past this share of the width -> dismiss
    property real flickVelocity: 900        // px/s to the right at release -> dismiss ...
    property real flickMinDistance: 24      // ... if it moved at least this far to the right
    property real dragThreshold: 6          // px before a press becomes a drag (below: still a click)
    property real leftMax: 24               // rubber band to the left approaches this many px
    property real velocityWindowMs: 100     // a pause longer than this before release = no flick

    readonly property real w: target ? Math.max(1, target.width) : 1
    property real offset: 0                 // the card's horizontal displacement (bind a Translate to it)
    readonly property real fade: offset <= 0 ? 1 : Math.max(0, 1 - offset / w)
    readonly property bool dragging: dh.active && !vertical
    readonly property bool busy: dh.active || back.running || out.running || gone
    property bool gone: false               // flown off (stays true: the owner removes the card)
    signal swiped()

    // --- pure logic (unit-tested) ---
    // raw horizontal pointer movement -> offset: 1:1 to the right, rubber band to the left
    function rubber(dx) { return dx >= 0 ? dx : -leftMax * (-dx) / (-dx + leftMax) }
    // release decision: distance past the threshold, or a fast flick to the right that moved far enough
    function shouldDismiss(off, vx, width) {
        if (off >= distanceFrac * width) return true
        return vx >= flickVelocity && off >= flickMinDistance
    }
    // fly-off duration: the close duration for the remaining share of the width (at least 40 % of it); a flick
    // faster than that continues at its own speed (OutCubic starts at 3x the mean speed)
    function flyMs(off, vx, width) {
        const rest = Math.max(0, width - off)
        let ms = Theme.popupMs(Motion.baseMs * 0.75 * Math.max(0.4, rest / width))
        if (ms > 0 && vx > 0) ms = Math.max(Math.min(ms, Math.round(3000 * rest / vx)), Theme.popupMs(1))
        return ms
    }

    // --- gesture state ---
    property real startOffset: 0
    property bool vertical: false            // this gesture was locked to the vertical axis: ignore it
    property bool cancelled: false
    property real vx: 0                       // px/s, smoothed over the last moves
    property real lastX: 0
    property real lastT: 0

    function begin() {
        back.stop()
        startOffset = offset
        const p = dh.centroid
        const dx = p.scenePosition.x - p.scenePressPosition.x
        const dy = p.scenePosition.y - p.scenePressPosition.y
        vertical = Math.abs(dy) > Math.abs(dx)
        cancelled = false
        vx = 0
        lastX = p.scenePosition.x
        lastT = Date.now()
    }
    function move() {
        if (vertical) return
        const p = dh.centroid
        const now = Date.now()
        const dt = now - lastT
        if (dt > 0) {
            const v = (p.scenePosition.x - lastX) * 1000 / dt
            vx = dt >= velocityWindowMs ? v : vx * 0.4 + v * 0.6
            lastX = p.scenePosition.x
            lastT = now
        }
        offset = rubber(startOffset + p.scenePosition.x - p.scenePressPosition.x)
    }
    function release() {
        if (vertical) { vertical = false; return }
        const v = Date.now() - lastT > velocityWindowMs ? 0 : vx
        settle(!cancelled && shouldDismiss(offset, v, w), v)
    }
    // animate to the decided end; also the test hook for the nested visual check (settle(true / false, vx))
    function settle(dismiss, v) {
        if (dismiss) {
            out.duration = flyMs(offset, v, w)
            out.to = w
            out.start()
        } else {
            back.start()
        }
    }

    DragHandler {
        id: dh
        parent: sw.target
        target: null
        enabled: sw.swipeEnabled && !sw.gone && !out.running
        acceptedButtons: Qt.LeftButton
        yAxis.enabled: false
        dragThreshold: sw.dragThreshold
        // horizontal: keep the gesture (a ListView may not steal it); locked vertical: hand it over to a ListView
        grabPermissions: sw.vertical ? PointerHandler.CanTakeOverFromAnything | PointerHandler.ApprovesTakeOverByAnything
            : PointerHandler.CanTakeOverFromAnything
        onActiveChanged: active ? sw.begin() : sw.release()
        onCentroidChanged: if (active) sw.move()
        onCanceled: sw.cancelled = true
    }

    NumberAnimation {
        id: back
        target: sw; property: "offset"; to: 0
        duration: Theme.popupOpenMs
        easing.type: Theme.popupEaseOpen
    }
    NumberAnimation {
        id: out
        target: sw; property: "offset"
        easing.type: Theme.popupEaseClose
        onFinished: { sw.gone = true; sw.swiped() }
    }
}
