pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell

// Settings > Desktop clock: the real desktop clock (DeskClockView in preview mode, with the wallpaper drawn under it)
// of `screen`, always 16:9: rendered at a virtual 1920 x 1080 and scaled down uniformly into this item, with rounded
// corners (as LockPreview). Follows DeskClockPrefs and Settings > Glass live; shows the clock even while it is off.
Item {
    id: pv
    property var screen: Quickshell.screens[0]
    readonly property Item cornerMask: corners
    readonly property real sw: 1920
    readonly property real sh: 1080
    implicitHeight: Math.round(width * sh / sw)
    function demo() { view.demo() }      // the digits' morph: one minute ahead and back

    Item {
        id: frame
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: pv.cornerMask }
        DeskClockView {
            id: view
            width: pv.sw
            height: pv.sh
            scale: pv.width / pv.sw
            transformOrigin: Item.TopLeft
            preview: true
            wallpaper: LockWallpapers.stillFor(pv.screen)
            screen: pv.screen
        }
    }
    Rectangle { id: corners; anchors.fill: parent; radius: Theme.radiusItem; visible: false; layer.enabled: true }
    Rectangle { anchors.fill: parent; radius: Theme.radiusItem; color: "transparent"; border.width: 1; border.color: Theme.alpha(Theme.overlay, 0.5) }
}
