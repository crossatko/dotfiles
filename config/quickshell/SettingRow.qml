import QtQuick
import QtQuick.Layouts

// One line of a Settings page: a fixed-width dim title column, then the children you add (Slider, Toggle,
// Segmented, value / hint Labels). All rows of a page share `titleWidth`, so the controls line up; an empty
// title keeps the column as an indent (a Toggle under a slider row).
RowLayout {
    id: sr
    property string title: ""
    property real titleWidth: 120
    property real titleTopAt: -1          // >= 0: the title's centre this far below the top (content that wraps to more rows)

    Layout.fillWidth: true
    spacing: 10

    Label {
        text: sr.title; Layout.preferredWidth: sr.titleWidth; color: Theme.fgDim; font.pixelSize: Theme.fontSmall; elide: Text.ElideRight
        Layout.alignment: sr.titleTopAt >= 0 ? Qt.AlignTop : Qt.AlignVCenter
        Layout.topMargin: sr.titleTopAt >= 0 ? Math.max(0, Math.round(sr.titleTopAt - implicitHeight / 2)) : 0
    }
}
