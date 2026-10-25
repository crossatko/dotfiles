import QtQuick

// The notification center's empty / do-not-disturb state: one glass strip in the look of the cards.
Rectangle {
    readonly property bool isGlassItem: true
    readonly property real glassScale: Theme.glassScaleAt(opacity)

    implicitHeight: 46
    radius: Theme.radius
    color: Theme.alpha(Theme.bg, Theme.cardFill)
    border.width: 1
    border.color: Theme.alpha(Theme.overlay, 0.5)
    Label {
        anchors.centerIn: parent
        text: Notifs.dnd ? "Do not disturb is on" : "No notifications"
        color: Theme.muted
    }
}
