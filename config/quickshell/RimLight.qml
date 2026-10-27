import QtQuick
import QtQuick.Shapes

// Pointer rim light of a big card (popup card, launcher / modal card, Settings): while the pointer is over the card,
// the 1 px rim near it catches a soft light that follows the pointer, as if the pane's edge picked up a highlight from
// it. Fades in / out with Motion.hoverMs. Strength = Settings > Glass "Pointer rim" (shell-only key `pointer_rim`,
// GlassTuneCtl; 0 = off), on glass and on stock (there on top of GlassEdge's flat rim).
// Cost: nothing while the pointer is elsewhere (invisible); while it moves over the card only the gradient's centre
// changes on one curve-rendered ring shape (no layers, no effect passes).
// Place it inside the card, after its content:   RimLight { anchors.fill: parent; radius: parent.radius }
Item {
    id: rl
    property real radius: 0
    property real reach: 140                       // gradient radius, px
    readonly property real strength: Math.max(0, Math.min(1, GlassTuneCtl.effective.pointer_rim ?? 0.5))
    readonly property bool lightBg: Theme.bg.hslLightness > 0.5

    // passive: takes no events, sets no cursor (re-parented onto the card, so hover holds over child controls)
    HoverHandler { id: hh; parent: rl.parent }
    readonly property bool on: hh.hovered && rl.strength > 0
    readonly property point pos: rl.parent ? rl.mapFromItem(rl.parent, hh.point.position.x, hh.point.position.y) : Qt.point(0, 0)
    property point at: Qt.point(width / 2, 0)
    onPosChanged: if (on) at = pos
    onOnChanged: if (on) at = pos

    opacity: on ? 1 : 0
    visible: opacity > 0 && width > 2 && height > 2
    Behavior on opacity { NumberAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }

    // the rim itself: a 1 px ring (outer rounded rect minus the inner one, odd-even fill) filled with a radial light
    // centred on the pointer; no layers / masks, one curve-rendered shape
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillRule: ShapePath.OddEvenFill
            fillGradient: RadialGradient {
                centerX: rl.at.x; centerY: rl.at.y
                focalX: rl.at.x; focalY: rl.at.y
                centerRadius: rl.reach
                focalRadius: 0
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, (rl.lightBg ? 0.95 : 0.7) * rl.strength) }
                GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, (rl.lightBg ? 0.35 : 0.22) * rl.strength) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
            }
            PathRectangle { x: 0; y: 0; width: rl.width; height: rl.height; radius: Math.min(rl.radius, rl.width / 2, rl.height / 2) }
            PathRectangle { x: 1; y: 1; width: rl.width - 2; height: rl.height - 2; radius: Math.max(0, Math.min(rl.radius - 1, rl.width / 2 - 1, rl.height / 2 - 1)) }
        }
    }
}
