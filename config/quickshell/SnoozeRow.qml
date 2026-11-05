pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// The ended reminder's buttons: one "+N min" per snooze step (ReminderService.snoozeFor the first length in `minutes`),
// then Dismiss. `fill` = equal buttons across the width (popup), else packed to the left (notification card);
// `primaryFirst` marks the first snooze as the primary button.
RowLayout {
    id: sr
    property int minutes: 1
    property bool fill: false
    property bool primaryFirst: false
    property int buttonH: Theme.controlH
    property real outerRadius: Theme.radius
    property real inset: Theme.pad
    signal snoozed(int step)
    signal dismissed()

    spacing: Theme.controlGap
    Repeater {
        model: ReminderService.snoozeFor(sr.minutes)
        Btn {
            required property int modelData
            required property int index
            Layout.fillWidth: sr.fill
            implicitHeight: sr.buttonH
            outerRadius: sr.outerRadius; inset: sr.inset
            text: "+" + modelData + " min"
            active: sr.primaryFirst && index === 0
            onClicked: sr.snoozed(modelData)
        }
    }
    Btn {
        Layout.fillWidth: sr.fill
        implicitHeight: sr.buttonH
        outerRadius: sr.outerRadius; inset: sr.inset
        text: "Dismiss"
        onClicked: sr.dismissed()
    }
    Item { visible: !sr.fill; Layout.fillWidth: true }
}
