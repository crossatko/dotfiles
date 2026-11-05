import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications

// The reminder's notification card (NotifCard draws it in place of icon / summary / body for a card that carries
// ReminderService's private hint): caption row with age and close, the time left as a big numeral (ReminderService ticks
// it, no notification updates), the text with the length and a hairline progress line while it runs; at the end a red
// 0:00, "Time is up" and the snoozes + Dismiss (SnoozeRow). Its buttons act through ReminderService, then dismiss the card.
ColumnLayout {
    id: body
    required property var n
    property bool showTime: false
    property real outerRadius: Theme.radius
    signal dismissRequested()

    readonly property bool ended: n.urgency === NotificationUrgency.Critical || n === ReminderService.expiredNote
    readonly property bool current: n === ReminderService.note
    readonly property string note: ReminderService.cardLabel(n)

    spacing: Theme.gapTight

    CaptionRow {
        Layout.fillWidth: true
        glyph: Icons.hourglass
        text: body.ended ? "Time is up" : "Reminder"
        tone: body.ended ? Theme.red : Theme.fgDim
        pixelSize: Theme.fontCaption
        Item { Layout.fillWidth: true }
        NotifTrail { nid: body.n.id; showTime: body.showTime; onCloseClicked: body.dismissRequested() }
    }
    BigDigits {
        compact: true
        text: ReminderService.fmt(body.current ? ReminderService.remaining : 0)
        color: body.ended ? Theme.red : Theme.fg
    }
    RowLayout {
        Layout.fillWidth: true
        visible: body.note !== "" || body.current
        spacing: Theme.controlGap
        Label {
            visible: body.note !== ""
            Layout.fillWidth: true
            Layout.maximumWidth: implicitWidth
            text: body.note
            color: Theme.fgDim
            elide: Text.ElideRight
        }
        Label {
            visible: body.current
            text: "of " + ReminderService.lengthText(ReminderService.total)
            color: Theme.muted
        }
        Item { Layout.fillWidth: true }
    }
    ProgressHairline {
        visible: !body.ended
        Layout.fillWidth: true
        Layout.topMargin: Theme.gapTight
        value: body.current ? ReminderService.progress : 0
    }
    SnoozeRow {
        visible: body.ended
        Layout.fillWidth: true
        Layout.topMargin: Theme.gapTight
        minutes: ReminderService.cardMinutes(body.n)
        primaryFirst: true
        outerRadius: body.outerRadius
        onSnoozed: step => { ReminderService.snooze(step, body.n); body.dismissRequested() }
        onDismissed: body.dismissRequested()
    }
}
