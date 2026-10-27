pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// A track's cover art (`url`) in a rounded frame (Theme.radiusItem), cropped to fill it; an empty tinted frame without
// art, or a music note with `placeholder`. MediaPanel, LockMedia.
Rectangle {
    id: art
    property string url: ""
    property bool placeholder: false
    radius: Theme.radiusItem
    color: Theme.alpha(Theme.fg, 0.08)
    clip: true
    Icon {
        anchors.centerIn: parent
        visible: art.placeholder && img.status !== Image.Ready
        text: ""
        font.pixelSize: Math.round(art.height * 0.32)
        color: Theme.muted
    }
    Image {
        id: img
        anchors.fill: parent
        source: art.url
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // clip only cuts to the bounding box; mask the cover to the frame's rounded shape
        layer.enabled: art.radius > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: artMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }
    Rectangle {
        id: artMask
        anchors.fill: parent
        radius: art.radius
        visible: false
        layer.enabled: true
        layer.smooth: true
    }
}
