pragma ComponentBehavior: Bound
import QtQuick

// Password echo of the lock screen: one glass bead (GlassBead, the clock's glass) per typed character, centred in
// `width`. Each pops in with the popup open motion and the row re-centres with the move motion; the gap shrinks to fit a
// long password, then the beads do. `busy` = a soft wave of the shell's busy pulse while PAM checks. `reject(n)` = a
// wrong password: n beads fill with red, shake, fade out, clear. `origin` = this item's top-left in the backdrop.
Item {
    id: dots
    property int count: 0
    property bool busy: false
    property int beadSize: 22
    property Item backdrop: null
    property Item sharpBackdrop: null
    property real sharpInset: 0
    property point origin: Qt.point(0, 0)
    property size backdropSize: Qt.size(1, 1)

    property bool rejecting: false
    property int heldCount: 0
    readonly property int shown: rejecting ? heldCount : count
    function reject(n) {
        if (n <= 0) return
        heldCount = n
        rejecting = true
        rejectAnim.restart()
    }

    // layout: gap from 0.7 bead down to 0.2 bead, then smaller beads
    readonly property real fitGap: shown > 1 ? (width - shown * beadSize) / (shown - 1) : beadSize
    readonly property real gap: Math.max(beadSize * 0.2, Math.min(beadSize * 0.7, fitGap))
    readonly property real size: shown > 0 ? Math.min(beadSize, width / (shown + (shown - 1) * 0.2)) : beadSize
    readonly property real stride: size + (size < beadSize ? size * 0.2 : gap)
    readonly property real rowWidth: shown > 0 ? (shown - 1) * stride + size : 0
    implicitHeight: beadSize

    // one model row per bead, appended / removed at the end only: an integer model resets and re-creates every delegate
    // (every bead would pop in again on each keystroke)
    ListModel { id: beadModel }
    function syncModel() {
        while (beadModel.count < shown) beadModel.append({})
        while (beadModel.count > shown) beadModel.remove(beadModel.count - 1)
    }
    onShownChanged: syncModel()
    Component.onCompleted: syncModel()

    property real phase: 0
    NumberAnimation on phase {
        running: dots.busy && dots.visible && duration > 0
        from: 0; to: 1
        duration: Theme.popupMs(2 * Theme.busyPulseMs)   // the busy pulse at the animation speed (none: no pulse)
        loops: Animation.Infinite
    }

    Item {
        id: row
        width: parent.width
        height: parent.height
        transform: Translate { id: shift }
        Repeater {
            model: beadModel
            GlassBead {
                id: bead
                required property int index
                property real appear
                readonly property real wave: 0.775 + 0.225 * Math.cos(2 * Math.PI * (dots.phase - bead.index / 8))
                size: Math.round(dots.size)
                x: Math.round((dots.width - dots.rowWidth) / 2 + bead.index * dots.stride)
                y: Math.round((dots.height - bead.size) / 2)
                Behavior on x { NumberAnimation { duration: Theme.popupMoveMs; easing.type: Theme.popupEaseMove } }
                backdrop: dots.backdrop
                sharpBackdrop: dots.sharpBackdrop
                sharpInset: dots.sharpInset
                dim: Theme.lockDim
                backdropSize: dots.backdropSize
                origin: Qt.point(dots.origin.x + bead.x + shift.x, dots.origin.y + bead.y)
                glow: Theme.alpha(Theme.red, dots.rejecting ? 0.55 : 0)
                Behavior on glow { ColorAnimation { duration: Theme.popupFadeInMs } }
                flatColor: dots.rejecting ? Theme.red : Theme.fg
                scale: bead.appear
                opacity: Math.min(1, bead.appear) * (dots.busy ? bead.wave : 1)
                NumberAnimation on appear { from: 0; to: 1; duration: Theme.popupOpenMs; easing.type: Easing.OutBack }
            }
        }
    }

    // wrong password: shake (damped, Theme.shakeMs), fade out, clear
    SequentialAnimation {
        id: rejectAnim
        NumberAnimation { target: shift; property: "x"; to: -Theme.shakePx; duration: Theme.shakeMs / 6; easing.type: Easing.OutSine }
        NumberAnimation { target: shift; property: "x"; to: Theme.shakePx * 0.8; duration: Theme.shakeMs / 4; easing.type: Easing.InOutSine }
        NumberAnimation { target: shift; property: "x"; to: -Theme.shakePx * 0.5; duration: Theme.shakeMs / 4; easing.type: Easing.InOutSine }
        NumberAnimation { target: shift; property: "x"; to: Theme.shakePx * 0.25; duration: Theme.shakeMs / 6; easing.type: Easing.InOutSine }
        NumberAnimation { target: shift; property: "x"; to: 0; duration: Theme.shakeMs / 6; easing.type: Easing.OutSine }
        PauseAnimation { duration: Theme.popupOpenMs }
        NumberAnimation { target: row; property: "opacity"; to: 0; duration: Theme.popupCloseMs; easing.type: Theme.popupEaseClose }
        ScriptAction { script: { dots.rejecting = false; row.opacity = 1 } }
    }
}
