pragma ComponentBehavior: Bound
import QtQuick

// Settings > Desktop clock: the real desktop clock (DeskClockView in preview mode, with the wallpaper drawn under it)
// of `screen`, always 16:9: rendered at a virtual 1920 x 1080 and scaled down uniformly into this item, with rounded
// corners (ScreenFrame, as LockPreview). Follows DeskClockPrefs and Settings > Glass live; shows the clock even while it is off.
Item {
    id: pv
    property var screen: Monitors.primary
    readonly property real sw: 1920
    readonly property real sh: 1080
    implicitHeight: Math.round(width * sh / sw)
    function demo() { view.demo() }      // the digits' morph: one minute ahead and back

    ScreenFrame {
        anchors.fill: parent
        virtualW: pv.sw
        virtualH: pv.sh
        DeskClockView {
            id: view
            anchors.fill: parent
            preview: true
            wallpaper: LockWallpapers.stillFor(pv.screen)
            screen: pv.screen
        }
    }
}
