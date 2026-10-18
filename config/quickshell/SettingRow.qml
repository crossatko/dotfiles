import QtQuick
import QtQuick.Layouts

// One line of a Settings page: a fixed-width dim title column, then the children you add (Slider, Toggle,
// Segmented, value / hint Labels). All rows of a page share `titleWidth`, so the controls line up; an empty
// title keeps the column as an indent (a Toggle under a slider row).
RowLayout {
    id: sr
    property string title: ""
    property real titleWidth: 120

    Layout.fillWidth: true
    spacing: 10

    Label { text: sr.title; Layout.preferredWidth: sr.titleWidth; color: Theme.fgDim; font.pixelSize: Theme.fontSmall; elide: Text.ElideRight }
}
