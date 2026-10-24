import QtQuick
import QtQuick.Layouts

// Header strip of the notification center: a glass pill (the center itself has no background, so the title needs its
// own surface to stay readable on any wallpaper): title, count (with a scroll hint) and Clear.
Rectangle {
    id: head
    property bool overflow: false      // more cards than fit: the list scrolls
    property real popupScale: 1        // the popup's glass scale while it is in motion (NotifPanel)

    readonly property bool isGlassItem: true
    readonly property real glassScale: popupScale
    implicitHeight: 46
    radius: Theme.radius
    color: Theme.alpha(Theme.bg, Theme.cardFill)
    border.width: 1
    border.color: Theme.alpha(Theme.overlay, 0.5)

    RowLayout {
        anchors { fill: parent; leftMargin: 16; rightMargin: 8 }
        spacing: 8
        Label { text: "Notifications"; font.pixelSize: 15; font.bold: true; Layout.fillWidth: true }
        Label {
            visible: Notifs.count > 0
            text: head.overflow ? Notifs.count + "  ·  scroll for more" : Notifs.count
            color: Theme.fgDim
            font.pixelSize: Theme.fontSmall
        }
        Btn { text: "Clear"; enabledLook: Notifs.count > 0; onClicked: Notifs.clearAll() }
    }
}
