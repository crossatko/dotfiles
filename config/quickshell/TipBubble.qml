import QtQuick
import QtQuick.Window

// A hover bubble for the item it fills (`anchors.fill: parent`): `text` shows while `shown`, on the window's content item
// (above every row, never clipped by a Flickable), under the item (right edges aligned, or left with `alignRight: false`),
// kept inside the window (Motion.hoverMs fade). InfoTip (the glyph's note), FitLabel (the full text of a cut line).
Item {
    id: tb
    property string text: ""
    property bool shown: false
    property bool alignRight: true
    property int maxWidth: 260
    readonly property int keep: Theme.gapRow  // the bubble stays this far inside the window

    readonly property Item overlay: tb.Window.window ? tb.Window.window.contentItem : null
    Rectangle {
        id: bubble
        parent: tb.overlay ?? tb
        // the item's bottom corner in the overlay's coordinates, re-read when the bubble shows
        readonly property point at: { void tb.shown; return tb.mapToItem(bubble.parent, tb.alignRight ? tb.width : 0, tb.height + Theme.controlGap) }
        x: Math.max(tb.keep, Math.min(tb.alignRight ? at.x - width : at.x, bubble.parent.width - width - tb.keep))
        y: at.y + height > bubble.parent.height - tb.keep ? at.y - tb.height - Theme.pad - height : at.y
        z: 1000
        width: label.width + 2 * Theme.padSm
        height: label.implicitHeight + Theme.padSm + Theme.gapTight
        radius: Theme.radiusItem
        color: Theme.alpha(Theme.bg, 0.97)
        border.width: 1
        border.color: Theme.edge
        opacity: tb.shown && tb.text !== "" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
        Label {
            id: label
            x: Theme.padSm; y: (bubble.height - height) / 2
            width: Math.min(implicitWidth, tb.maxWidth, bubble.parent.width - 2 * tb.keep - 2 * Theme.padSm)
            text: tb.text
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontCaption
            color: Theme.fgDim
        }
    }
}
