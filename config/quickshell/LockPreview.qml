pragma ComponentBehavior: Bound
import QtQuick

// Settings > Lock: the real lock visuals of `screen` (LockView in preview mode: its wallpaper still, cropped like the
// lock does, blur, dim, glass clock (or none: LockPrefs.clockOn), date, `dots` sample beads and a sample
// playback card; no input, no video, never a session lock), always 16:9: rendered at a virtual 1920 x 1080 and scaled down uniformly into this item, with rounded corners. Follows LockPrefs live; replay() plays the lock's opening again.
Item {
    id: pv
    property var screen: Monitors.primary
    property int dots: 4
    readonly property real sw: 1920
    readonly property real sh: 1080
    function replay() { view.engage() }
    function demo() { view.demo() }      // the digits' morph: one minute ahead and back
    implicitHeight: Math.round(width * sh / sw)

    ScreenFrame {
        anchors.fill: parent
        virtualW: pv.sw
        virtualH: pv.sh
        LockView {
            id: view
            anchors.fill: parent
            preview: true
            previewDots: pv.dots
            wallpaper: LockWallpapers.stillFor(pv.screen)
            screenName: pv.screen ? pv.screen.name : ""
            engaged: true
        }
    }
}
