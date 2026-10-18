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

    property int rowH: 44
    property string icon: ""                       // "" = no leading icon column
    property string iconFamily: Theme.iconFont
    property int iconSize: 18
    property color iconColor: Theme.fg
    property bool selected: false                  // connected / this device: accent tint
    property bool outlined: false                  // expanded / asking: accent outline
    property bool interactive: true                // false: no hover, no click (e.g. a wired link with nothing to connect)
    property bool rightClick: false                // also emit clicked() for the right button
    property color baseColor: Theme.alpha(Theme.fg, 0.05)
    readonly property bool hovered: area.containsMouse && interactive
    // the default fill; a row with an extra state (Wi-Fi password form) overrides `color` and falls back to this
    readonly property color stateColor: hovered ? Theme.alpha(Theme.fg, 0.12) : selected ? Theme.alpha(Theme.accent, 0.18) : baseColor

    default property alias content: head.data
    property alias body: below.data
    property bool expanded: false
    property real bodyTop: 0                       // gap between head and body
    property real bodyLeft: 12                     // body's left inset (48 = under the text column)
    property real bodyGap: 8                       // card height added beyond the body's own height while expanded

    signal clicked(var mouse)

    implicitHeight: rowH + (expanded ? below.implicitHeight + bodyGap : 0)
    clip: true
    radius: Theme.radiusItem
    color: stateColor
    border.width: outlined ? 1 : 0
    border.color: Theme.alpha(Theme.accent, 0.7)
    Behavior on implicitHeight { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

    MouseArea {
        id: area
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: row.rowH
        z: -1
        hoverEnabled: true
        enabled: row.interactive
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: row.rightClick ? Qt.LeftButton | Qt.RightButton : Qt.LeftButton
        onClicked: mouse => row.clicked(mouse)
    }

    RowLayout {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 12 }
        height: row.rowH
        spacing: 14
        Icon {
            visible: row.icon !== ""
            text: row.icon
            font.family: row.iconFamily
            font.pixelSize: row.iconSize
            color: row.iconColor
            horizontalAlignment: Text.AlignHCenter
            Layout.preferredWidth: 22
        }
    }

    ColumnLayout {
        id: below
        anchors { left: parent.left; right: parent.right; top: head.bottom; leftMargin: row.bodyLeft; rightMargin: 12; topMargin: row.bodyTop }
        spacing: 0
        opacity: row.expanded ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
}
