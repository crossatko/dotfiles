import QtQuick
import QtQuick.Effects

// The rim of a card when the compositor draws no glass (Theme.glass false: stock Hyprland, another blur variant): a
// 1 px line along the card's rounded outline, lit on the side facing the light and faint on the far side, so a flat
// card still reads as a lit pane instead of glass taken away. Light direction = Settings > Glass "Light angle", strength
// = "Flat card edge" (GlassTuneCtl.effective: light_angle, edge; 0 = off). No shader of its own: a rotated gradient
// masked to the outline (MultiEffect), rendered again only when the size, radius or those values change.
// Place it inside the card: `GlassEdge { anchors.fill: parent; radius: parent.radius }`. With the compositor's glass
// it is not drawn (the compositor's rim is the edge then).
Item {
    id: e
    property real radius: 0
    readonly property var gv: GlassTuneCtl.effective
    readonly property real strength: Math.max(0, Math.min(1, gv.edge ?? 0))
    readonly property real angle: gv.light_angle ?? 135
    readonly property bool lightBg: Theme.bg.hslLightness > 0.5
    visible: !Theme.glass && strength > 0 && width > 2 && height > 2

    // vertical gradient whose top end points at the light: lit (white) -> nothing -> a faint counter light
    Item {
        id: grad
        anchors.fill: parent
        visible: false
        layer.enabled: e.visible
        clip: true
        Rectangle {
            readonly property real d: Math.ceil(Math.sqrt(e.width * e.width + e.height * e.height))
            width: d; height: d
            anchors.centerIn: parent
            rotation: 90 - e.angle            // the gradient's top = straight up (90°) turned onto light_angle
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, (e.lightBg ? 0.9 : 0.6) * e.strength) }
                GradientStop { position: 0.4; color: Qt.rgba(1, 1, 1, 0) }
                GradientStop { position: 0.6; color: Qt.rgba(1, 1, 1, 0) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, (e.lightBg ? 0.35 : 0.2) * e.strength) }
            }
        }
    }
    // the outline the gradient shows through: 1 px inside the card edge, the card's own radius
    Rectangle {
        id: ring
        anchors.fill: parent
        radius: e.radius
        color: "transparent"
        border.width: 1
        border.color: "white"
        visible: false
        layer.enabled: e.visible
    }
    MultiEffect {
        anchors.fill: parent
        visible: e.visible
        source: grad
        maskEnabled: true
        maskSource: ring
    }
}
