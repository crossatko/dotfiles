import QtQuick

// Entrance of content that was just swapped in place (a Settings page, a launcher section / action list, a tray
// submenu): play() fades `target` in and lets it rise `rise` px into place (Motion.moveMs, easeEnter). No exit: the
// old content is gone at once and the new one arrives, which keeps switching quick. Reduced motion = nothing.
// It owns a Translate that it appends to the target's transforms once. A play() while one runs restarts from the
// start (a fast series of switches never leaves the content half transparent: the last one always completes).
// Usage:   Reveal { id: rv; target: pageLoader }   ...   onLoaded: rv.play()
Item {
    id: rv
    property Item target: parent
    property real rise: 8
    property real from: 0                    // opacity it starts at
    property real p: 1                       // 0 -> 1 while playing

    visible: false
    function play() {
        anim.stop()
        if (!target || Motion.reduced) { p = 1; return }
        p = 0
        anim.start()
    }
    NumberAnimation { id: anim; target: rv; property: "p"; to: 1; duration: Motion.moveMs; easing.type: Motion.easeEnter }
    Translate { id: shift; y: (1 - rv.p) * rv.rise }
    Binding { target: rv.target; property: "opacity"; value: rv.from + (1 - rv.from) * Math.max(0, Math.min(1, rv.p)); when: rv.target !== null && rv.p < 1 }
    onTargetChanged: attach()
    Component.onCompleted: attach()
    function attach() {
        if (!target) return
        const ts = []
        for (const t of target.transform) { if (t === shift) return; ts.push(t) }
        ts.push(shift)
        target.transform = ts
    }
}
