import QtQuick
import QtQuick.Window

// A small info glyph (circled i by default; a lock / warning glyph for a disabled or unavailable thing) whose `text`
// shows as a tooltip while hovered: the place for the rare technical note (needs a border, needs the fork build, where a
// value is saved) so the page itself stays visual. The bubble lives on the window's content item (above every row,
// never clipped by the page's Flickable), right-aligned under the glyph, kept inside the window (Motion.hoverMs fade).
Item {
    id: tip
    property string text: ""
    property string icon: Icons.info           // circle-info
    property color color: Theme.muted
    property int maxWidth: 260
    readonly property int box: 16            // hit box of the glyph
    readonly property int keep: Theme.gapRow  // the bubble stays this far inside the window
    implicitWidth: box
    implicitHeight: box
    visible: text !== ""

    Icon { anchors.centerIn: parent; text: tip.icon; font.pixelSize: Theme.iconSm; color: hh.hovered ? Theme.fg : tip.color
           Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } } }
    HoverHandler { id: hh; cursorShape: Qt.WhatsThisCursor }

    readonly property Item overlay: tip.Window.window ? tip.Window.window.contentItem : null
    Rectangle {
        id: bubble
        parent: tip.overlay ?? tip
        // the glyph's bottom-right corner in the overlay's coordinates, re-read when the tip shows
        readonly property point at: { void hh.hovered; return tip.mapToItem(bubble.parent, tip.width, tip.height + Theme.controlGap) }
        x: Math.max(tip.keep, Math.min(at.x - width, bubble.parent.width - width - tip.keep))
        y: at.y + height > bubble.parent.height - tip.keep ? at.y - tip.height - Theme.pad - height : at.y
        z: 1000
        width: label.implicitWidth + 2 * Theme.padSm
        height: label.implicitHeight + Theme.padSm + Theme.gapTight
        radius: Theme.radiusItem
        color: Theme.alpha(Theme.bg, 0.97)
        border.width: 1
        border.color: Theme.edge
        opacity: hh.hovered ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
        Label {
            id: label
            x: Theme.padSm; y: (bubble.height - height) / 2
            width: Math.min(implicitWidth, tip.maxWidth)
            text: tip.text
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontCaption
            color: Theme.fgDim
        }
    }
}
