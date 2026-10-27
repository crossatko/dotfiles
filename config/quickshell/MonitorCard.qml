pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings > Monitors: the detail card of the monitor selected on the map (MonitorPicker). Head = name (model, elided),
// connector, mode / scale badges, then PrimaryTag or "Set as primary". Body = the per-monitor switches, each written to
// its feature's OWN store (no copy here): Bar = BarConfig "enabled" (a linked group goes on / off together; the last bar
// stays on: it is the way back into Settings), Lock clock = LockPrefs.setClockOn, Desktop clock =
// DeskClockPrefs.setShownOn (locked while the clock is off on its page). objectNames: monitor-card-<connector>,
// mon-bar|mon-lockclock|mon-deskclock-<connector> (+ "-toggle"), mon-primary-<connector>.
Rectangle {
    id: card
    required property var monitor
    readonly property string key: Appearance.monitorKey(monitor)
    readonly property bool primary: Monitors.isPrimary(monitor)
    readonly property bool barOn: BarConfig.enabled(monitor)
    readonly property bool barLast: barOn && !BarConfig.canDisable(monitor)
    readonly property bool barLinked: BarConfig.groupOf(monitor).length > 1

    objectName: "monitor-card-" + monitor.name
    implicitHeight: col.implicitHeight + 2 * Theme.pad
    radius: Theme.radiusPage
    color: Theme.alpha(Theme.fg, 0.04)
    border.width: 1
    border.color: Theme.edge

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.pad }
        spacing: Theme.pad

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.controlH          // same height with the tag or the button
            spacing: Theme.gapRow
            Icon { text: Icons.monitor; font.pixelSize: Theme.iconMd; color: card.primary ? Theme.accent : Theme.fgDim; Layout.preferredWidth: Theme.iconLg; horizontalAlignment: Text.AlignHCenter }
            Label {
                objectName: "mon-name-" + card.monitor.name
                text: Monitors.title(card.monitor)
                font.pixelSize: Theme.fontSize; font.bold: true; color: Theme.fg
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.maximumWidth: implicitWidth
                Layout.minimumWidth: Math.min(implicitWidth, 60)
            }
            // the connector only when the model name does not already say it
            Label { visible: Monitors.title(card.monitor) !== card.monitor.name; text: Monitors.label(card.monitor); font.pixelSize: Theme.fontCaption; color: Theme.muted }
            Pill { objectName: "mon-mode-" + card.monitor.name; text: Monitors.modeText(card.monitor); tint: Theme.fgDim }
            Pill { objectName: "mon-scale-" + card.monitor.name; text: Monitors.scaleText(card.monitor); tint: Theme.fgDim }
            Item { Layout.fillWidth: true; Layout.preferredWidth: 0 }
            PrimaryTag { visible: card.primary }
            Btn {
                objectName: "mon-primary-" + card.monitor.name
                visible: !card.primary
                outerRadius: Theme.radiusPage; inset: Theme.pad
                implicitHeight: 26
                text: "Set as primary"
                onClicked: Monitors.setPrimary(card.monitor)
            }
        }

        // the switches: three across while each fits whole, else one per row (narrow window)
        GridLayout {
            id: grid
            Layout.fillWidth: true
            readonly property real tileW: Math.max(barSw.implicitWidth, lockSw.implicitWidth, deskSw.implicitWidth)
            columns: width >= 3 * tileW + 2 * columnSpacing ? 3 : 1
            columnSpacing: Theme.controlGap
            rowSpacing: Theme.controlGap
            LabelSwitch {
                id: barSw
                objectName: "mon-bar-" + card.monitor.name
                Layout.fillWidth: true; Layout.preferredWidth: 1
                icon: Icons.tableColumns
                label: "Bar"
                checked: card.barOn
                enabledLook: !card.barLast
                tip: card.barLast ? "Last bar" : card.barLinked ? "Linked bars" : ""
                tipIcon: card.barLast ? Icons.lock : Icons.info
                onToggled: want => BarConfig.set(card.monitor, "enabled", want)
            }
            LabelSwitch {
                id: lockSw
                objectName: "mon-lockclock-" + card.monitor.name
                Layout.fillWidth: true; Layout.preferredWidth: 1
                icon: Icons.lock
                label: "Lock clock"
                checked: LockPrefs.hidden[card.key] !== true
                enabledLook: card.key !== ""
                onToggled: want => LockPrefs.setClockOn(card.key, want)
            }
            LabelSwitch {
                id: deskSw
                objectName: "mon-deskclock-" + card.monitor.name
                Layout.fillWidth: true; Layout.preferredWidth: 1
                icon: Icons.clock
                label: "Desktop clock"
                checked: DeskClockPrefs.hidden[card.key] !== true      // the saved choice, dimmed while the clock is off
                enabledLook: DeskClockPrefs.enabled && card.key !== ""
                tip: DeskClockPrefs.enabled ? "" : "Clock is off"
                tipIcon: Icons.lock
                onToggled: want => DeskClockPrefs.setShownOn(card.key, want)
            }
        }
    }
}
