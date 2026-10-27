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
    readonly property bool dragging: size.dragging || posX.dragging || posY.dragging || adaptStrength.dragging || morph.dragging
    readonly property var monitors: Quickshell.screens.filter(s => s && s.width > 0)
    property int monitorIdx: 0
    function pct(v) { return Math.round(v * 100) + " %" }
    function times(v) { return v <= 0 ? "instant" : Number(v.toFixed(2)) + "x" }
    // a changed morph time shows itself in the preview once the slider rests
    Connections { target: DeskClockPrefs; function onMorphChanged() { morphShow.restart() } }
    Timer { id: morphShow; interval: 400; onTriggered: preview.demo() }

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
            id: preview
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight      // 16:9
            screen: pg.monitors[Math.min(pg.monitorIdx, pg.monitors.length - 1)] || null
        }

        SectionHead { title: "Look"; detail: "glass: Settings > Glass"; Layout.topMargin: 6 }
        PrefSlider { id: size; title: "Size"; titleWidth: pg.titleW; store: DeskClockPrefs; key: "size"; format: v => pg.pct(v) }
        PrefSlider { id: posX; title: "Horizontal"; titleWidth: pg.titleW; store: DeskClockPrefs; key: "posX"; format: v => pg.pct(v) }
        PrefSlider { id: posY; title: "Vertical"; titleWidth: pg.titleW; store: DeskClockPrefs; key: "posY"; format: v => pg.pct(v) }
        PrefToggle { titleWidth: pg.titleW; store: DeskClockPrefs; key: "showDate"; label: "Show the date" }
        PrefToggle { titleWidth: pg.titleW; store: DeskClockPrefs; key: "adapt"; label: "Adapt to wallpaper"; hint: "light, clear glass over a bright wallpaper" }
        PrefSlider { id: adaptStrength; title: "Adapt strength"; titleWidth: pg.titleW; store: DeskClockPrefs; key: "adaptStrength"; format: v => pg.pct(v); enabled: DeskClockPrefs.adapt; opacity: enabled ? 1 : 0.4 }

        SectionHead {
            title: "Clock"; detail: "morph at the Animations speed, with seconds 0.45 s at most"; Layout.topMargin: 6
            Btn { objectName: "btn-deskclock-morph"; text: "Show morph"; inset: 18; implicitHeight: 26; onClicked: preview.demo() }
        }
        PrefToggle { titleWidth: pg.titleW; store: DeskClockPrefs; key: "clock24h"; label: "24-hour clock"; hint: "off: 12-hour without AM / PM" }
        PrefToggle { titleWidth: pg.titleW; store: DeskClockPrefs; key: "seconds"; label: "Seconds"; hint: "only the changing digits redraw each second" }
        PrefSlider { id: morph; title: "Morph time"; titleWidth: pg.titleW; store: DeskClockPrefs; key: "morph"; format: v => pg.times(v) }

        SectionHead { title: "Monitors"; Layout.topMargin: 6 }
        MonitorToggles {
            Layout.fillWidth: true
            titleWidth: pg.titleW
            idPrefix: "toggle-deskclock"
            enabledLook: DeskClockPrefs.enabled
            isOn: key => DeskClockPrefs.hidden[key] !== true
            onToggled: (key, on) => DeskClockPrefs.setShownOn(key, on)
        }

        RowLayout {
            Layout.topMargin: 6
            Btn { objectName: "btn-deskclock-reset"; text: "Reset all"; inset: 18; implicitHeight: 26; enabledLook: Object.keys(DeskClockPrefs.data).length > 0; onClicked: DeskClockPrefs.reset() }
            Item { Layout.fillWidth: true }
        }
    }
}
