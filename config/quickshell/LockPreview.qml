pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// Settings > Lock: the real lock visuals of `screen` (LockView in preview mode: its wallpaper still, cropped like the
// lock does, blur, dim, glass clock (or none: Settings > Monitors), date, `dots` sample beads and a sample
// playback card; no input, no video, never a session lock), always 16:9: rendered at a virtual 1920 x 1080 and scaled down uniformly into this item, with rounded corners. Follows LockPrefs live; replay() plays the lock's opening again.
Item {
    id: pv
    property var screen: Monitors.primary
    property int dots: 4
    readonly property Item cornerMask: corners
    readonly property real sw: 1920
    readonly property real sh: 1080
    function replay() { view.engage() }
    function demo() { view.demo() }      // the digits' morph: one minute ahead and back
    implicitHeight: Math.round(width * sh / sw)

    Item {
        id: frame
        anchors.fill: parent
        // rounded corners as the layer's effect (the frame stays visible: layered parts inside an invisible item, such as
        // the date's halo, were not drawn)
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: pv.cornerMask }
        LockView {
            id: view
            width: pv.sw
            height: pv.sh
            scale: pv.width / pv.sw
            transformOrigin: Item.TopLeft
            preview: true
            previewDots: pv.dots
            wallpaper: LockWallpapers.stillFor(pv.screen)
            screenName: pv.screen ? pv.screen.name : ""
            engaged: true
        }
    }
    Rectangle { id: corners; anchors.fill: parent; radius: Theme.radiusItem; visible: false; layer.enabled: true }
    Rectangle { anchors.fill: parent; radius: Theme.radiusItem; color: "transparent"; border.width: 1; border.color: Theme.alpha(Theme.overlay, 0.5) }
}
