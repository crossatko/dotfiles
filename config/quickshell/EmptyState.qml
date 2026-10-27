import QtQuick
import QtQuick.Layouts

// What a popup shows when there is nothing to list (no player, no events, no devices, adapter off): one quiet inline
// row, left-aligned with the section's content and no taller than a compact row: a small muted glyph and two to four
// words ("Wi-Fi is off", "No events", "Nothing playing"), never a sentence and never a large centred glyph.
// `hint` = an optional second, dimmer caption under it (a short reason or the way out, e.g. the error text); it wraps.
// `big` = the centred block (iconXl glyph over the text) for a whole empty page (Settings > Wallpaper only).
Item {
    id: empty
    property string icon: ""
    property string text: ""
    property string hint: ""
    property bool big: false

    Layout.fillWidth: true
    Layout.topMargin: big ? Theme.pad : 0
    Layout.bottomMargin: big ? Theme.pad : 0
    implicitHeight: big ? bigCol.implicitHeight : col.implicitHeight
    implicitWidth: big ? bigCol.implicitWidth : col.implicitWidth

    // ---- inline (the default) ----
    ColumnLayout {
        id: col
        visible: !empty.big
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: Theme.gapTight / 2
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.controlH      // one compact row, like a dropdown head or a button
            spacing: Theme.gapRow
            Icon {
                visible: empty.icon !== ""
                text: empty.icon
                font.pixelSize: Theme.iconSm
                color: Theme.muted
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: Theme.iconSm + 2
            }
            Label { Layout.fillWidth: true; text: empty.text; color: Theme.muted; font.pixelSize: Theme.fontSmall; elide: Text.ElideRight }
        }
        Label {
            visible: empty.hint !== ""
            Layout.fillWidth: true
            Layout.leftMargin: empty.icon !== "" ? Theme.iconSm + 2 + Theme.gapRow : 0   // under the text, not the glyph
            Layout.bottomMargin: Theme.gapTight
            wrapMode: Text.Wrap
            text: empty.hint
            color: Theme.muted
            font.pixelSize: Theme.fontCaption
        }
    }

    // ---- big: a centred block for an empty page ----
    // A plain Column, not a layout: a ColumnLayout whose children do not fill gets a maximum width = its widest child,
    // and the parent layout then ignores fillWidth beyond that (the glyph sat off-centre at the left).
    Column {
        id: bigCol
        visible: empty.big
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        spacing: Theme.controlGap
        Icon { visible: empty.icon !== ""; anchors.horizontalCenter: parent.horizontalCenter; text: empty.icon; font.pixelSize: Theme.iconXl; color: Theme.muted }
        Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: empty.text; color: Theme.fgDim; font.pixelSize: Theme.fontSmall }
        Label { visible: empty.hint !== ""; width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: empty.hint; color: Theme.muted; font.pixelSize: Theme.fontCaption }
    }
}
