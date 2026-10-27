import QtQuick
import QtQuick.Window

// The glass optics of GlassText / GlassBead (shaders/glassfield.frag + glasstext.frag): any white-on-transparent `mask`
// (a layer-enabled item of this item's size, with `pad` px of empty margin all round) becomes clear glass tubes of
// radius `strokeHalf` that refract the backdrop behind them, with highlights along the strokes, fresnel reflection,
// inner glow, shadow and caustic. `backdrop` = the blurred background (texture provider), `sharpBackdrop` = the same
// unblurred (`sharpInset` px larger on every side), `origin` = this item's top-left in them. Values: Settings > Glass
// (GlassTuneCtl.effective, as Slider.qml), nothing lock-specific; `glow` (alpha = strength) fills the glass with a
// colour (state feedback, e.g. an error). Cost: the field renders once per mask change; the optics pass is cheap and
// redraws with the backdrop. `refracting` is false (the caller shows its flat fallback) without Theme.shellGlass / a backdrop / the shaders
// (shell-drawn: works on stock Hyprland too).
Item {
    id: g
    property Item mask: null
    property Item mask2: null             // morph partner (GlassText's other mask); null = no morph
    property real morph: 0                // 0 = the shown shape, 1 = the other one: the glass flows between the two
    // which mask is shown (false: mask, true: mask2). Each mask keeps its own field layer for good: a morph only swaps
    // which field the optics read, so nothing but the field of the mask that got new content renders again
    property bool flip: false
    property int pad: 0
    property real strokeHalf: 10
    property Item backdrop: null
    property Item sharpBackdrop: null
    property real sharpInset: 0           // px the sharp backdrop extends past the blurred one on every side
    property point origin: Qt.point(0, 0)
    property size backdropSize: Qt.size(1, 1)
    property real shade: 0.45
    property color glow: "transparent"
    property real dim: 0                  // darkening of the sharp scene, to match a dimmed blurred backdrop
    property real strength: 1             // the glass forming: 0 = flat and clear, 1 = full; > 1 briefly over-inflates
    property real airy: 0                 // 0 = the Settings > Glass look, 1 = light clear glass for a bright backdrop (glasstext.frag)
    // bumped by GlassText when a mask's text changed: that mask's shape field renders again (`refresh` = mask's,
    // `refresh2` = mask2's; the masks are layers of invisible items, and a content change of the same mask texture did
    // not always reach the field's own layer, so a morph could run between two stale, identical fields and the new digit
    // only appeared at its end, see GlassText)
    property int refresh: 0
    property int refresh2: 0
    readonly property var gv: GlassTuneCtl.effective
    readonly property bool refracting: mask !== null && backdrop !== null && Theme.shellGlass && fx.status !== ShaderEffect.Error && fieldFx.status !== ShaderEffect.Error && fieldFx2.status !== ShaderEffect.Error
    // the mask (GlassMask / the bead disc) renders at 2x, mipmapped, on a scale-1 output (per screen; 1x on scaled
    // outputs, which have the pixels already): the field's blurs read it smooth
    readonly property int ss: Screen.devicePixelRatio > 1 ? 1 : 2
    readonly property real softRadius: Math.max(4, Math.min(48, strokeHalf * 1.1))
    visible: refracting

    // coverage, smooth height and shadow blur in one float layer, rendered once per mask (glassfield.frag)
    ShaderEffect {
        id: fieldFx
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true
        layer.format: ShaderEffectSource.RGBA16F      // 8 bit stepped the normals (banding)
        blending: false                               // alpha is data (glassfield.frag)
        fragmentShader: Qt.resolvedUrl("shaders/glassfield.frag.qsb")
        property var mask: g.mask
        property size itemSize: Qt.size(width, height)
        property real radius: g.strokeHalf
        property real level: 0.5 + 1e-6 * (g.refresh % 2)   // a no-op change: re-renders the field
        property real maskScale: g.ss
    }

    ShaderEffect {
        id: fieldFx2
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true
        layer.format: ShaderEffectSource.RGBA16F      // 8 bit stepped the normals (banding)
        blending: false                               // alpha is data (glassfield.frag)
        fragmentShader: Qt.resolvedUrl("shaders/glassfield.frag.qsb")
        property var mask: g.mask2 ?? g.mask
        property size itemSize: Qt.size(width, height)
        property real radius: g.strokeHalf
        property real level: 0.5 + 1e-6 * (g.refresh2 % 2)   // a no-op change: re-renders the field
        property real maskScale: g.ss
    }

    ShaderEffect {
        id: fx
        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("shaders/glasstext.frag.qsb")
        property var backdrop: g.backdrop
        property var sharp: g.sharpBackdrop ?? g.backdrop
        property var field: g.mask2 && g.flip ? fieldFx2 : fieldFx
        property var field2: !g.mask2 ? fieldFx : g.flip ? fieldFx : fieldFx2
        property real morph: g.mask2 ? g.morph : 0
        property size itemSize: Qt.size(width, height)
        property point origin: g.origin
        property size backdropSize: g.backdropSize
        property real radius: g.strokeHalf
        // a slight swell mid-morph, the glass passing through a rounder shape
        property real heightScale: g.strokeHalf * 3.0 * Math.max(g.strength, 0.001) * (1 + 0.15 * Math.sin(Math.PI * morph))
        // the compositor's bend is in px for window-sized glass: scaled to the tube (24 px = 1x), capped at two radii
        property real refraction: Math.min(g.gv.refraction * Math.max(g.gv.depth, 0.25) * g.strokeHalf / 24, g.strokeHalf * 2) * g.strength
        property real edgeCurve: g.gv.edge_curve
        property real aberration: g.gv.aberration
        property point lightDir: Qt.point(Math.cos(g.gv.light_angle * Math.PI / 180), -Math.sin(g.gv.light_angle * Math.PI / 180))
        property real specular: g.gv.specular_intensity
        property real specPower: g.gv.specular_power
        property real sheen: g.gv.sheen
        property real saturation: g.gv.saturation
        property real darkening: g.gv.darkening
        property color tint: GlassTuneCtl.effectiveTint
        property color glow: g.glow
        property real dim: g.sharpBackdrop ? g.dim : 0
        property real shade: g.shade * g.strength
        property real sharpInset: g.sharpBackdrop ? g.sharpInset : 0
        property real airy: g.airy
    }
}
