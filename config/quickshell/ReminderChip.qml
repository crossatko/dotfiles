import QtQuick
import QtQuick.Layouts

// The reminder chip (Bar.qml widget "reminder"; state in ReminderService): an hourglass at rest; while a reminder runs
// the hourglass sits in a small ring that drains with the time left, next to the time left; once it has ended the ring is
// full and red with a red 0:00 until the end card is dismissed or snoozed. Click = the reminder popup (ReminderPanel.qml).
Chip {
    id: chip
    readonly property bool running: ReminderService.active
    readonly property bool ended: !running && ReminderService.isExpired
    readonly property color tone: ended ? chip.ink.red : chip.ink.accent
    readonly property int ringPx: Theme.chipIcon + 2 * Theme.gapTight     // 24: the ring around the glyph
    readonly property int ringStroke: 2

    BarIcon { visible: !chip.running && !chip.ended; text: Icons.hourglass; color: chip.ink.fgDim }
    Item {
        visible: chip.running || chip.ended
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: chip.ringPx
        implicitHeight: chip.ringPx
        RingArc {
            anchors.fill: parent
            size: chip.ringPx
            stroke: chip.ringStroke
            value: chip.ended ? 1 : ReminderService.total > 0 ? ReminderService.remaining / ReminderService.total : 0
            color: chip.tone
            trackColor: Theme.alpha(chip.ink.fg, Theme.itemActive.a)   // the item-active wash in the chip's ink
        }
        BarIcon {
            anchors.centerIn: parent
            ink: chip.ink
            text: Icons.hourglass
            pixelSize: Theme.iconSm
            color: chip.tone
        }
    }
    BarLabel {
        visible: chip.running || chip.ended
        text: ReminderService.fmt(ReminderService.remaining)
        color: chip.ended ? chip.ink.red : chip.ink.fg
    }
}
