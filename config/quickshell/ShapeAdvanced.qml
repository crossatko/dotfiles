pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

// Settings > Look & feel > Shape > Customise…: corner radius, window border, window gap, a separate edge gap, and
// smart gaps (one switch; with several monitors a MonitorChooser with an "All" chip picks what it edits: All = every
// monitor, also ones connected later, and drops the per-monitor entries; a monitor = its own entry, undone by the
// reset glyph; a chip with its own entry says "on" / "off"), with a sample of the
// concentric radii. Writes only through the Appearance singleton (appearance.json overrides, debounced save, then
// Hyprland is poked); shows the EFFECTIVE values from Theme (override, else the theme default). Everything in the
// shell and Hyprland follows at once. Slider rows end in the value and a reset glyph (lit while the key is set), like
// every other fold. A change here turns the Shape choice above into Custom.
ColumnLayout {
    id: sa
    // true for a moment after every slider move: Settings.qml stops the page Flickable from stealing the drag
    readonly property bool dragging: dragHold.running
    Timer { id: dragHold; interval: 300 }
    property real titleW: 120
    readonly property int valueW: 62        // the value column of every slider row (PrefSlider.valueWidth)
    spacing: 12

    // effective value of a numeric key
    function eff(key) {
        if (key === "radius") return Theme.radius
        if (key === "gap") return Theme.gap
        if (key === "edgeGap") return Theme.gapOut
        if (key === "border") return Theme.borderSize
        return 0
    }
    function slide(key, v, max, step) {
        dragHold.restart()
        Appearance.set(key, Math.round(v * max / step) * step)
    }
    readonly property bool multiMonitor: Quickshell.screens.length > 1
    property bool smartAll: true                     // the chooser's "All" chip is picked (page-local; a monitor = Monitors.selected)
    readonly property var smartScreen: multiMonitor && !smartAll ? Monitors.selected : null
    readonly property string smartKey: smartScreen ? Appearance.monitorKey(smartScreen) : ""
    // with one monitor the "all monitors" switch is the only one: it shows that monitor's effective value
    // (a leftover entry of its own, e.g. from a docked laptop, wins in Hyprland) and clears it when used
    readonly property string soleKey: !multiMonitor && Quickshell.screens.length === 1 ? Appearance.monitorKey(Quickshell.screens[0]) : ""

    Repeater {
        model: [
            { key: "radius", title: "Corner radius", max: 24, step: 1 },
            { key: "border", title: "Window border", max: 4, step: 1 },
            { key: "gap", title: "Window gap", max: 32, step: 2 }
        ]
        delegate: sliderRow
    }
    SettingRow {
        titleWidth: sa.titleW
        Toggle {
            objectName: "toggle-edgeGap"
            checked: Appearance.overridden("edgeGap")
            onToggled: want => want ? Appearance.set("edgeGap", Theme.gapOut) : Appearance.unset("edgeGap")
        }
        Label { text: "Separate edge gap"; color: Theme.fgDim; font.pixelSize: Theme.fontSmall }
        Item { Layout.fillWidth: true }
    }
    Repeater {
        model: [{ key: "edgeGap", title: "Edge gap", max: 40, step: 1 }]
        delegate: sliderRow
    }
    SettingRow {
        visible: smartMons.shown
        titleWidth: sa.titleW
        MonitorChooser {
            id: smartMons
            objectName: "smart-monitors"
            allEntry: true
            allCurrent: sa.smartAll
            subtitleFor: s => { const k = Appearance.monitorKey(s); return Appearance.smartOverridden(k) ? (Appearance.smartFor(k, Theme.smartGaps) ? "on" : "off") : "" }
            onPicked: name => sa.smartAll = name === ""
        }
    }
    SettingRow {
        titleWidth: sa.titleW
        // All: sets the default (also for monitors connected later) and clears the per-monitor entries; a monitor: its own entry
        Toggle {
            objectName: "toggle-smartGaps"
            checked: sa.smartKey !== "" ? Appearance.smartFor(sa.smartKey, Theme.smartGaps)
                   : sa.soleKey !== "" ? Appearance.smartFor(sa.soleKey, Theme.smartGaps) : Theme.smartGaps
            onToggled: want => sa.smartKey !== "" ? Appearance.setSmartFor(sa.smartKey, want) : Appearance.setSmartAll(want)
        }
        Label { text: "Smart gaps"; color: Theme.fgDim; font.pixelSize: Theme.fontSmall }
        InfoTip { text: "A lone tiled window fills the screen without gaps." }
        Item { Layout.fillWidth: true }
        ResetBtn {
            objectName: "reset-smart-monitor"
            visible: sa.smartKey !== ""
            set: Appearance.smartOverridden(sa.smartKey)
            onClicked: Appearance.unsetSmartFor(sa.smartKey)
        }
    }

    // the concentric radii at real size: card (R) > item (inner(R, 12)) > chip (inner(item, 8))
    SettingRow {
        titleWidth: sa.titleW
        title: "Sample"
        Rectangle {
            id: sample
            implicitWidth: 220; implicitHeight: 110
            radius: Theme.radius
            color: Theme.alpha(Theme.bg, 0.9)
            border.width: 1
            border.color: Theme.alpha(Theme.overlay, 0.6)
            Label { x: Theme.pad; y: Theme.controlGap; height: 16; text: "card · " + Theme.radius; color: Theme.muted; font.pixelSize: Theme.fontCaption }
            Rectangle {
                anchors { fill: parent; margins: Theme.pad; topMargin: 24 }
                radius: Theme.radiusItem
                color: Theme.itemFill
                border.width: 1
                border.color: Theme.edge
                Label { x: Theme.gapRow; y: Theme.gapTight; height: 16; text: "item · " + Theme.radiusItem; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                Rectangle {
                    anchors { fill: parent; margins: Theme.gapRow; topMargin: 22 }
                    radius: Theme.radiusDeep
                    color: Theme.accentFill
                    border.width: 1
                    border.color: Theme.accentEdge
                    Label { anchors.centerIn: parent; text: "chip · " + Theme.radiusDeep; color: Theme.accent; font.pixelSize: Theme.fontCaption }
                }
            }
        }
        InfoTip { text: "Concentric corners: card " + Theme.radius + " / item " + Theme.radiusItem + " / chip " + Theme.radiusDeep + " px. Saved in appearance.json, applied to Hyprland and the shell at once." }
        Item { Layout.fillWidth: true }
    }

    // one labelled slider: title | slider | value | reset (lit while the key is overridden)
    Component {
        id: sliderRow
        SettingRow {
            id: row
            required property var modelData
            readonly property int cur: sa.eff(modelData.key)
            readonly property bool own: Appearance.overridden(modelData.key)
            title: modelData.title
            titleWidth: sa.titleW
            visible: modelData.key !== "edgeGap" || own
            Slider {
                wheel: false
                objectName: "slider-" + row.modelData.key
                Layout.fillWidth: true
                value: row.cur / row.modelData.max
                onMoved: v => sa.slide(row.modelData.key, v, row.modelData.max, row.modelData.step)
            }
            Label { text: row.cur + " px"; Layout.preferredWidth: sa.valueW; horizontalAlignment: Text.AlignRight; color: Theme.fg; font.pixelSize: Theme.fontSmall }
            ResetBtn {
                objectName: "reset-" + row.modelData.key
                set: row.own
                onClicked: if (row.own) Appearance.unset(row.modelData.key)
            }
        }
    }
}
