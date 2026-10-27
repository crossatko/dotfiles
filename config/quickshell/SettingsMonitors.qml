pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

// Settings -> Monitors: the monitor map (MonitorPicker: real sizes and positions, wallpaper in each tile; click selects,
// double click / Enter makes primary), the Primary choice (Auto = highest refresh rate, Manual = a saved monitor), and one
// detail card (MonitorCard) for the selected monitor with its per-monitor switches (bar, lock clock, desktop clock). The
// switches write the features' own stores (bars.json, lock.json, deskclock.json): this page is the one place for them;
// the Bar / Lock screen / Desktop clock pages keep only their own settings. The selection is the shared Settings pick
// (Monitors.selected): the MonitorChooser of the other pages shows the same monitor.
Item {
    id: pg
    implicitHeight: col.implicitHeight

    readonly property var monitors: Monitors.ordered.filter(s => s.width > 0)
    // the selected monitor = the shared Settings pick (default: the primary; a monitor that went away falls back to it)
    readonly property var sel: Monitors.selected || monitors[0] || null
    function select(name) { Monitors.select(name) }
    // fresh refresh rates / scales for the badges: at open and whenever an output's geometry changes (a new mode or scale)
    readonly property string geometry: monitors.map(s => [s.name, s.x, s.y, s.width, s.height].join(" ")).join(",")
    onGeometryChanged: Hyprland.refreshMonitors()
    Component.onCompleted: Hyprland.refreshMonitors()

    // keyboard: the item Tab lands on is scrolled into view (Settings hands the page its scroller)
    property Flickable flick: null
    readonly property Item focusItem: Window.activeFocusItem
    onFocusItemChanged: {
        let it = focusItem
        while (it && it !== pg) it = it.parent
        if (!it || !flick) return
        const y = focusItem.mapToItem(flick.contentItem, 0, 0).y, m = Theme.pad
        if (y - m < flick.contentY) flick.contentY = Math.max(0, y - m)
        else if (y + focusItem.height + m > flick.contentY + flick.height)
            flick.contentY = Math.min(flick.contentHeight - flick.height, y + focusItem.height + m - flick.height)
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 12

        MonitorPicker {
            objectName: "monitor-picker"
            selected: pg.sel ? pg.sel.name : ""
            onPicked: name => pg.select(name)
        }

        ChoiceRow {
            objectName: "primary-mode"
            title: "Primary"
            titleWidth: 120
            values: ["auto", "manual"]
            labels: ["Auto", "Manual"]
            objectNames: ["primary-auto", "primary-manual"]
            segWidth: 70
            current: Monitors.custom ? "manual" : "auto"
            hint: Monitors.title(Monitors.primary)
            info: "Opens Settings, OSD and popups. Auto: highest refresh rate. Double-click a monitor to pick it."
            // Manual pins the selected monitor (or keeps the current pick); Auto drops the saved choice
            onPicked: v => v === "auto" ? Monitors.clearPrimary() : Monitors.setPrimary(pg.sel || Monitors.primary)
        }

        Loader {
            id: detail
            Layout.fillWidth: true
            active: pg.sel !== null
            sourceComponent: MonitorCard { monitor: pg.sel }
        }
    }
    // the card re-fills for another monitor: it arrives again (Reveal) instead of jumping
    Reveal { id: cardReveal; target: detail; rise: 6 }
    onSelChanged: cardReveal.play()
}
