import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

// One battery readout of the AirPods section: a ring meter around the part's icon (PodIcon), the percentage (bolt
// while charging) and the name below. `level` < 0 = not heard from (case closed / bud out of range): empty grey
// ring, "–", dimmed; the cell stays so the row does not jump. `inEar` tints the icon with the accent colour.
// `age` ("10m") marks a stale reading: grey arc and text, the age after the name.
ColumnLayout {
    id: br
    property string part: "left"           // PodIcon part
    property string name: ""
    property int level: -1
    property bool charging: false
    property bool inEar: false
    property string age: ""
    property int ring: 56                   // art size of the ring
    readonly property int stroke: 4
    readonly property int arcInset: 3

    readonly property bool known: level >= 0
    readonly property bool stale: known && age !== ""
    readonly property color tone: !known || stale ? Theme.muted : charging ? Theme.green : level <= 15 ? Theme.red : Theme.accent

    spacing: Theme.gapTight

    Item {
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: br.ring
        implicitHeight: br.ring
        opacity: br.known ? 1 : Theme.dimOpacity
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer     // analytic anti-aliasing: crisp at fractional scales
            ShapePath {
                strokeColor: Theme.itemActive; strokeWidth: br.stroke; fillColor: Theme.alpha(Theme.bg, 0)
                PathAngleArc { centerX: br.ring / 2; centerY: br.ring / 2; radiusX: br.ring / 2 - br.arcInset; radiusY: br.ring / 2 - br.arcInset; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: br.tone; strokeWidth: br.stroke; fillColor: Theme.alpha(Theme.bg, 0); capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: br.ring / 2; centerY: br.ring / 2; radiusX: br.ring / 2 - br.arcInset; radiusY: br.ring / 2 - br.arcInset; startAngle: -90; sweepAngle: br.known ? 3.6 * br.level : 0 }
            }
        }
        PodIcon {
            anchors.centerIn: parent
            part: br.part
            size: Math.round(br.ring * 0.42)
            color: br.inEar ? Theme.accent : Theme.fgDim
        }
    }
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Theme.gapTight
        opacity: br.known ? 1 : Theme.dimOpacity
        Label { text: br.known ? br.level + "%" : "–"; font.pixelSize: Theme.fontSize; color: br.stale ? Theme.fgDim : Theme.fg }
        Icon { visible: br.charging && !br.stale; text: Icons.bolt; font.pixelSize: Theme.iconSm; color: Theme.green }   // bolt
    }
    Label {
        Layout.alignment: Qt.AlignHCenter
        text: br.name + (br.stale ? " · " + br.age : "")
        font.pixelSize: Theme.fontCaption
        color: Theme.fgDim
    }
}
