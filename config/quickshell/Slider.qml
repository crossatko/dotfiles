import QtQuick

// Horizontal slider, 0..1. `value` is the real state; dragging emits moved(v) and never sets `value`
// itself, so it always shows the truth.
Item {
    id: sl
    property real value: 0
    property bool dim: false
    property real floor: 0              // lowest value a drag / wheel can emit (brightness keeps screens from going black)
    property real mark: -1              // optional tick on the track at this position (0..1), e.g. the 1x of a speed slider
    property bool wheel: true           // false = the wheel passes through (sliders on scrolling pages: scrolling must not change them)
    signal moved(real v)

    implicitHeight: 24
    opacity: dim ? 0.5 : 1

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
    Rectangle {
        visible: sl.mark >= 0 && sl.mark <= 1
        width: 2; height: 12
        radius: 1
        anchors.verticalCenter: parent.verticalCenter
        x: Math.round(Math.max(0, Math.min(1, sl.mark)) * (sl.width - 16) + 8 - width / 2)   // at the handle centre for that value
        color: Theme.alpha(Theme.fg, 0.45)
    }

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
            host = findHost()
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
    // shader that failed to load (`lensBroken`, set once by the effect): no lens, the handle itself grows to the lens
    // size with the same animation instead, so a slider is never broken or invisible.
    property bool lensBroken: false
    readonly property bool lensUsable: GraphicsInfo.api !== GraphicsInfo.Software && !lensBroken
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
        scale: sl.lensUsable ? 1 : sl.lensSize / size      // fallback without the lens: the handle grows instead
        visible: opacity > 0
    }

    // the card to capture: nearest glass card (popup card, Settings card), else the item right under the window root
    property Item host: null
    function findHost() {
        let top = sl
        for (let a = sl.parent; a; a = a.parent) {
            if (a.isGlassItem === true && a.parent)
                return a
            if (a.parent)
                top = a
        }
        return top !== sl && top.parent ? top : null
    }
    // lens geometry in host coordinates: 16 px (the handle) -> 28 px (1.75x), always square, centred on the handle
    readonly property real lensSize: Math.max(4, 16 + 12 * grow)
    readonly property point lensC: {
        void [shown, grow, handle.x, width, height, x, y, host ? host.width + host.height : 0]
        return host ? sl.mapToItem(host, handle.x + 8, sl.height / 2) : Qt.point(0, 0)
    }
    // Settings > Glass: the live solid_glass values when the compositor has them (Theme.glass and GlassTuneCtl read
    // them back); otherwise (stock Hyprland, other blur variant, not read yet) the page's built-in defaults. The lens is
    // in-app, so it works without the compositor's glass either way.
    readonly property var gv: Theme.glass && GlassTuneCtl.ready ? GlassTuneCtl.values : GlassTuneCtl.defaults()

    Loader {
        active: sl.lensOn
        parent: sl.host ? sl.host.parent : sl
        z: 1000
        sourceComponent: Component {
            ShaderEffect {
                id: fx
                onStatusChanged: if (status === ShaderEffect.Error) { console.warn("Slider lens shader failed, lens disabled:", log); sl.lensBroken = true }
                // the card plus a margin, so the lens and its shadow may overhang the card edge
                readonly property real m: 24
                x: sl.host.x - m; y: sl.host.y - m
                width: sl.host.width + 2 * m; height: sl.host.height + 2 * m
                opacity: sl.host.opacity
                // in the visual tree (a zero-size child), not a parentless property value: a parentless source keeps a
                // stale window when its window is hidden mid-animation (segfault in QQuickWindowPrivate::dirtyItem)
                ShaderEffectSource {
                    id: src
                    width: 0; height: 0
                    sourceItem: sl.host
                    sourceRect: Qt.rect(-24, -24, sl.host.width + 48, sl.host.height + 48)
                    // a shader that failed to load: the card stays drawn (and the lens is dropped, lensBroken)
                    hideSource: fx.status !== ShaderEffect.Error
                    live: true
                    smooth: true
                }
                property var source: src
                property size itemSize: Qt.size(width, height)
                property point lensCenter: Qt.point(sl.lensC.x + m, sl.lensC.y + m)
                property real lensHalf: sl.lensSize / 2
                // handle corner radius -> fully round; corners: circular when the theme radius already makes the
                // handle a circle (R >= 8), else a squircle
                property real radius: Math.min(8, Theme.radius) * sl.lensSize / 16 + (sl.lensSize / 2 - Math.min(8, Theme.radius) * sl.lensSize / 16) * Math.max(0, Math.min(1, sl.grow))
                property real power: Theme.radius >= 8 ? 2 : 4
                property real amount: Math.max(0, Math.min(1, sl.grow * 3))
                property real refraction: sl.gv.refraction
                property real bulb: sl.gv.bulb
                property real depth: sl.gv.depth
                property real edgeCurve: sl.gv.edge_curve
                property real aberration: sl.gv.aberration
                property point lightDir: Qt.point(Math.cos(sl.gv.light_angle * Math.PI / 180), -Math.sin(sl.gv.light_angle * Math.PI / 180))
                property real specular: sl.gv.specular_intensity
                property real specPower: sl.gv.specular_power
                property real sheen: sl.gv.sheen
                property real frost: sl.gv.frost + (1 - sl.gv.clarity) * 3   // clarity < 1 mixes in the big blur there
                property real mag: 1 + 0.35 * sl.gv.depth
                // tint, darkening, saturation: not used (the card's compositor glass already applies them, see the shader)
                property real shade: sl.lightBg ? 0.18 : 0.32
                fragmentShader: Qt.resolvedUrl("shaders/sliderlens.frag.qsb")
            }
        }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        property real live: 0
        function set(x) { live = sl.valueAt(x); sl.moved(live) }
        onPressed: mouse => set(mouse.x)
        onPositionChanged: mouse => { if (pressed) set(mouse.x) }
        onWheel: w => { if (!sl.wheel) { w.accepted = false; return } live = Math.max(sl.floor, Math.min(1, sl.value + (w.angleDelta.y > 0 ? 0.03 : -0.03))); sl.moved(live) }
    }
}
