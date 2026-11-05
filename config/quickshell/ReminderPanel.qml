pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Reminder popup (reminder chip; state in ReminderService.qml). The numeral is the interface:
//  - setup: one big editable number of minutes with - / + (MinutesStepper), presets, an optional text, Start (Enter in
//    the number or the text starts too);
//  - running: the time left, its text, a hairline progress line, Cancel and +5 min;
//  - ended (until the end card is dismissed or snoozed): a red 0:00, the snoozes and Dismiss (SnoozeRow, as on the card).
ColumnLayout {
    id: rp
    spacing: Theme.pad

    readonly property var presets: [5, 10, 15, 30, 60]
    property int minutes: 15
    property string error: ""
    readonly property bool running: ReminderService.active
    readonly property bool ended: !running && ReminderService.isExpired

    function begin() {
        rp.error = ReminderService.start(rp.minutes, note.text)
        if (rp.error === "") note.text = ""
    }

    CaptionRow {
        Layout.fillWidth: true
        glyph: Icons.hourglass
        text: "Reminder"
        tone: rp.ended ? Theme.red : Theme.fgDim
        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: rp.ended ? "Time is up" : rp.running ? "Running" : ""
            color: rp.ended ? Theme.red : Theme.fgDim
            font.pixelSize: Theme.fontSmall
        }
    }

    // ---- setup ----
    ColumnLayout {
        visible: !rp.running && !rp.ended
        Layout.fillWidth: true
        spacing: Theme.pad

        MinutesStepper {
            Layout.fillWidth: true
            value: rp.minutes
            max: ReminderService.maxMinutes
            onMoved: v => { rp.minutes = v; rp.error = "" }
            onAccepted: rp.begin()
        }
        Segmented {
            Layout.fillWidth: true
            fillWidth: width
            values: rp.presets
            labels: rp.presets.map(m => m < 60 ? String(m) : m / 60 + " h")
            current: rp.presets.indexOf(rp.minutes) >= 0 ? rp.minutes : undefined
            onPicked: v => { rp.minutes = v; rp.error = "" }
        }
        FieldBox {
            id: note
            Layout.fillWidth: true
            flat: true
            placeholder: "What for?"
            maximumLength: ReminderService.labelMax
            onAccepted: rp.begin()
            onCancelled: note.input.focus = false
        }
        Label {
            visible: rp.error !== ""
            text: rp.error
            color: Theme.red
            font.pixelSize: Theme.fontCaption
        }
        Btn {
            Layout.fillWidth: true
            implicitHeight: Theme.rowH
            glyph: Icons.play
            text: "Start"
            active: true
            enabledLook: rp.minutes >= 1
            onClicked: rp.begin()
        }
    }

    // ---- running / ended ----
    ColumnLayout {
        visible: rp.running || rp.ended
        Layout.fillWidth: true
        spacing: Theme.gapTight

        BigDigits {
            text: ReminderService.fmt(ReminderService.remaining)
            color: rp.ended ? Theme.red : Theme.fg
        }
        Label {
            Layout.fillWidth: true
            text: rp.ended ? ReminderService.expired?.label ?? "" : ReminderService.label
            color: Theme.fgDim
            elide: Text.ElideRight
        }
        ProgressHairline {
            Layout.fillWidth: true
            Layout.topMargin: Theme.gapRow
            value: rp.ended ? 1 : ReminderService.progress
            fillColor: rp.ended ? Theme.red : Theme.accent
        }
        RowLayout {
            visible: rp.running
            Layout.fillWidth: true
            Layout.topMargin: Theme.gapRow
            spacing: Theme.controlGap
            Btn { Layout.fillWidth: true; text: "Cancel"; onClicked: ReminderService.cancel() }
            Btn { Layout.fillWidth: true; text: "+" + ReminderService.extendMinutes + " min"; onClicked: ReminderService.extend(ReminderService.extendMinutes) }
        }
        SnoozeRow {
            visible: rp.ended
            Layout.fillWidth: true
            Layout.topMargin: Theme.gapRow
            fill: true
            minutes: ReminderService.expired?.minutes ?? 1
            onSnoozed: step => ReminderService.snooze(step, null)
            onDismissed: ReminderService.dismissExpired()
        }
    }
}
