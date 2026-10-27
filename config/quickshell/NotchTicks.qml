pragma ComponentBehavior: Bound
import QtQuick

// The tick marks of a NotchSnap, drawn into the parent (the track's item) at the handle centre of each notch:
// a short quiet line per notch, the default one taller and a little stronger. Used by Slider and HaStrip.
Repeater {
    id: nt
    property NotchSnap snap: null
    readonly property real tickW: 2
    property real defaultH: 12          // the default notch
    property real extraH: 8             // further notches (presets, full scale)
    property color color: Theme.fg
    property real centerY: -1           // vertical centre in the parent; -1 = the middle (on the track)
    readonly property real defaultAlpha: 0.5
    readonly property real extraAlpha: 0.3

    model: snap ? snap.list : []
    Rectangle {
        required property var modelData
        readonly property bool isDefault: modelData.kind === "default"
        width: nt.tickW
        height: isDefault ? nt.defaultH : nt.extraH
        radius: width / 2
        x: Math.round(nt.snap.pxOf(modelData.v) - width / 2)
        y: Math.round((nt.centerY >= 0 ? nt.centerY * 2 : (nt.parent ? nt.parent.height : 0)) / 2 - height / 2)
        color: Theme.alpha(nt.color, isDefault ? nt.defaultAlpha : nt.extraAlpha)
    }
}
