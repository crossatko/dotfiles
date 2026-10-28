import QtQuick
import QtQuick.Layouts

// A glyph + a short value of a media source (viewers, stream time, category): caption size, `fgDim`, no box. Hidden
// without a value; elides when it is given less than its text (a width, or Layout.fillWidth). MediaStats, MediaPanel.
RowLayout {
    id: mb
    property string icon: ""
    property string text: ""
    property color color: Theme.fgDim
    visible: text !== ""
    Layout.fillWidth: false                // as wide as its text unless the user lets it fill (then it elides)
    spacing: Theme.gapTight
    Icon { text: mb.icon; font.pixelSize: Theme.iconSm; color: mb.color }
    Label { Layout.fillWidth: true; text: mb.text; color: mb.color; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight }
}
