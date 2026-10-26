import QtQuick
import QtQuick.Effects

// Cheap glass lettering, no custom shader (the fallback of GlassText): a faint translucent white gradient inside the
// glyphs, a bright 1-2 px highlight along their top edge, a darker one along the bottom edge and a soft drop shadow.
// Edges = glyph minus the glyph shifted by `edge` px (inverted mask). Use only at big, thick sizes.
Item {
    id: f
    property string text: ""
    property int pixelSize: 120
    property int weight: Font.Bold
    property real edge: Math.max(1.2, pixelSize / 90)
    property real letterSpacing: 0
    property int pad: 32
    implicitWidth: base.width
    implicitHeight: base.height
    width: implicitWidth
    height: implicitHeight

    GlassMask { id: base; text: f.text; pixelSize: f.pixelSize; weight: f.weight; letterSpacing: f.letterSpacing; pad: f.pad }
    GlassMask { id: down; text: f.text; pixelSize: f.pixelSize; weight: f.weight; letterSpacing: f.letterSpacing; pad: f.pad; dy: f.edge }
    GlassMask { id: up; text: f.text; pixelSize: f.pixelSize; weight: f.weight; letterSpacing: f.letterSpacing; pad: f.pad; dy: -f.edge }

    // drop shadow: blurred black glyph, shifted down, cut out where the glyph itself is
    Item {
        id: shadowSrc
        width: base.width; height: base.height
        layer.enabled: true
        visible: false
        MultiEffect {
            anchors.fill: parent
            anchors.topMargin: f.pixelSize * 0.04
            source: base
            colorization: 1
            colorizationColor: "black"
            blurEnabled: true
            blur: 0.45
            blurMax: 32
            opacity: 0.45
        }
    }
    MultiEffect { anchors.fill: parent; source: shadowSrc; maskEnabled: true; maskSource: base; maskInverted: true }

    // body: translucent white gradient through the glyph shape
    Rectangle {
        id: bodyFill
        width: base.width; height: base.height
        layer.enabled: true
        visible: false
        gradient: Gradient {
            GradientStop { position: 0.2; color: Qt.rgba(1, 1, 1, 0.34) }
            GradientStop { position: 0.8; color: Qt.rgba(1, 1, 1, 0.12) }
        }
    }
    MultiEffect { anchors.fill: parent; source: bodyFill; maskEnabled: true; maskSource: base }

    // top edge light and bottom edge shade (inside the glyph)
    MultiEffect { anchors.fill: parent; source: base; maskEnabled: true; maskSource: down; maskInverted: true; opacity: 0.9 }
    MultiEffect { anchors.fill: parent; source: base; colorization: 1; colorizationColor: "black"; maskEnabled: true; maskSource: up; maskInverted: true; opacity: 0.35 }
}
