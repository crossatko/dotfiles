import QtQuick

// The lock's desktop snapshot with the desktop clock faded out of it (LockView -> LockReveal). The snapshot is taken
// with the clock on screen (no hide before it: the clock does not snap away while the lock comes up); `patch` = that
// clock's rect without the clock (DeskClock.patches: the backdrop its glass refracts, grabbed at the lock request) is
// laid over it and fades in once `fading` (the lock is up), so the clock fades out on the lock surface and the unlock
// ring opens onto a desktop without it. A texture provider while `active`; otherwise LockView uses the bare snapshot.
Item {
    id: p
    property Item snapshot: null
    property var patch: null              // { result (ItemGrabResult), x, y, w, h } in this item's (screen) px
    property bool fading: false
    property real t: 0                    // 0 = the snapshot as taken (clock), 1 = the clock gone
    readonly property bool active: snapshot !== null && !!patch && !!patch.result
    visible: false
    layer.enabled: active

    function run() {
        if (!active || !fading || t >= 1 || fade.running) return
        fade.duration = Theme.popupMs(Motion.baseMs)
        if (fade.duration <= 0) t = 1
        else fade.start()
    }
    // the end state (clean rect fully drawn) stays until another patch comes: the unlock ring opens onto it, and the
    // surface's last frames after the unlock must not show the clock again
    onFadingChanged: run()
    onActiveChanged: run()
    property var lastResult: null
    onPatchChanged: {
        const r = patch ? patch.result : null
        if (r === lastResult) return          // the same grab handed in again (another screen's arrived)
        lastResult = r
        fade.stop(); t = 0; run()
    }
    NumberAnimation { id: fade; target: p; property: "t"; to: 1; easing.type: Easing.InOutSine }

    ShaderEffectSource { anchors.fill: parent; sourceItem: p.snapshot; hideSource: false }
    Image {
        x: p.active ? p.patch.x : 0
        y: p.active ? p.patch.y : 0
        width: p.active ? p.patch.w : 0
        height: p.active ? p.patch.h : 0
        source: p.active ? p.patch.result.url : ""
        cache: false
        smooth: true
        opacity: p.t
    }
}
