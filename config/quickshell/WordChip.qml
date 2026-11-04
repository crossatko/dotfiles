import QtQuick
import QtQuick.Layouts

// One removable word of a word list (WordListEditor): the word and an x button (`removed`). Reusable for any short list.
Rectangle {
    id: chip
    property string text: ""
    signal removed()

    implicitHeight: 24
    implicitWidth: row.implicitWidth + 2 * Theme.gapRow
    radius: Math.min(Theme.radiusDeep, Math.floor(height / 3))
    color: Theme.itemFill
    border.width: 1
    border.color: Theme.alpha(Theme.overlay, 0.5)

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Theme.gapTight
        Label { text: chip.text; font.pixelSize: Theme.fontSmall }
        Item {
            Layout.preferredWidth: 16; Layout.preferredHeight: 16
            Icon { anchors.centerIn: parent; text: Icons.xmark; font.pixelSize: Theme.iconSm; color: xArea.containsMouse ? Theme.red : Theme.muted }
            MouseArea { id: xArea; objectName: "chip-x-" + chip.text; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.removed() }
        }
    }
}
