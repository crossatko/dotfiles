import QtQuick
import QtQuick.Layouts

// One labelled meter line of a VM card: label | bar | right-aligned value. The label and value columns have a fixed width
// (the widest realistic text), so every row of every card shares the same bar edges and the text never touches the bar.
RowLayout {
    id: r
    property string label: ""
    property real value: 0
    property string text: ""
    property color fillColor: Theme.accent

    spacing: Theme.controlGap

    TextMetrics { id: labelW; font.family: Theme.font; font.pixelSize: Theme.fontCaption; text: "RAM" }
    TextMetrics { id: valueW; font.family: Theme.font; font.pixelSize: Theme.fontCaption; text: "128.0 GB / 128.0 GB" }

    Label { text: r.label; color: Theme.fgDim; font.pixelSize: Theme.fontCaption; Layout.preferredWidth: Math.ceil(labelW.advanceWidth) }
    Meter { Layout.fillWidth: true; value: r.value; animMs: 300; implicitHeight: 4; fillColor: r.fillColor }
    Label {
        text: r.text
        font.pixelSize: Theme.fontCaption
        horizontalAlignment: Text.AlignRight
        Layout.preferredWidth: Math.ceil(valueW.advanceWidth)
    }
}
