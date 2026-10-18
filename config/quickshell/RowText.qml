import QtQuick
import QtQuick.Layouts

// Title + optional dim sub line for a list row (ListRow) or tile. Fills the free width; the title elides.
// Children (small badges such as "this device") go right after the title on its line.
ColumnLayout {
    id: rt
    property string title: ""
    property string sub: ""                        // "" = single line
    property color titleColor: Theme.fg
    default property alias badges: line.data

    Layout.fillWidth: true
    spacing: 0

    // title at its natural width with the badges right after it; when space is short it shrinks (down to 24 px)
    // and elides
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Label {
            text: rt.title
            color: rt.titleColor
            elide: Text.ElideRight
            Layout.preferredWidth: implicitWidth
            Layout.minimumWidth: 24
        }
        RowLayout { id: line; spacing: 6 }
        Item { Layout.fillWidth: true }
    }
    Label {
        visible: rt.sub !== ""
        Layout.fillWidth: true
        text: rt.sub
        color: Theme.fgDim
        font.pixelSize: Theme.fontCaption
        elide: Text.ElideRight
    }
}
