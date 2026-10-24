import QtQuick
import QtQuick.Shapes

// Hover highlight for clickable items in the popups (rows, quick-toggle tiles, pickers, buttons): a soft radial
// gradient centred on the pointer, following it with no lag, clipped to the item's rounded rect (it IS a rounded
// rect shape, so no layer / mask is needed). Fades in / out with the popup motion tokens. Costs nothing while not
// hovered (opacity 0 -> invisible -> not rendered).
//
// Usage, as the FIRST child of the item (or with z below the content):
//     HoverGlow { area: myMouseArea; radius: parent.radius }
// `area` (optional) only gates it: an item whose MouseArea is disabled gets no glow. The glow takes the colour of the item
// it sits on: by default the parent's current fill colour made opaque (a gray row glows gray, a red selected row /
// "on" tile / accent button glows red, a coloured item in its colour), so it follows state changes; a transparent
// fill falls back to Theme.fg. Size: a broad soft light, max(3 x height, 0.7 x width). Strength is compensated
// for brightness (peak alpha = 0.06 / sqrt(luminance), capped 0.04..0.12), so gray and red read about the same.
// The item keeps a light flat hover tint under it (2026-10-21 user feedback: larger, item-coloured, subtler).
Shape {
    id: glow

    property MouseArea area: null
    property real radius: 0
    // per-corner radii (segmented cells); -1 = `radius`
    property real topLeftRadius: -1
    property real topRightRadius: -1
    property real bottomLeftRadius: -1
    property real bottomRightRadius: -1
    // the item's fill (if it has one) made opaque; transparent / no fill -> the foreground colour
    // duck-typed on purpose (any parent with a `color`): qmllint only knows Item here
    // qmllint disable missing-property
    readonly property color fill: parent && parent.color !== undefined && parent.color.a > 0.01
        ? Qt.rgba(parent.color.r, parent.color.g, parent.color.b, 1) : Theme.fg
    // qmllint enable missing-property
    property color color: fill
    readonly property real lum: 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
    property real strength: Math.max(0.04, Math.min(0.12, 0.06 / Math.sqrt(Math.max(0.05, lum))))   // alpha at the centre
    property real reach: 3                           // gradient radius: reach x height ...
    property real widthReach: 0.7                    // ... or this x width, whichever is larger
    property var testPos: null                       // test hook: Qt.point -> shown there as if hovered

    // Pointer tracking: a passive HoverHandler on the ITEM (re-parented to our parent), not the item's MouseArea.
    // Hover reaches an item's ancestors even while a child control has it (Tailscale IP copy label, Wi-Fi reveal,
    // a Btn inside a row), so the glow keeps following over children; a MouseArea's containsMouse dropped there.
    // It takes no events and sets no cursor, so children keep their own cursor and clicks. `area` now only says
    // whether the item is enabled (area.enabled false = no glow); `hovered` is also what the item's flat hover
    // tint should use, so tint and glow agree.
    HoverHandler {
        id: hh
        parent: glow.parent
        enabled: glow.area === null || glow.area.enabled
    }
    readonly property bool hovered: hh.hovered
    readonly property bool on: testPos !== null || hovered
    // pointer in our coordinates (the handler's point is in the item's)
    readonly property point pos: testPos !== null ? testPos
        : glow.parent ? glow.mapFromItem(glow.parent, hh.point.position.x, hh.point.position.y) : Qt.point(width / 2, height / 2)
    // last position while on: the fade-out stays where the pointer left
    property point at: Qt.point(width / 2, height / 2)
    onPosChanged: if (on) at = pos
    onOnChanged: if (on) at = pos

    anchors.fill: parent
    z: -0.5                                          // above the item's own fill, below its content (and above a z: -1 MouseArea)
    opacity: on ? 1 : 0
    visible: opacity > 0
    // one duration both ways: a Behavior whose duration depends on `on` reads the old value when it starts
    Behavior on opacity { NumberAnimation { duration: Theme.popupFadeInMs; easing.type: Easing.OutCubic } }
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillGradient: RadialGradient {
            centerX: glow.at.x; centerY: glow.at.y
            focalX: glow.at.x; focalY: glow.at.y
            centerRadius: Math.max(8, glow.height * glow.reach, glow.width * glow.widthReach)
            focalRadius: 0
            GradientStop { position: 0; color: Theme.alpha(glow.color, glow.strength) }
            GradientStop { position: 0.5; color: Theme.alpha(glow.color, glow.strength * 0.4) }
            GradientStop { position: 1; color: Theme.alpha(glow.color, 0) }
        }
        PathRectangle {
            x: 0; y: 0
            width: glow.width; height: glow.height
            readonly property real cap: Math.min(glow.width / 2, glow.height / 2)
            radius: Math.min(glow.radius, cap)
            topLeftRadius: Math.min(glow.topLeftRadius >= 0 ? glow.topLeftRadius : glow.radius, cap)
            topRightRadius: Math.min(glow.topRightRadius >= 0 ? glow.topRightRadius : glow.radius, cap)
            bottomLeftRadius: Math.min(glow.bottomLeftRadius >= 0 ? glow.bottomLeftRadius : glow.radius, cap)
            bottomRightRadius: Math.min(glow.bottomRightRadius >= 0 ? glow.bottomRightRadius : glow.radius, cap)
        }
    }
}
