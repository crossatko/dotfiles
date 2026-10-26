import QtQuick

// A round glass bead (a sphere: GlassShape over a disc) of diameter `size`, over `backdrop` / `sharpBackdrop`; `origin`
// = this item's top-left in them. The lock screen's password dots (LockDots). Flat fallback: a Theme.fg disc.
Item {
    id: b
    property int size: 20
    property alias backdrop: shape.backdrop
    property alias sharpBackdrop: shape.sharpBackdrop
    property alias sharpInset: shape.sharpInset
    property alias dim: shape.dim
    property point origin: Qt.point(0, 0)
    property alias backdropSize: shape.backdropSize
    property alias glow: shape.glow
    property color flatColor: Theme.fg
    readonly property int pad: Math.ceil(size * 0.9)
    implicitWidth: size
    implicitHeight: size

    Item {
        id: disc
        x: -b.pad; y: -b.pad
        width: b.size + 2 * b.pad; height: width
        visible: false
        layer.enabled: true
        layer.smooth: true
        layer.mipmap: true
        layer.textureSize: Qt.size(width * shape.ss, height * shape.ss)
        Rectangle { x: b.pad; y: b.pad; width: b.size; height: b.size; radius: b.size / 2; color: "white" }
    }
    GlassShape {
        id: shape
        x: -b.pad; y: -b.pad
        width: disc.width; height: disc.height
        mask: disc
        pad: b.pad
        strokeHalf: b.size / 2
        shade: 0.35
        origin: Qt.point(b.origin.x - b.pad, b.origin.y - b.pad)
    }
    Rectangle {
        visible: !shape.refracting
        anchors.fill: parent
        radius: width / 2
        color: b.flatColor
    }
}
