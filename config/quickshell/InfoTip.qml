import QtQuick

// A small info glyph (circled i by default; a lock / warning glyph for a disabled or unavailable thing) whose `text`
// shows as a tooltip while hovered: the place for the rare technical note (needs a border, needs the fork build, where a
// value is saved) so the page itself stays visual. The bubble lives on the window's content item (above every row,
// never clipped by the page's Flickable), right-aligned under the glyph, kept inside the window (TipBubble).
Item {
    id: tip
    property string text: ""
    property string icon: Icons.info           // circle-info
    property color color: Theme.muted
    property int maxWidth: 260
    readonly property int box: 16            // hit box of the glyph
    implicitWidth: box
    implicitHeight: box
    visible: text !== ""

    Icon { anchors.centerIn: parent; text: tip.icon; font.pixelSize: Theme.iconSm; color: hh.hovered ? Theme.fg : tip.color
           Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } } }
    HoverHandler { id: hh; cursorShape: Qt.WhatsThisCursor }

    TipBubble { anchors.fill: parent; text: tip.text; shown: hh.hovered; maxWidth: tip.maxWidth }
}
