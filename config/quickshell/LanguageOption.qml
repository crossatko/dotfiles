import QtQuick
import QtQuick.Layouts

// One choice of the language picker (LanguagePicker): the language's English name and its code; clicking it emits
// `picked`. `highlighted` marks the one Enter would pick; `added` (already in the selection) dims it, marks it and
// makes it unclickable.
Rectangle {
    id: opt
    property string code: ""
    property string name: ""
    property bool highlighted: false
    property bool added: false
    signal picked()

    Layout.fillWidth: true
    implicitHeight: 26
    radius: Math.min(Theme.radiusDeep, Math.floor(height / 3))
    color: !opt.added && (area.containsMouse || opt.highlighted) ? Theme.itemHover : Theme.itemFill
    opacity: opt.added ? 0.55 : 1

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.gapRow; anchors.rightMargin: Theme.gapRow
        spacing: Theme.gapRow
        Label { text: opt.name; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; elide: Text.ElideRight }
        Icon { visible: opt.added; text: Icons.check; font.pixelSize: Theme.iconSm; color: Theme.muted }
        Label { text: opt.added ? "added" : opt.code; color: Theme.muted; font.pixelSize: Theme.fontCaption }
    }
    MouseArea {
        id: area
        objectName: "lang-option-" + opt.code
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: opt.added ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: if (!opt.added) opt.picked()
    }
}
