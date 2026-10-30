import QtQuick
import QtQuick.Effects

// Icon of one AirPods part, centred in a `size` square box: "left" / "right" bud, "case" (drawings in assets/,
// credits in assets/CREDITS.md) or "headset" (AirPods Max: Vadivam headphones). The drawings are plain
// black-on-transparent SVGs tinted to `color` (MultiEffect: brightness lifts them to white, colorization then
// maps white to the colour) and rasterised at their displayed size (Image renders an SVG at sourceSize x the
// screen's device pixel ratio, so they stay crisp at fractional scales).
Item {
    id: pi
    property string part: "left"
    property color color: Theme.fg
    property int size: 26

    readonly property bool drawn: part === "left" || part === "right" || part === "case"
    // width / height of each drawing's viewBox (scripted crop of the source drawing, see assets/CREDITS.md)
    readonly property real aspect: part === "case" ? 17.0727 / 13.15 : 6.9 / 8.6
    // the case is a large solid block: drawn a bit smaller so it does not outweigh the buds
    readonly property real fit: part === "case" ? Math.round(size * 0.85) : size

    implicitWidth: size
    implicitHeight: size

    Image {
        id: img
        anchors.centerIn: parent
        visible: false                     // drawn through the tint below
        source: pi.drawn ? Qt.resolvedUrl("assets/airpods-pro-" + pi.part + ".svg") : ""
        width: pi.aspect >= 1 ? pi.fit : Math.round(pi.fit * pi.aspect)
        height: pi.aspect >= 1 ? Math.round(pi.fit / pi.aspect) : pi.fit
        sourceSize.width: width
        sourceSize.height: height
        smooth: true
    }
    MultiEffect {
        visible: pi.drawn
        anchors.fill: img
        source: img
        brightness: 1
        colorization: 1
        colorizationColor: pi.color
    }
    Icon {
        visible: !pi.drawn
        anchors.centerIn: parent
        text: Icons.headphones                     // headphones
        font.pixelSize: pi.size - 6
        color: pi.color
    }
}
