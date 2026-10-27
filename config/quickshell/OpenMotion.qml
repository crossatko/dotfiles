import QtQuick

// Open / close progress of a small surface (OSD pill, tray menu), the same model as PopupHost's card: `t` 0..1 runs
// to 1 while `open` (Motion.moveMs, easeEnter) and to 0 after (Motion.exitMs, easeExit), always from the current value
// (an interrupted close turns around and runs only the remaining share of the duration). `shown` stays true until
// the close has finished: bind the window's `visible` to it so the surface unmaps only once nothing is left on it
// (the compositor's glass cannot fade: give the card `glassScale: Theme.glassScaleAt(motion.t)` like the popup cards).
// `delay` (ms) holds a cold open back so a layer surface can map first. Reduced motion = jumps.
// Apply it with the popup style (Theme.popupScaleFrom / popupSlidePx): see `popScale` / `slide`.
Item {
    id: om
    property bool open: false
    property int delay: 0
    property real t: 0
    readonly property bool moving: openAnim.running || closeAnim.running || wait.running
    readonly property bool shown: open || t > 0 || moving
    // the popup style at this progress: scale factor and slide distance still to go (px, towards the anchor edge)
    readonly property real popScale: Theme.popupScaleFrom + (1 - Theme.popupScaleFrom) * t
    readonly property real slide: (1 - t) * Theme.popupSlidePx
    signal closed()

    visible: false
    onOpenChanged: {
        wait.stop(); openAnim.stop(); closeAnim.stop(); guard.stop()
        if (open) {
            if (Motion.reduced) { t = 1; return }
            if (t <= 0 && delay > 0) wait.restart(); else go()
        } else {
            if (Motion.reduced || t <= 0) { t = 0; closed(); return }
            closeAnim.duration = Math.round(Motion.exitMs * Math.min(1, t))
            closeAnim.start()
            guard.restart()
        }
    }
    function go() {
        openAnim.duration = Math.round(Motion.moveMs * Math.max(0, Math.min(1, 1 - t)))
        openAnim.start()
    }
    Timer { id: wait; interval: om.delay; onTriggered: if (om.open) om.go() }
    NumberAnimation { id: openAnim; target: om; property: "t"; to: 1; easing.type: Motion.easeEnter }
    NumberAnimation { id: closeAnim; target: om; property: "t"; to: 0; easing.type: Motion.easeExit; onFinished: { guard.stop(); om.closed() } }
    // Qt advances animations only while the window is exposed (an output that is off / not presenting): a close that
    // has not finished well after its time ends at once, so the surface never stays mapped waiting for frames
    Timer { id: guard; interval: Motion.exitMs + 400; onTriggered: if (!om.open) { closeAnim.stop(); om.t = 0; om.closed() } }
}
