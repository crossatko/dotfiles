pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// A monitor's wallpaper still in the monitor's real aspect (cover crop, small rounded corners, hairline): the thumbnail of
// MonitorChip, the MonitorCard head and the Bar page's "copy layout from" buttons. `h` sets the height, the width follows
// the aspect (clamped so a portrait or ultrawide monitor stays a sensible chip).
Item {
    id: th
    property var screen: null
    property string source: LockWallpapers.stillFor(th.screen)
    property int h: 26
    readonly property real aspect: th.screen && th.screen.height > 0 ? th.screen.width / th.screen.height : 16 / 9

    implicitHeight: h
    implicitWidth: Math.max(Math.round(h * 0.66), Math.min(Math.round(h * 2.25), Math.round(h * aspect)))

    Rectangle { id: corners; anchors.fill: parent; radius: Math.min(3, Theme.radiusDeep); visible: false; layer.enabled: true }
    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: corners }
        Rectangle { anchors.fill: parent; color: Theme.itemActive }
        Image {
            anchors.fill: parent
            source: th.source
            sourceSize.width: 2 * th.width
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: corners.radius
        color: Theme.alpha(Theme.fg, 0)
        border.width: 1
        border.color: Theme.edge
    }
}
