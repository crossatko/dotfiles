import QtQuick

// Small text button used inside the popups.
Rectangle {
    id: btn
    property string text: ""
    property bool active: false
    property bool enabledLook: true
    property bool icon: false     // text is a Font Awesome glyph
    signal clicked(var mouse)

    implicitWidth: label.implicitWidth + 22
    implicitHeight: 30
    radius: Math.max(0, Theme.rounding - 4)
    opacity: enabledLook ? 1 : 0.5
    color: active ? Theme.alpha(Theme.accent, 0.3)
         : area.containsMouse ? Theme.alpha(Theme.fg, 0.14)
         : Theme.alpha(Theme.fg, 0.07)
    border.width: active ? 1 : 0
    border.color: Theme.alpha(Theme.accent, 0.8)
    Behavior on color { ColorAnimation { duration: 100 } }

    Label { id: label; anchors.centerIn: parent; text: btn.text; font.pixelSize: btn.icon ? 14 : 12; font.family: btn.icon ? Theme.iconFont : Theme.font; font.styleName: btn.icon ? "Regular" : "";  color: btn.active ? Theme.accent : Theme.fg }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => btn.clicked(mouse)
    }
}
