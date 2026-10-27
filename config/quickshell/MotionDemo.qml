import QtQuick

// Settings > Look & feel > Motion: a mock bar + popup card that replays close -> open with the shell's live popup
// tokens (Theme.popup*: speed, curve, style from Settings), so the picked motion is seen at once. Click to replay;
// replay() from outside (the page calls it when the choice changes).
Rectangle {
    id: demo
    implicitWidth: 260
    implicitHeight: 110
    radius: Theme.radiusPage
    color: Theme.alpha(Theme.fg, 0.04)
    border.width: 1
    border.color: Theme.alpha(Theme.overlay, 0.5)
    clip: true
    property real t: 1
    function replay() { anim.restart() }

    HoverGlow { area: demoArea; radius: demo.radius }
    Rectangle {
        id: demoBar
        x: 8; y: 8; width: parent.width - 16; height: 18
        radius: Theme.radiusChip
        color: Theme.surface2
        Rectangle { id: demoChip; x: 150; y: 3; width: 40; height: 12; radius: Math.min(4, Theme.radiusChip); color: Theme.alpha(Theme.accent, demo.t > 0.5 ? 0.5 : 0.2) }
    }
    Rectangle {
        id: demoCard
        width: 130; height: 66
        x: demoBar.x + demoChip.x + demoChip.width / 2 - width / 2
        y: demoBar.y + demoBar.height + 6
        radius: Theme.radiusItem
        color: Theme.alpha(Theme.bg, 0.95)
        border.width: 1
        border.color: Theme.alpha(Theme.overlay, 0.6)
        opacity: demo.t
        transform: [
            Scale {
                origin.x: demoCard.width / 2; origin.y: 0
                xScale: Theme.popupScaleFrom + (1 - Theme.popupScaleFrom) * demo.t
                yScale: Theme.popupScaleFrom + (1 - Theme.popupScaleFrom) * demo.t
            },
            Translate { y: -(1 - demo.t) * Theme.popupSlidePx }
        ]
        Column {
            x: 10; y: 10; spacing: 8
            Repeater {
                model: [0.7, 0.5, 0.85]
                Rectangle { required property real modelData; width: 110 * modelData; height: 8; radius: 4; color: Theme.alpha(Theme.fg, 0.18) }
            }
        }
    }
    SequentialAnimation {
        id: anim
        NumberAnimation { target: demo; property: "t"; to: 0; duration: Theme.popupCloseMs; easing.type: Theme.popupEaseClose }
        PauseAnimation { duration: 260 }
        NumberAnimation { target: demo; property: "t"; to: 1; duration: Theme.popupOpenMs; easing.type: Theme.popupEaseOpen }
    }
    Icon {   // replay
        anchors { right: parent.right; bottom: parent.bottom; margins: 8 }
        text: Icons.retry; font.pixelSize: 11
        color: demoArea.containsMouse ? Theme.fg : Theme.muted
    }
    MouseArea { id: demoArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: anim.restart() }
}
