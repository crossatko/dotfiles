import QtQuick
import QtQuick.Layouts

// The end of a notification card's first row: the age (notification center only) and the close glyph. NotifCard and the
// reminder card (ReminderCardBody) share it.
RowLayout {
    id: trail
    property int nid: 0
    property bool showTime: false
    signal closeClicked()

    spacing: Theme.controlGap
    Label {
        visible: trail.showTime
        text: Notifs.ago(trail.nid)
        color: Theme.muted
        font.pixelSize: Theme.fontCaption
    }
    Icon {
        text: Icons.xmark
        color: closeArea.containsMouse ? Theme.accent : Theme.muted
        font.pixelSize: Theme.iconSm
        Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
        MouseArea { id: closeArea; anchors.fill: parent; anchors.margins: -Theme.controlGap; hoverEnabled: true; onClicked: trail.closeClicked() }
    }
}
