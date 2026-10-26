pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

// Settings -> Desktop clock: a live preview (DeskClockPreview: the real DeskClockView over that monitor's wallpaper,
// 16:9, shown even while the clock is off) and the DeskClockPrefs keys (deskclock.json). Everything applies live.
// The glass itself (refraction, light, tint) is Settings > Glass.
Item {
    id: pg
    implicitHeight: col.implicitHeight

    readonly property int titleW: 120
    readonly property bool dragging: size.dragging || posX.dragging || posY.dragging
    readonly property var monitors: Quickshell.screens.filter(s => s && s.width > 0)
    property int monitorIdx: 0
    function pct(v) { return Math.round(v * 100) + " %" }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 12

        PrefToggle { titleWidth: pg.titleW; store: DeskClockPrefs; key: "enabled"; label: "Show the clock on the desktop"; hint: "under all windows, over the wallpaper" }

        SectionHead {
            title: "Preview"
            detail: pg.monitors.length > 1 ? "" : "as on " + (pg.monitors[0] ? pg.monitors[0].name : "this monitor")
            Layout.topMargin: 6
        }
        Segmented {
            visible: pg.monitors.length > 1
            values: pg.monitors.map((s, i) => i)
            labels: pg.monitors.map(s => s.name)
            current: pg.monitorIdx
            inset: 18; segHeight: 24
            onPicked: v => pg.monitorIdx = v
        }
        DeskClockPreview {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight      // 16:9
            screen: pg.monitors[Math.min(pg.monitorIdx, pg.monitors.length - 1)] || null
        }

        SectionHead { title: "Look"; detail: "glass: Settings > Glass"; Layout.topMargin: 6 }
        PrefSlider { id: size; title: "Size"; titleWidth: pg.titleW; store: DeskClockPrefs; key: "size"; format: v => pg.pct(v) }
        PrefSlider { id: posX; title: "Horizontal"; titleWidth: pg.titleW; store: DeskClockPrefs; key: "posX"; format: v => pg.pct(v) }
        PrefSlider { id: posY; title: "Vertical"; titleWidth: pg.titleW; store: DeskClockPrefs; key: "posY"; format: v => pg.pct(v) }
        PrefToggle { titleWidth: pg.titleW; store: DeskClockPrefs; key: "showDate"; label: "Show the date" }
        PrefToggle { titleWidth: pg.titleW; store: DeskClockPrefs; key: "clock24h"; label: "24-hour clock"; hint: "off: 12-hour without AM / PM" }

        SectionHead { title: "Monitors"; Layout.topMargin: 6 }
        Repeater {
            model: pg.monitors
            delegate: SettingRow {
                id: mrow
                required property var modelData
                readonly property string key: Appearance.monitorKey(modelData)
                titleWidth: pg.titleW
                Toggle {
                    objectName: "toggle-deskclock-" + mrow.modelData.name
                    checked: DeskClockPrefs.hidden[mrow.key] !== true
                    enabledLook: mrow.key !== "" && DeskClockPrefs.enabled
                    onToggled: want => DeskClockPrefs.setShownOn(mrow.key, want)
                }
                Icon { text: ""; font.pixelSize: 12; color: Theme.fgDim; Layout.preferredWidth: 16; horizontalAlignment: Text.AlignHCenter }
                Label { text: mrow.modelData.model || mrow.modelData.name; color: Theme.fgDim; font.pixelSize: Theme.fontSmall; elide: Text.ElideRight; Layout.maximumWidth: 220 }
                Label { text: mrow.modelData.name; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true; elide: Text.ElideRight }
            }
        }

        RowLayout {
            Layout.topMargin: 6
            Btn { objectName: "btn-deskclock-reset"; text: "Reset all"; inset: 18; implicitHeight: 26; enabledLook: Object.keys(DeskClockPrefs.data).length > 0; onClicked: DeskClockPrefs.reset() }
            Item { Layout.fillWidth: true }
        }
    }
}
