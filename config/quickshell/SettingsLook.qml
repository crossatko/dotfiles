pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell

// Settings -> Look & feel: how the shell looks and moves, as a few named choices (Presets.qml) with live previews and
// almost no words: colour mode (theme.py mode: dark / light from the same wallpaper) and accent source (theme.py accent:
// a standout detail or the dominant colour), glass style (GlassTuneCtl /
// glass.json: the Settings window itself shows the result), motion (Motion / animations.json: popup replay), shape
// (Appearance / appearance.json: a scaled desktop). Each section's Customise… fold holds the detailed controls that
// were the old Glass / Animations / Appearance pages (GlassAdvanced, MotionAdvanced, ShapeAdvanced); a tweak there
// turns the choice into Custom (the saved values stay), a preset click puts a named set back. Old page ids
// appearance / animations / glass open this page (Settings.qml).
Item {
    id: pg
    implicitHeight: col.implicitHeight

    readonly property int titleW: 120
    readonly property bool dragging: glassAdv.dragging || blurSec.dragging || motionAdv.dragging || shapeAdv.dragging
    // the wallpaper behind this window (the monitor Settings is on): what the previews draw their glass / desktop on
    readonly property var screen: { const w = pg.Window.window as Window; return w && w.screen ? Quickshell.screens.find(s => s.name === w.screen.name) ?? null : null }
    readonly property string wallpaper: LockWallpapers.stillFor(screen)
    function count(n, what) { return n + " " + what + (n === 1 ? "" : "s") }

    // ---- colour mode: theme.py re-renders every themed app from the same wallpaper (takes a few seconds) ----
    property string colorWant: ""
    function setColorMode(m) {
        if (colorWant !== "" || m === Theme.mode) return   // one switch at a time
        colorWant = m
        colorGuard.restart()
        // detached, not a Process: closing Settings (page unloaded) must not kill a half-done render
        Quickshell.execDetached(["python3", "-I", Theme.themeDir + "/theme.py", "mode", m])
    }
    Connections { target: Theme; function onModeChanged() { if (Theme.mode === pg.colorWant) pg.colorWant = "" } }
    Timer { id: colorGuard; interval: 20000; onTriggered: pg.colorWant = "" }

    // ---- accent source: theme.py accent standout|dominant (re-render from the cached analysis, like the mode) ----
    property string accentWant: ""
    function setAccentPick(v) {
        if (accentWant !== "" || v === Theme.accentPick) return
        accentWant = v
        accentGuard.restart()
        Quickshell.execDetached(["python3", "-I", Theme.themeDir + "/theme.py", "accent", v])
    }
    Connections { target: Theme; function onAccentPickChanged() { if (Theme.accentPick === pg.accentWant) pg.accentWant = "" } }
    Timer { id: accentGuard; interval: 20000; onTriggered: pg.accentWant = "" }

    // a changed motion replays the demo once the choice rests
    Connections {
        target: Motion
        function onPopupSpeedChanged() { replayLater.restart() }
        function onPopupCurveChanged() { replayLater.restart() }
        function onPopupStyleChanged() { replayLater.restart() }
    }
    Timer { id: replayLater; interval: 350; onTriggered: demo.replay() }

    readonly property bool glassDirty: GlassTuneCtl.changedKeys.length > 0 || GlassSurfaces.totalCount > 0
    readonly property bool motionDirty: Object.keys(Motion.data).length > 0
    readonly property bool shapeDirty: Appearance.keys.some(k => Appearance.overridden(k))

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 12

        // ---------------------------------------------------------------- colour
        SectionHead { title: "Colour" }
        ChoiceRow {
            title: "Mode"
            titleWidth: pg.titleW
            values: ["dark", "light"]
            labels: ["Dark", "Light"]
            objectNames: ["mode-dark", "mode-light"]
            segWidth: 90
            current: pg.colorWant !== "" ? pg.colorWant : Theme.mode
            hint: pg.colorWant !== "" ? "switching…" : ""
            onPicked: v => pg.setColorMode(v)
        }
        ChoiceRow {
            title: "Accent"
            titleWidth: pg.titleW
            values: ["standout", "dominant"]
            labels: ["Standout", "Dominant"]
            objectNames: ["accent-standout", "accent-dominant"]
            segWidth: 90
            current: pg.accentWant !== "" ? pg.accentWant : Theme.accentPick
            hint: pg.accentWant !== "" ? "switching…" : ""
            info: "Standout: a small vivid detail of the wallpaper, when it has one."
            onPicked: v => pg.setAccentPick(v)
        }

        // ---------------------------------------------------------------- glass
        SectionHead {
            title: "Glass"
            Layout.topMargin: 6
            InfoTip { visible: !Theme.glass; icon: Icons.warning; color: Theme.yellow; text: "No compositor glass on this Hyprland: these values only shape the shell's own lenses and lettering." }
        }
        PresetCards {
            id: glassCards
            Layout.fillWidth: true
            objectPrefix: "glass"
            model: Presets.glass
            current: Presets.glassCurrent
            previewHeight: Math.round(cardW * 9 / 16)
            preview: GlassSample { wallpaper: pg.wallpaper }
            onPicked: id => Presets.applyGlass(id)
        }
        AdvancedFold {
            objectName: "fold-glass"
            label: "Customise…"
            detail: GlassTuneCtl.changedKeys.length > 0 ? pg.count(GlassTuneCtl.changedKeys.length, "value") + " changed" : ""
            GlassAdvanced { id: glassAdv; Layout.fillWidth: true; titleW: pg.titleW }
        }
        BlurSection { id: blurSec; Layout.fillWidth: true; titleW: pg.titleW }

        // ---------------------------------------------------------------- motion
        SectionHead { title: "Motion"; Layout.topMargin: 6; detail: Motion.reduced ? "off" : Theme.popupOpenMs + " ms" }
        ChoiceRow {
            title: "Feel"
            titleWidth: pg.titleW
            values: Presets.motion.map(p => p.id)
            labels: Presets.motion.map(p => p.name)
            objectNames: Presets.motion.map(p => "motion-" + p.id)
            segWidth: 76
            current: Presets.motionCurrent
            onPicked: v => Presets.applyMotion(v)
        }
        SettingRow {
            titleWidth: pg.titleW
            MotionDemo { id: demo }
        }
        AdvancedFold {
            objectName: "fold-motion"
            label: "Customise…"
            detail: pg.motionDirty ? pg.count(Object.keys(Motion.data).length, "value") + " set" : ""
            MotionAdvanced { id: motionAdv; Layout.fillWidth: true; titleW: pg.titleW }
        }

        // ---------------------------------------------------------------- shape
        SectionHead { title: "Shape"; Layout.topMargin: 6; detail: Theme.radius + " · " + Theme.gap + " · " + Theme.borderSize + " px" }
        PresetCards {
            Layout.fillWidth: true
            objectPrefix: "shape"
            model: Presets.shape
            current: Presets.shapeCurrent
            previewHeight: Math.round(cardW * 9 / 16)
            preview: ShapeDemo {
                property string preset: "custom"
                readonly property var p: Presets.shape.find(x => x.id === preset) ?? null
                wallpaper: pg.wallpaper
                cornerR: p ? p.v.radius : Theme.radius
                gap: p ? p.v.gap : Theme.gap
                borderPx: p ? p.v.border : Theme.borderSize
                border.width: 0
            }
            onPicked: id => Presets.applyShape(id)
        }
        AdvancedFold {
            objectName: "fold-shape"
            label: "Customise…"
            detail: pg.shapeDirty ? pg.count(Appearance.keys.filter(k => Appearance.overridden(k)).length, "value") + " set" : ""
            ShapeAdvanced { id: shapeAdv; Layout.fillWidth: true; titleW: pg.titleW }
        }

        PageReset {
            dirty: pg.glassDirty || pg.motionDirty || pg.shapeDirty
            info: "Back to the built-in glass, the default motion and the theme's shape (glass.json, animations.json, appearance.json)."
            onReset: { GlassTuneCtl.reset("all"); if (GlassSurfaces.available) GlassSurfaces.reset("all"); Motion.reset(""); Appearance.reset() }
        }
    }
}
