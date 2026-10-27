pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

// Settings -> Lock screen: a live preview (LockPreview: the real LockView in preview mode, scaled), a few named
// choices (Presets.qml: layout, clock size, backdrop, morph; seconds and 12 / 24 h as plain switches) and, under
// Customise…, every LockPrefs key (lock.json) as before. A tweak in the fold turns a choice into Custom (the saved
// values stay); a preset click puts a named set back. Everything applies live: the preview at once, the real lock
// at once if it is up, else at the next lock. "Lock now" asks THIS shell for the same lock as SUPER+SHIFT+L
// (`qs -p <its config> ipc call lock lock`).
Item {
    id: pg
    implicitHeight: col.implicitHeight

    readonly property int titleW: 120
    readonly property bool dragging: dim.dragging || blur.dragging || size.dragging || dots.dragging || morph.dragging
    readonly property var monitors: Monitors.ordered.filter(s => s.width > 0)
    function pct(v) { return Math.round(v * 100) + " %" }
    function times(v) { return v <= 0 ? "instant" : Number(v.toFixed(2)) + "x" }
    // a changed morph time shows itself in the preview once the slider rests
    Connections { target: LockPrefs; function onMorphChanged() { morphShow.restart() } }
    Timer { id: morphShow; interval: 400; onTriggered: preview.demo() }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 12


        SectionHead {
            title: "Preview"
            detail: pg.monitors.length > 1 ? "" : "as on " + (pg.monitors[0] ? pg.monitors[0].name : "this monitor")
            Btn { objectName: "btn-lock-replay"; text: Icons.retry + "  Replay"; outerRadius: Theme.radiusPage; inset: 9; implicitHeight: 26; onClicked: preview.replay() }
            Btn {
                objectName: "btn-lock-now"
                text: Icons.lock + "  Lock now"
                outerRadius: Theme.radiusPage; inset: 9; implicitHeight: 26
                onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellDir, "ipc", "call", "lock", "lock"])
            }
        }
        MonitorChooser {
            objectName: "lock-monitors"
            subtitleFor: s => LockPrefs.clockOn(s) ? "" : "no clock"
        }
        LockPreview {
            id: preview
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight      // 16:9
            screen: Monitors.selected
        }

        // ---------------------------------------------------------------- primary choices
        SectionHead { title: "Layout"; Layout.topMargin: 6 }
        PresetCards {
            Layout.fillWidth: true
            objectPrefix: "lock-layout"
            model: Presets.lockLayout
            current: Presets.lockLayoutCurrent
            previewHeight: Math.round(cardW * 9 / 16)
            preview: LockSketch {}
            onPicked: id => Presets.applyLockLayout(id)
        }

        SectionHead { title: "Look"; Layout.topMargin: 6 }
        ChoiceRow {
            title: "Clock size"
            titleWidth: pg.titleW
            values: Presets.lockSize.map(p => p.id)
            labels: Presets.lockSize.map(p => p.name)
            objectNames: Presets.lockSize.map(p => "lock-size-" + p.id)
            current: Presets.lockSizeCurrent
            hint: Presets.lockSizeCurrent === "custom" ? pg.pct(LockPrefs.clockSize) : ""
            onPicked: v => Presets.applyLockSize(v)
        }
        ChoiceRow {
            title: "Backdrop"
            titleWidth: pg.titleW
            values: Presets.lockBackdrop.map(p => p.id)
            labels: Presets.lockBackdrop.map(p => p.name)
            objectNames: Presets.lockBackdrop.map(p => "lock-backdrop-" + p.id)
            current: Presets.lockBackdropCurrent
            hint: Presets.lockBackdropCurrent === "custom" ? pg.pct(LockPrefs.dim) + " dim, " + LockPrefs.blur + " px" : ""
            onPicked: v => Presets.applyLockBackdrop(v)
        }

        SectionHead { title: "Clock"; Layout.topMargin: 6 }
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

        // ---------------------------------------------------------------- everything else
        AdvancedFold {
            objectName: "fold-lock"
            detail: Object.keys(LockPrefs.data).length > 0 ? Object.keys(LockPrefs.data).length + " changed" : ""

            SectionHead { title: "Look" }
            PrefSlider { id: dim; title: "Wallpaper dim"; titleWidth: pg.titleW; store: LockPrefs; key: "dim"; format: v => pg.pct(v); extras: Presets.lockBackdrop.map(p => p.v.dim) }
            PrefSlider { id: blur; title: "Blur"; titleWidth: pg.titleW; store: LockPrefs; key: "blur"; format: v => v + " px"; extras: Presets.lockBackdrop.map(p => p.v.blur) }
            PrefSlider { id: size; title: "Clock size"; titleWidth: pg.titleW; store: LockPrefs; key: "clockSize"; format: v => pg.pct(v); extras: Presets.lockSize.map(p => p.v) }
            PrefSlider { id: dots; title: "Dot size"; titleWidth: pg.titleW; store: LockPrefs; key: "dotSize"; format: v => (v * 100).toFixed(1) + " %" }

            SectionHead {
                title: "Clock"
                InfoTip { text: "Follows the Animations speed." }
                Btn { objectName: "btn-lock-morph"; text: Icons.play + "  Morph"; outerRadius: Theme.radiusPage; inset: 9; implicitHeight: 26; onClicked: preview.demo() }
            }
            PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "showDate"; label: "Show the date" }
            PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "mediaCard"; label: "Playback card"; hint: "under the dots" }
            PrefSlider { id: morph; title: "Morph time"; titleWidth: pg.titleW; store: LockPrefs; key: "morph"; format: v => pg.times(v); extras: Presets.morph.map(p => p.v) }

            SectionHead { title: "Motion"; InfoTip { text: "At the Animations speed; none = instant." } }
            PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "clockReveal"; label: "Clock reveal" }
            PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "snapshot"; label: "Desktop snapshot"; hint: "for ring transitions" }
            PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "unlockRing"; label: "Unlock ring" }

            SectionHead { title: "Video wallpaper"; InfoTip { text: "Play-once videos play a burst." } }
            PrefToggle { titleWidth: pg.titleW; store: LockPrefs; key: "burstOnLock"; label: "When the lock comes up" }
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
