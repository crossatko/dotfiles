pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings -> Desktop clock: a live preview (DeskClockPreview: the real DeskClockView over that monitor's wallpaper,
// 16:9, shown even while the clock is off), a few named choices (Presets.qml: size, morph; a 3 x 3 position grid) and,
// under Customise…, every DeskClockPrefs key (deskclock.json). Everything applies live. The glass itself (refraction,
// light, tint) is Settings > Look & feel.
Item {
    id: pg
    implicitHeight: col.implicitHeight

    readonly property int titleW: 120
    readonly property bool dragging: size.dragging || posX.dragging || posY.dragging || adaptStrength.dragging || morph.dragging
    readonly property var monitors: Monitors.ordered.filter(s => s.width > 0)
    function pct(v) { return Math.round(v * 100) + " %" }
    function times(v) { return v <= 0 ? "instant" : Number(v.toFixed(2)) + "x" }
    // a changed morph time shows itself in the preview once the slider rests
    Connections { target: DeskClockPrefs; function onMorphChanged() { morphShow.restart() } }
    Timer { id: morphShow; interval: 400; onTriggered: preview.demo() }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 12


        PrefSwitch {
            title: "Show clock"; titleWidth: pg.titleW; store: DeskClockPrefs; key: "enabled"
            info: DeskClockPrefs.enabled ? "Under all windows" : "Clock is off"
            infoIcon: DeskClockPrefs.enabled ? "" : Icons.lock
        }

        // everything below hints that the clock is off, but stays usable
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12

            SectionHead {
                title: "Preview"
                detail: pg.monitors.length > 1 ? "" : "as on " + (pg.monitors[0] ? pg.monitors[0].name : "this monitor")
                Layout.topMargin: 6
            }
            MonitorChooser {
                objectName: "deskclock-monitors"
                subtitleFor: s => !DeskClockPrefs.enabled || DeskClockPrefs.shownOn(s) ? "" : "no clock"
            }
            DeskClockPreview {
                id: preview
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight      // 16:9
                screen: Monitors.selected
            }

        }

        // below the preview: dimmed while the clock is off (a hint only, everything stays usable)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            opacity: DeskClockPrefs.enabled ? 1 : Theme.disabledOpacity
            Behavior on opacity { NumberAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }

            SectionHead { title: "Look"; Layout.topMargin: 6 }
            ChoiceRow {
                title: "Size"
                titleWidth: pg.titleW
                values: Presets.deskSize.map(p => p.id)
                labels: Presets.deskSize.map(p => p.name)
                objectNames: Presets.deskSize.map(p => "desk-size-" + p.id)
                current: Presets.deskSizeCurrent
                hint: Presets.deskSizeCurrent === "custom" ? pg.pct(DeskClockPrefs.size) : ""
                onPicked: v => Presets.applyDeskSize(v)
            }
            SettingRow {
                title: "Position"
                titleWidth: pg.titleW
                GridPick {
                    objectName: "desk-grid"
                    px: DeskClockPrefs.posX
                    py: DeskClockPrefs.posY
                    onPicked: (x, y) => { DeskClockPrefs.set("posX", x); DeskClockPrefs.set("posY", y) }
                }
                CustomTag { visible: pg.offGrid }
            }
            PrefSwitch { title: "Date"; titleWidth: pg.titleW; store: DeskClockPrefs; key: "showDate" }

            SectionHead { title: "Clock"; Layout.topMargin: 6 }
            PrefSwitch { title: "Seconds"; titleWidth: pg.titleW; store: DeskClockPrefs; key: "seconds"; info: "Only changed digits redraw" }
            ChoiceRow {
                title: "Morph"
                titleWidth: pg.titleW
                values: Presets.morph.map(p => p.id)
                labels: Presets.morph.map(p => p.name)
                objectNames: Presets.morph.map(p => "desk-morph-" + p.id)
                current: Presets.morphOf(DeskClockPrefs.morph)
                hint: Presets.morphOf(DeskClockPrefs.morph) === "custom" ? pg.times(DeskClockPrefs.morph) : ""
                onPicked: v => DeskClockPrefs.set("morph", Presets.morphValue(v))
            }

            AdvancedFold {
                objectName: "fold-deskclock"
                detail: Object.keys(DeskClockPrefs.data).length > 0 ? Object.keys(DeskClockPrefs.data).length + " changed" : ""

                SectionHead { title: "Look"; InfoTip { text: "The glass itself: Settings > Look & feel." } }
                PrefSlider { id: size; title: "Size"; titleWidth: pg.titleW; store: DeskClockPrefs; key: "size"; format: v => pg.pct(v); extras: Presets.deskSize.map(p => p.v) }
                PrefSlider { id: posX; title: "Horizontal"; titleWidth: pg.titleW; store: DeskClockPrefs; key: "posX"; format: v => pg.pct(v); extras: [0.5] }
                PrefSlider { id: posY; title: "Vertical"; titleWidth: pg.titleW; store: DeskClockPrefs; key: "posY"; format: v => pg.pct(v); extras: [0.5] }
                PrefToggle { titleWidth: pg.titleW; store: DeskClockPrefs; key: "adapt"; label: "Adapt to wallpaper" }
                PrefSlider { id: adaptStrength; title: "Adapt strength"; titleWidth: pg.titleW; store: DeskClockPrefs; key: "adaptStrength"; format: v => pg.pct(v); enabled: DeskClockPrefs.adapt; opacity: enabled ? 1 : Theme.disabledOpacity }

                SectionHead {
                    title: "Clock"
                    InfoTip { text: "Follows the Animations speed." }
                    Btn { objectName: "btn-deskclock-morph"; text: Icons.play + "  Morph"; outerRadius: Theme.radiusPage; inset: 9; implicitHeight: 26; onClicked: preview.demo() }
                }
                PrefToggle { titleWidth: pg.titleW; store: DeskClockPrefs; key: "clock24h"; label: "24-hour clock" }
                PrefSlider { id: morph; title: "Morph time"; titleWidth: pg.titleW; store: DeskClockPrefs; key: "morph"; format: v => pg.times(v); extras: Presets.morph.map(p => p.v) }
            }
        }

        PageReset {
            objectName_: "btn-deskclock-reset"
            dirty: Object.keys(DeskClockPrefs.data).length > 0
            info: "Saved in deskclock.json."
            onReset: DeskClockPrefs.reset()
        }
    }
    readonly property bool offGrid: {
        const s = [0, 0.5, 1]
        return !(s.some(v => Math.abs(DeskClockPrefs.posX - v) <= 0.01) && s.some(v => Math.abs(DeskClockPrefs.posY - v) <= 0.01))
    }
}
