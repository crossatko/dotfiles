pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

// Settings -> Lock screen, built like Settings > Desktop clock: the monitor strip first (MonitorSection, switchable: the
// picked monitor + the lock clock on / off per monitor and "All"; LockPrefs.setClockOn / setAllClock, the same setter as
// Settings > Monitors), a live preview of the picked monitor (LockPreview: the real LockView in preview mode, 16:9; Replay
// plays the lock's opening again, Lock now asks THIS shell for the same lock as SUPER+SHIFT+L), the named choices (Presets.qml: layout
// cards, clock size, seconds, 12 / 24 h, morph, backdrop) and, under Customise…, every LockPrefs key (lock.json). A tweak
// in the fold turns a choice into Custom (the saved values stay). Everything applies live: the preview at once, the real
// lock at once if it is up, else at the next lock. While the picked monitor shows no lock clock the clock sections are
// dimmed (still usable) with an "Off" mark; the backdrop and motion rows are not (they apply there anyway).
Item {
    id: pg
    implicitHeight: col.implicitHeight

    readonly property int titleW: 120
    readonly property bool dragging: dim.dragging || blur.dragging || size.dragging || dots.dragging || morph.dragging
    readonly property bool on: LockPrefs.clockOn(Monitors.selected)
    readonly property real clockOpacity: pg.on ? 1 : Theme.disabledOpacity
    function pct(v) { return Math.round(v * 100) + " %" }
    function times(v) { return v <= 0 ? "instant" : Number(v.toFixed(2)) + "x" }
    // a changed morph time shows itself in the preview once the slider rests
    Connections { target: LockPrefs; function onMorphChanged() { morphShow.restart() } }
    Timer { id: morphShow; interval: 400; onTriggered: preview.demo() }

    // a block the picked monitor's missing lock clock dims (a hint only, everything stays usable)
    component ClockBlock: ColumnLayout {
        Layout.fillWidth: true
        spacing: 12
        opacity: pg.clockOpacity
        Behavior on opacity { NumberAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 12

        // ---------------------------------------------------------------- the monitor strip: picked monitor + lock clock per monitor
        MonitorSection {
            objectName: "lock-monitors"
            showSingle: true
            switchable: true
            onFor: s => LockPrefs.clockOn(s)
            switchTipFor: s => (LockPrefs.clockOn(s) ? "Hide clock on " : "Show clock on ") + Monitors.title(s)
            allOn: LockPrefs.clockAll
            allIcon: Icons.lock
            onSwitched: (s, want) => LockPrefs.setClockOn(Appearance.monitorKey(s), want)
            onAllSwitched: want => LockPrefs.setAllClock(want)
        }

        // ---------------------------------------------------------------- preview of the picked monitor
        SectionHead {
            title: "Preview"
            Layout.topMargin: 6
            OffMark { visible: !pg.on }
            Btn { objectName: "btn-lock-replay"; glyph: Icons.retry; text: "Replay"; outerRadius: Theme.radiusPage; inset: 9; implicitHeight: 26; onClicked: preview.replay() }
            Btn {
                objectName: "btn-lock-now"
                glyph: Icons.lock
                text: "Lock now"
                outerRadius: Theme.radiusPage; inset: 9; implicitHeight: 26
                onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellDir, "ipc", "call", "lock", "lock"])
            }
        }
        LockPreview {
            id: preview
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight      // 16:9
            screen: Monitors.selected
        }

        // ---------------------------------------------------------------- primary choices
        SectionHead { title: "Layout"; Layout.topMargin: 6; OffMark { visible: !pg.on } }
        ClockBlock {
            PresetCards {
                Layout.fillWidth: true
                objectPrefix: "lock-layout"
                model: Presets.lockLayout
                current: Presets.lockLayoutCurrent
                previewHeight: Math.round(cardW * 9 / 16)
                preview: LockSketch {}
                onPicked: id => Presets.applyLockLayout(id)
            }
        }

        SectionHead { title: "Clock"; Layout.topMargin: 6; OffMark { visible: !pg.on } }
        ClockBlock {
            ChoiceRow {
                title: "Size"
                titleWidth: pg.titleW
                values: Presets.lockSize.map(p => p.id)
                labels: Presets.lockSize.map(p => p.name)
                objectNames: Presets.lockSize.map(p => "lock-size-" + p.id)
                current: Presets.lockSizeCurrent
                hint: Presets.lockSizeCurrent === "custom" ? pg.pct(LockPrefs.clockSize) : ""
                onPicked: v => Presets.applyLockSize(v)
            }
            PrefSwitch { title: "Seconds"; titleWidth: pg.titleW; store: LockPrefs; key: "seconds"; info: "Only changed digits redraw" }
            ChoiceRow {
                title: "Time"
                titleWidth: pg.titleW
                values: [true, false]
                labels: ["24 h", "12 h"]
                objectNames: ["lock-time-24", "lock-time-12"]
                current: LockPrefs.clock24h
                onPicked: v => LockPrefs.set("clock24h", v)
            }
            ChoiceRow {
                title: "Morph"
                titleWidth: pg.titleW
                values: Presets.morph.map(p => p.id)
                labels: Presets.morph.map(p => p.name)
                objectNames: Presets.morph.map(p => "lock-morph-" + p.id)
                current: Presets.morphOf(LockPrefs.morph)
                hint: Presets.morphOf(LockPrefs.morph) === "custom" ? pg.times(LockPrefs.morph) : ""
                onPicked: v => LockPrefs.set("morph", Presets.morphValue(v))
            }
        }

        SectionHead { title: "Look"; Layout.topMargin: 6 }
        ChoiceRow {
            title: "Backdrop"
            titleWidth: pg.titleW
            values: Presets.lockBackdrop.map(p => p.id)
            labels: Presets.lockBackdrop.map(p => p.name)
            objectNames: Presets.lockBackdrop.map(p => "lock-backdrop-" + p.id)
            current: Presets.lockBackdropCurrent
            hint: Presets.lockBackdropCurrent === "custom" ? pg.pct(LockPrefs.dim) + " · " + LockPrefs.blur + " px" : ""
            onPicked: v => Presets.applyLockBackdrop(v)
        }

        // ---------------------------------------------------------------- everything else
        AdvancedFold {
            objectName: "fold-lock"
            detail: Object.keys(LockPrefs.data).length > 0 ? Object.keys(LockPrefs.data).length + " changed" : ""

            SectionHead {
                title: "Clock"
                OffMark { visible: !pg.on }
                InfoTip { text: "Morph follows the Animations speed." }
                Btn { objectName: "btn-lock-morph"; glyph: Icons.play; text: "Morph"; outerRadius: Theme.radiusPage; inset: 9; implicitHeight: 26; onClicked: preview.demo() }
            }
            ClockBlock {
                PrefSlider { id: size; title: "Size"; titleWidth: pg.titleW; store: LockPrefs; key: "clockSize"; format: v => pg.pct(v); extras: Presets.lockSize.map(p => p.v) }
                PrefSlider { id: morph; title: "Morph time"; titleWidth: pg.titleW; store: LockPrefs; key: "morph"; format: v => pg.times(v); extras: Presets.morph.map(p => p.v) }
                PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "showDate"; label: "Date" }
                PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "mediaCard"; label: "Playback card" }
                PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "clockReveal"; label: "Reveal" }
            }

            SectionHead { title: "Look" }
            PrefSlider { id: dim; title: "Dim"; titleWidth: pg.titleW; store: LockPrefs; key: "dim"; format: v => pg.pct(v); extras: Presets.lockBackdrop.map(p => p.v.dim) }
            PrefSlider { id: blur; title: "Blur"; titleWidth: pg.titleW; store: LockPrefs; key: "blur"; format: v => v + " px"; extras: Presets.lockBackdrop.map(p => p.v.blur) }
            PrefSlider { id: dots; title: "Dot size"; titleWidth: pg.titleW; store: LockPrefs; key: "dotSize"; format: v => (v * 100).toFixed(1) + " %" }

            SectionHead { title: "Motion"; InfoTip { text: "At the Animations speed; none = instant." } }
            PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "snapshot"; label: "Desktop snapshot"; hint: "ring transitions" }
            PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "unlockRing"; label: "Unlock ring" }

            SectionHead { title: "Video wallpaper"; InfoTip { text: "Play-once videos play a burst." } }
            PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "burstOnLock"; label: "On lock" }
            PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "burstOnType"; label: "While typing" }
            PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "burstOnSubmit"; label: "On Enter" }
        }

        PageReset {
            objectName_: "btn-lock-reset"
            dirty: Object.keys(LockPrefs.data).length > 0
            info: "Saved in lock.json."
            onReset: LockPrefs.reset()
        }
    }
}
