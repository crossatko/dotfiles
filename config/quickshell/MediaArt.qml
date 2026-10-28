pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// A track's cover art (`url`) in a rounded frame (Theme.radiusItem), cropped to fill it; an empty tinted frame without
// art, a music note with `placeholder`, or the source's brand mark (`glyph`, Theme.brandFont). MediaPanel, LockMedia.
Rectangle {
    id: art
    property string url: ""
    property bool placeholder: false
    property string glyph: ""          // brand mark shown instead of the note (and also without `placeholder`)
    property bool glyphBrand: true     // false: `glyph` is an Icons glyph (Theme.iconFont)
    radius: Theme.radiusItem
    color: Theme.itemHover
    clip: true
    Icon {
        anchors.centerIn: parent
        visible: (art.placeholder || art.glyph !== "") && img.status !== Image.Ready
        text: art.glyph !== "" ? art.glyph : Icons.music
        font.family: art.glyph !== "" && art.glyphBrand ? Theme.brandFont : Theme.iconFont
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
