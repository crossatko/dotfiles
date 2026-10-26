import QtQuick

// A glyph run drawn white on transparent, padded on all sides: the shape input of GlassText / GlassTextFlat (used as
// a layer texture / effect mask, never shown itself).
Item {
    id: m
    property string text: ""
    property int pixelSize: 120
    property int weight: Font.Bold
    property real letterSpacing: 0
    property int superSample: 1     // layer resolution factor (GlassShape.ss)
    property int pad: 32
    property real dx: 0          // shift of the glyphs (px), for edge masks
    property real dy: 0
    readonly property alias glyph: t
    implicitWidth: t.implicitWidth + 2 * pad
    implicitHeight: t.implicitHeight + 2 * pad
    width: implicitWidth
    height: implicitHeight
    layer.enabled: true
    layer.smooth: true
    layer.mipmap: true          // glassfield.frag reads it at the mip level of its sample spacing
    layer.textureSize: Qt.size(Math.ceil(width * superSample), Math.ceil(height * superSample))
    visible: false
    Text {
        id: t
        x: m.pad + m.dx
        y: m.pad + m.dy
        text: m.text
        color: "white"
        font.family: Theme.font
        font.pixelSize: m.pixelSize
        font.weight: m.weight
        font.letterSpacing: m.letterSpacing
    }
}
