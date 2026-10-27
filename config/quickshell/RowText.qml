import QtQuick
import QtQuick.Layouts

// Title + optional dim sub line for a list row (ListRow) or tile. Fills the free width; the title elides.
// Children (small badges such as "this device") go right after the title on its line.
ColumnLayout {
    id: rt
    property string title: ""
    property string sub: ""                        // "" = single line
    property color titleColor: Theme.fg
    property bool titleBold: false
    default property alias badges: line.data

    Layout.fillWidth: true
    spacing: 0

    // title at its natural width with the badges right after it; when space is short it shrinks (down to 24 px)
    // and elides
    readonly property int titleMin: 24             // a title shrinks to this before the badges give way
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.controlGap
        // the title's natural width comes from metrics, not implicitWidth: once elided, implicitWidth feeds the
        // shortened layout back (short titles kept eliding); fillWidth + the same maximum lets a long title take the
        // free width and elide there instead of pushing the trailing items (state mark, value) out of the row
        TextMetrics { id: titleMetrics; font: titleLabel.font; text: rt.title }
        Label {
            id: titleLabel
            text: rt.title
            color: rt.titleColor
            font.bold: rt.titleBold
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.preferredWidth: Math.ceil(titleMetrics.advanceWidth) + 1
            Layout.maximumWidth: Math.ceil(titleMetrics.advanceWidth) + 1
            Layout.minimumWidth: rt.titleMin
        }
        RowLayout { id: line; spacing: Theme.controlGap }
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
