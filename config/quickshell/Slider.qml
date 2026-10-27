pragma ComponentBehavior: Bound
import QtQuick

// Horizontal slider, 0..1. `value` is the real state; dragging emits moved(v) and never sets `value`
// itself, so it always shows the truth.
// Notches (NotchSnap): `notches` = values 0..1 where the handle sticks (a number or { v, kind: "default" | "extra" };
// the first bare number is the default). A drag snaps onto a notch near the pointer and holds it for a few px, wheel and
// arrow steps stop on a notch they cross, Shift + arrow jumps notch to notch, a double-click resets: to the default notch
// (`resetToNotch`), and always resetRequested() (rows with a reset glyph unset their key there instead). Tab focuses.
Item {
    id: sl
    property real value: 0
    property bool dim: false
    property real floor: 0              // lowest value a drag / wheel can emit (brightness keeps screens from going black)
    property real mark: -1              // older API: one default notch at this position (0..1), e.g. the 1x of a speed slider
    property var notches: []            // see the header; `mark` comes first when set
    property bool resetToNotch: true    // double-click emits moved(default notch); false = only resetRequested()
    property real step: 0.01            // arrow-key step (0..1)
    property bool wheel: true           // false = the wheel passes through (sliders on scrolling pages: scrolling must not change them)
    signal moved(real v)
    signal resetRequested()

    activeFocusOnTab: true
    NotchSnap {
        id: notch
        floor: sl.floor
        start: 8
        length: Math.max(1, sl.width - 16)
        notches: sl.mark >= 0 ? [{ v: sl.mark, kind: "default" }].concat(sl.notches || []) : (sl.notches || [])
    }
    readonly property real defaultNotch: notch.defaultValue
    readonly property real notchPulsePx: 3      // how much a snap "click" swells the handle / lens
    function emit(v) { drag.live = v; sl.moved(v) }
    Keys.onPressed: e => {
        const dir = e.key === Qt.Key_Right || e.key === Qt.Key_Up ? 1 : e.key === Qt.Key_Left || e.key === Qt.Key_Down ? -1 : 0
        if (dir === 0) return
        e.accepted = true
        emit((e.modifiers & Qt.ShiftModifier) ? notch.jump(sl.value, dir) : notch.stepFrom(sl.value, dir * sl.step))
    }

    implicitHeight: 24
    opacity: dim ? Theme.disabledOpacity : 1

    // `held` follows the press but is set in onDownChanged AFTER `settling`, so the switch from the pointer to `value`
    // on release already runs with the settle Behavior on
    property bool held: false
    readonly property real shown: held ? drag.live : value
    // pointer x -> value with the handle's own travel: the handle centre runs over [8, width - 8] (x = v * (width - 16)),
    // so a press or drag puts the handle (and lens) centre exactly under the pointer, also when pressing the handle
    // off-centre (no grab offset); clamped past the ends
    function valueAt(px) { return Math.max(floor, Math.min(1, (px - 8) / Math.max(1, width - 16))) }

    Meter {
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        // the fill ends at the handle centre (same travel as the handle), not at value x width
        value: sl.shown <= 0 ? 0 : (Math.min(1, sl.shown) * (sl.width - 16) + 8) / Math.max(1, sl.width)
        animMs: sl.settling ? Math.max(90, Theme.popupCloseMs) : 90
        animate: !drag.pressed
    }
    NotchTicks { snap: notch }

    // Pressed / dragging: the handle grows into a small liquid-glass lens (1:1 squircle / circle, 16 -> 28 px) that
    // REFRACTS what the shell drew under it (track, fill, card, text) with the Settings > Glass values (GlassTuneCtl,
    // see shaders/sliderlens.frag), and shrinks back on release. `grow` 0..1 runs on the popup motion tokens
    // (Settings > Animations: Theme.popupOpenMs / popupCloseMs and popupEaseOpen / popupEaseClose, style none =
    // instant), like a popup opening / closing; only an overshooting curve (Back) overshoots. The lens is drawn over a
    // capture of the whole card the slider sits on (`host`: nearest `isGlassItem` ancestor, else the top item): while
    // it runs the card is hidden (hideSource) and the effect, a sibling of the card, draws it in full, so the
    // un-refracted content never shows through the lens and the lens is not in its own capture. Nothing of this
    // exists at rest (Loader inactive). Hit area unchanged; the lens centre is the handle centre (not clamped, may overhang). Hover does nothing.
    readonly property bool down: drag.pressed
    property real grow: 0
    onDownChanged: {
        if (down)
            host = lens.findHost(sl)
        settling = !down && Theme.popupCloseMs > 0
        if (settling) settle.restart()
        held = down
        growAnim.stop()
        growAnim.to = down ? 1 : 0
        growAnim.easing.type = down ? Theme.popupEaseOpen : Theme.popupEaseClose
        // the remaining distance's share of the duration (interrupt-safe, as PopupHost)
        growAnim.duration = down ? Math.round(Theme.popupOpenMs * Math.max(0, Math.min(1, 1 - grow)))
                                 : Math.round(Theme.popupCloseMs * Math.max(0, Math.min(1, grow)))
        if (growAnim.duration <= 0) grow = growAnim.to
        else growAnim.start()
    }
    NumberAnimation { id: growAnim; target: sl; property: "grow" }
    property bool settling: false
    Timer { id: settle; interval: Math.max(1, Theme.popupCloseMs); onTriggered: sl.settling = false }
    readonly property bool lightBg: Theme.bg.hslLightness > 0.5
    // The lens needs a real GPU scene graph and the compiled shader. Software backend (QT_QUICK_BACKEND=software) or a
    // shader that failed to load (GlassLens.broken, set once by the effect): no lens, the handle itself grows to the lens
    // size with the same animation instead, so a slider is never broken or invisible.
    readonly property bool lensUsable: lens.usable
    readonly property bool lensOn: lensUsable && (down || grow > 0.004) && host !== null

    Rectangle {
        // Handle is always square (width == height). Radius = min(size / 2, Theme.radius): a square at
        // radius 0, rounder as the setting grows, a full circle once radius >= size / 2 (8 px).
        id: handle
        readonly property int size: 16
        width: size; height: size
        radius: Math.min(size / 2, Theme.radius)
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(1, sl.shown)) * (sl.width - width)
        // after a release the handle follows the pointer no longer but `value`, which a stepped / snapping caller
        // rounded (gap steps, speed 1x snap): glide onto it with the release motion instead of jumping
        Behavior on x { enabled: sl.settling; NumberAnimation { duration: Theme.popupCloseMs; easing.type: Theme.popupEaseClose } }
        color: Theme.fg
        opacity: sl.lensUsable ? 1 - Math.max(0, Math.min(1, sl.grow * 3)) : 1
        // fallback without the lens: the handle grows instead; a notch "click" at rest (keys, wheel) swells it a little
        scale: sl.lensUsable ? 1 + notch.pulse * sl.notchPulsePx / size : sl.lensSize / size
        visible: opacity > 0
        // keyboard focus (Tab): an accent ring around the handle
        Rectangle {
            visible: sl.activeFocus
            anchors { fill: parent; margins: -3 }
            radius: Math.min(width / 2, parent.radius + 3)
            color: Theme.alpha(Theme.accent, 0)
            border.width: 1.5
            border.color: Theme.accent
        }
    }

    // the card to capture: nearest glass card (popup card, Settings card), else the item right under the window root
    property Item host: null
    // lens geometry in host coordinates: 16 px (the handle) -> 28 px (1.75x), always square, centred on the handle
    readonly property real lensSize: Math.max(4, 16 + 12 * grow + notch.pulse * notchPulsePx)
    readonly property point lensC: {
        void [shown, grow, handle.x, width, height, x, y, host ? host.width + host.height : 0]
        return host ? sl.mapToItem(host, handle.x + 8, sl.height / 2) : Qt.point(0, 0)
    }
    // the lens itself (GlassLens: Settings > Glass values, in-app, so it works without the compositor's glass too)
    GlassLens {
        id: lens
        host: sl.lensOn ? sl.host : null
        center: sl.lensC
        size: sl.lensSize
        // handle corner radius -> fully round; corners: circular when the theme radius already makes the
        // handle a circle (R >= 8), else a squircle
        cornerRadius: Math.min(8, Theme.radius) * sl.lensSize / 16 + (sl.lensSize / 2 - Math.min(8, Theme.radius) * sl.lensSize / 16) * Math.max(0, Math.min(1, sl.grow))
        power: Theme.radius >= 8 ? 2 : 4
        amount: Math.max(0, Math.min(1, sl.grow * 3))
        shade: sl.lightBg ? 0.18 : 0.32
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        property real live: 0
        function set(x) { sl.emit(notch.snap(x, sl.valueAt(x))) }
        onPressed: mouse => { notch.free(); set(mouse.x) }
        onPositionChanged: mouse => { if (pressed) set(mouse.x) }
        onReleased: notch.free()
        onCanceled: notch.free()
        onDoubleClicked: {
            notch.free()
            if (sl.defaultNotch >= 0) { live = sl.defaultNotch; notch.click(); if (sl.resetToNotch) sl.moved(sl.defaultNotch) }
            sl.resetRequested()
        }
        onWheel: w => { if (!sl.wheel) { w.accepted = false; return } sl.emit(notch.stepFrom(sl.value, w.angleDelta.y > 0 ? 0.03 : -0.03)) }
    }
}
