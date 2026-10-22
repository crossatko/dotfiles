import QtQuick

// Round notches cut out of a card (the link buttons between the monitor cards, MonitorCardRow), as the card's
// `layer.effect` (shaders/notchmask.frag): the card is drawn as usual into its layer and the shader cuts the notches
// with an antialiased edge and draws the card's border along each cut. The cards are flat fills on the Settings glass
// card (not glass surfaces themselves), so the compositor glass region is not involved. Usage on a card Rectangle:
//     property var notches: []                       // MonitorCardRow.notchesOf(index)
//     layer.enabled: notches.length > 0
//     layer.effect: NotchMask { notches: card.notches; radius: card.radius; borderWidth: card.border.width; borderColor: card.border.color }
ShaderEffect {
    id: fx
    property var notches: []               // [Qt.vector3d(x, y, radius)] in the card's coordinates, up to 4
    property real radius: 0
    property real borderWidth: 1
    property color borderColor: "transparent"

    function at(i) { const n = notches[i]; return n ? Qt.vector4d(n.x, n.y, n.z, 0) : Qt.vector4d(0, 0, 0, 0) }
    property size itemSize: Qt.size(width, height)
    property vector4d borderRgba: Qt.vector4d(borderColor.r, borderColor.g, borderColor.b, borderColor.a)
    property vector4d n0: at(0)
    property vector4d n1: at(1)
    property vector4d n2: at(2)
    property vector4d n3: at(3)
    onStatusChanged: if (status === ShaderEffect.Error) console.warn("NotchMask shader failed:", log)
    fragmentShader: Qt.resolvedUrl("shaders/notchmask.frag.qsb")
}
