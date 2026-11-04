import QtQuick
import QtQuick.Layouts

// One choice of the language picker (LanguagePicker): the language's English name and its code; clicking it emits
// `picked`. `highlighted` marks the one Enter would pick.
Rectangle {
    id: opt
    property string code: ""
    property string name: ""
    property bool highlighted: false
    signal picked()

    Layout.fillWidth: true
    implicitHeight: 26
    radius: Math.min(Theme.radiusDeep, Math.floor(height / 3))
    color: area.containsMouse || opt.highlighted ? Theme.itemHover : Theme.itemFill

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.gapRow; anchors.rightMargin: Theme.gapRow
        spacing: Theme.gapRow
        Label { text: opt.name; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; elide: Text.ElideRight }
        Label { text: opt.code; color: Theme.muted; font.pixelSize: Theme.fontCaption }
    }
    MouseArea {
        id: area
        objectName: "lang-option-" + opt.code
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: opt.picked()
    }
}
