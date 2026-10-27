import QtQuick
import QtQuick.Layouts

// One card in a popup list (Bluetooth devices, wired links, Wi-Fi networks, Tailscale machines): a `rowH` tall
// head row = leading icon (22 px column) + the children you add (usually RowText, then a RowState or other
// trailing items), on an item-radius card that tints on hover / when `selected`. Click / hover cover the head row
// only and sit under the children (z: -1), so a child MouseArea (click-to-copy label) still gets its own clicks.
// Expandable rows put their extra content in `body` (shown under the head while `expanded`); the card grows
// with an animation and clips.
Rectangle {
    id: row

    property int rowH: Theme.rowH
    property string icon: ""                       // "" = no leading icon column
    property string iconFamily: Theme.iconFont
    property int iconSize: Theme.iconLg
    property color iconColor: Theme.fg
    property bool selected: false                  // connected / this device: accent tint
    property bool outlined: false                  // expanded / asking: accent outline
    property bool interactive: true                // false: no hover, no click (e.g. a wired link with nothing to connect)
    property bool rightClick: false                // also emit clicked() for the right button
    property color baseColor: Theme.itemFill
    readonly property bool hovered: glow.hovered && interactive   // pointer anywhere on the card, also over child controls (HoverGlow)
    // the default fill; a row with an extra state (Wi-Fi password form) overrides `color` and falls back to this
    readonly property color stateColor: selected ? (hovered ? Theme.accentHover : Theme.accentFill) : hovered ? Theme.itemHover : baseColor

    default property alias content: head.data
    property alias body: below.data
    property bool expanded: false
    property real bodyTop: 0                       // gap between head and body
    property real bodyLeft: Theme.pad              // body's left inset (pad + iconCol + pad = under the text column)
    property real bodyGap: Theme.gapRow            // card height added beyond the body's own height while expanded

    signal clicked(var mouse)

    implicitHeight: rowH + (expanded ? below.implicitHeight + bodyGap : 0)
    clip: true
    radius: Theme.radiusItem
    color: stateColor
    border.width: outlined ? 1 : 0
    border.color: Theme.accentEdge
    Behavior on implicitHeight { NumberAnimation { duration: Motion.moveMs; easing.type: Motion.easeMove } }
    Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }

    MouseArea {
        id: hoverArea
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: row.rowH
        z: -1
        hoverEnabled: true
        enabled: row.interactive
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: row.rightClick ? Qt.LeftButton | Qt.RightButton : Qt.LeftButton
        onClicked: mouse => row.clicked(mouse)
    }

    // pointer-following highlight over the lighter flat hover tint (HoverGlow.qml)
    HoverGlow { id: glow; area: hoverArea; radius: row.radius }
    PressFeedback { area: hoverArea; depth: 1.5 }

    RowLayout {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: Theme.pad; rightMargin: Theme.pad }
        height: row.rowH
        spacing: Theme.pad
        Icon {
            visible: row.icon !== ""
            text: row.icon
            font.family: row.iconFamily
            font.pixelSize: row.iconSize
            color: row.iconColor
            Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
            horizontalAlignment: Text.AlignHCenter
            Layout.preferredWidth: Theme.iconCol
        }
    }

    ColumnLayout {
        id: below
        anchors { left: parent.left; right: parent.right; top: head.bottom; leftMargin: row.bodyLeft; rightMargin: Theme.pad; topMargin: row.bodyTop }
        spacing: 0
        opacity: row.expanded ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
    }
}
