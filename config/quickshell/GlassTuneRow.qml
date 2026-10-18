import QtQuick
import QtQuick.Layouts

// One tunable value of GlassTune: label, editable number, reset button and a slider underneath.
// Never changes `value` itself; edited(v) carries the new value, the owner stores it.
ColumnLayout {
    id: row
    property string label: ""
    property real value: 0
    property real from: 0
    property real to: 1
    property real def: 0
    property int dec: 2
    property string unit: ""
    property real curve: 1                  // >1: more slider travel for the low end
    property color accentColor: Theme.accent
    signal edited(real v)

    readonly property bool atDefault: Math.abs(value - def) < Math.pow(10, -dec) / 2
    function toNorm(v) { return Math.pow(Math.max(0, Math.min(1, (v - from) / (to - from))), 1 / curve) }
    function fromNorm(n) { return from + (to - from) * Math.pow(n, curve) }

    Layout.fillWidth: true
    spacing: 2

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Label { text: row.label; color: Theme.fgDim; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; elide: Text.ElideRight }
        Rectangle {
            Layout.preferredWidth: 62; implicitHeight: 20
            radius: Math.min(5, Theme.radiusDeep)
            color: input.activeFocus ? Theme.alpha(Theme.fg, 0.16) : Theme.alpha(Theme.fg, 0.07)
            TextInput {
                id: input
                anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                horizontalAlignment: TextInput.AlignRight
                verticalAlignment: TextInput.AlignVCenter
                font.family: Theme.font; font.pixelSize: Theme.fontSmall
                color: Theme.fg
                selectByMouse: true
                clip: true
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                text: row.value.toFixed(row.dec) + row.unit
                onEditingFinished: {
                    const n = parseFloat(text)
                    if (!isNaN(n)) row.edited(Math.max(row.from, Math.min(row.to, n)))
                    text = Qt.binding(() => row.value.toFixed(row.dec) + row.unit)
                    focus = false
                }
            }
        }
        Btn {
            icon: true; text: ""          // rotate-left
            implicitHeight: 20; implicitWidth: 24
            outerRadius: Theme.radius; inset: 12
            enabledLook: !row.atDefault
            onClicked: row.edited(row.def)
        }
    }
    Slider {
        Layout.fillWidth: true
        implicitHeight: 18
        value: row.toNorm(row.value)
        onMoved: v => row.edited(row.fromNorm(v))
    }
}
