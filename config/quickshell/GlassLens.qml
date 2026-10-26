pragma ComponentBehavior: Bound
import QtQuick

// A small liquid-glass lens over a card (shaders/sliderlens.frag): the card the shell drew (`host`, an Item) is captured
// and drawn again in full, except inside the lens (1:1, `size` px, corner `cornerRadius`, `power` 2 = circle / 4 =
// squircle) centred on `center` (host coordinates), where it is REFRACTED with the Settings > Glass values
// (GlassTuneCtl.effective: refraction, bulb, depth, edge curve, aberration, light angle, specular, sheen, frost /
// clarity; magnification 1 + 0.35 x depth). Tint, darkening and saturation are not applied: the card's own compositor
// glass already applies them to the backdrop (see the shader). Works the same without the compositor's glass (stock
// Hyprland): it only refracts the shell's own pixels.
// Lifetime: nothing exists while `amount` is 0 (the Loader is inactive), so a lens costs nothing at rest; callers animate
// `amount` (0..1) only around an interaction. While it runs the host is hidden (hideSource) and the effect, a sibling
// of the host (parented to host.parent, z 1000), draws it, so the unrefracted content never shows through and the lens
// is not in its own capture. Two lenses on one host at the same time would draw the host twice: one at a time.
// `findHost(item)`: the card an item sits on = its nearest `isGlassItem` ancestor (popup card, Settings card, OSD), else
// the item right under the window's root (the bar frame).
// Users: Slider (handle while dragged), Toggle (knob while pressed / moving), Osd (level while it changes), Bar
// (workspace switch).
Item {
    id: gl
    // never drawn itself (and takes no slot in a Row): the effect lives under host.parent while it runs
    visible: false
    property Item host: null
    property point center: Qt.point(0, 0)
    property real size: 28
    property real cornerRadius: size / 2
    property real power: 2
    property real amount: 0
    property real shade: Theme.bg.hslLightness > 0.5 ? 0.18 : 0.32

    // software scene graph or a shader that failed to load: no lens (`usable` false); callers keep a flat fallback
    property bool broken: false
    readonly property bool usable: GraphicsInfo.api !== GraphicsInfo.Software && !broken
    readonly property bool running: usable && amount > 0.004 && host !== null
    readonly property var gv: GlassTuneCtl.effective

    function findHost(item) {
        let top = item
        for (let a = item ? item.parent : null; a; a = a.parent) {
            if (a.isGlassItem === true && a.parent)   // qmllint disable missing-property
                return a
            if (a.parent)
                top = a
        }
        return top !== item && top && top.parent ? top : null
    }

    Loader {
        active: gl.running
        parent: gl.host ? gl.host.parent : gl
        z: 1000
        sourceComponent: Component {
            ShaderEffect {
                id: fx
                onStatusChanged: if (status === ShaderEffect.Error) { console.warn("Glass lens shader failed, lens disabled:", log); gl.broken = true }
                // the card plus a margin, so the lens and its shadow may overhang the card edge
                readonly property real m: 24
                x: gl.host.x - m; y: gl.host.y - m
                width: gl.host.width + 2 * m; height: gl.host.height + 2 * m
                opacity: gl.host.opacity
                // in the visual tree (a zero-size child), not a parentless property value: a parentless source keeps a
                // stale window when its window is hidden mid-animation (segfault in QQuickWindowPrivate::dirtyItem)
                ShaderEffectSource {
                    id: src
                    width: 0; height: 0
                    sourceItem: gl.host
                    sourceRect: Qt.rect(-fx.m, -fx.m, gl.host.width + 2 * fx.m, gl.host.height + 2 * fx.m)
                    // a shader that failed to load: the card stays drawn (and the lens is dropped, broken)
                    hideSource: fx.status !== ShaderEffect.Error
                    live: true
                    smooth: true
                }
                property var source: src
                property size itemSize: Qt.size(width, height)
                property point lensCenter: Qt.point(gl.center.x + m, gl.center.y + m)
                property real lensHalf: gl.size / 2
                property real radius: Math.min(gl.cornerRadius, gl.size / 2)
                property real power: gl.power
                property real amount: Math.max(0, Math.min(1, gl.amount))
                property real refraction: gl.gv.refraction
                property real bulb: gl.gv.bulb
                property real depth: gl.gv.depth
                property real edgeCurve: gl.gv.edge_curve
                property real aberration: gl.gv.aberration
                property point lightDir: Qt.point(Math.cos(gl.gv.light_angle * Math.PI / 180), -Math.sin(gl.gv.light_angle * Math.PI / 180))
                property real specular: gl.gv.specular_intensity
                property real specPower: gl.gv.specular_power
                property real sheen: gl.gv.sheen
                property real frost: gl.gv.frost + (1 - gl.gv.clarity) * 3   // clarity < 1 mixes in the big blur there
                property real mag: 1 + 0.35 * gl.gv.depth
                property real shade: gl.shade
                fragmentShader: Qt.resolvedUrl("shaders/sliderlens.frag.qsb")
            }
        }
    }
}
