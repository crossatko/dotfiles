pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick.Window

// One monitor of the wallpaper engine (engine.qml): a BACKGROUND-layer window (namespace qs-wallpaper, like the main
// shell's WallpaperLayer: no input, no keyboard, no exclusive zone, empty blur region, `no_anim` rule, black where
// nothing covers) holding everything the desktop shows under the windows:
//   paper = the image / still (WallpaperView, the shell's own two-slot cross-fade) and over it the video (EngineVideo),
//   clock = the desktop clock (DeskClockView, Settings > Desktop clock / Monitors), a sibling above `paper` that refracts
//           `paper` itself (its `backdrop`): no copy of the wallpaper, no player sync; a switch / burst / fade under
//           the clock is the same item the desktop shows, so the glass follows it frame by frame.
// The window maps with its first image (WallpaperView.ready): a (re)start shows the still, then the clip fades in.
// PanelWindow is an uncreatable interface type in Quickshell's qmltypes (the real window exists at runtime)
// qmllint disable uncreatable-type
PanelWindow {
    id: win
    required property var modelData
    property var record: null             // this monitor's player record (engine.qml)
    property var saved: null              // { file, pos } from the last run
    property bool held: false             // pause the video (engine: lock, cover, DPMS, IPC)
    property bool clockHidden: false      // the lock is up (under the lock surface)
    property bool clockCovered: false     // hidden before the lock's desktop snapshot (covered by a window)
    property bool bench: false            // bin/engine-bench: overlay layer, no clock
    readonly property string conn: modelData ? String(modelData.name) : ""
    readonly property var monitor: modelData ? Hyprland.monitorFor(modelData) : null
    readonly property EngineVideo video: vid
    readonly property WallpaperView view: wall
    readonly property DeskClockView clock: clockLoader.item as DeskClockView
    readonly property bool clockShown: clockLoader.active
    // what the clock paints, global layout px [x, y, w, h] (the lock's clean rect / cover test), [] = no clock
    readonly property var inkRect: clock && modelData ? [Math.round(modelData.x + clock.ink.x), Math.round(modelData.y + clock.ink.y),
                                                         Math.round(clock.ink.width), Math.round(clock.ink.height)] : []
    signal stationWrite(string path, string text)

    screen: modelData
    visible: wall.ready
    WlrLayershell.layer: win.bench ? WlrLayer.Overlay : WlrLayer.Background
    WlrLayershell.namespace: "qs-wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "black"
    mask: Region {}
    BackgroundEffect.blurRegion: Region {}

    Item {
        id: paper
        // the screen's size, not the window's (the window has none before it maps)
        width: win.modelData ? win.modelData.width : 0
        height: win.modelData ? win.modelData.height : 0
        WallpaperView {
            id: wall
            anchors.fill: parent
            screen: win.modelData
        }
        EngineVideo {
            id: vid
            anchors.fill: parent
            record: win.record
            saved: win.saved
            held: win.held
        }
    }

    Loader {
        id: clockLoader
        active: !win.bench && DeskClockPrefs.shownOn(win.modelData)
        sourceComponent: DeskClockView {
            width: paper.width
            height: paper.height
            backdrop: paper
            backdropReady: wall.hasImage || vid.showing
            wallpaper: LockWallpapers.stillFor(win.modelData)
            screen: win.modelData
            // hidden under the lock: never drawn there, so the buffer the compositor keeps has no clock (it forms again
            // after the unlock, engine.qml); covered = gone before the snapshot (content opacity: the next frame)
            visible: !win.clockHidden
            opacity: win.clockCovered ? 0 : 1
        }
    }

    // ---- lock: the clean backdrop of the clock's ink rect (the wallpaper under it, without the clock), as a PNG the
    // lock surface fades in over its snapshot (Lock.qml / LockClockPatch). Grabbed from `paper` on the next frame.
    function grabClean(file, done) {
        const c = win.clock
        if (!c || !(c.ink.width > 0) || !wall.ready) { done(false); return }
        cleanSrc.sourceRect = c.ink
        cleanBox.width = c.ink.width
        cleanBox.height = c.ink.height
        cleanSrc.live = true
        cleanSrc.scheduleUpdate()
        cleanJob.file = file
        cleanJob.done = done
        cleanJob.frames = 0
        cleanJob.restart()
        // a frame now (an idle window, e.g. a still image, would render the copy only with its next change)
        if (paper.Window.window) paper.Window.window.update()
    }
    function cleanFinish(ok) {
        const d = cleanJob.done
        cleanJob.done = null
        cleanJob.stop()
        cleanSrc.live = false
        if (d) d(ok)
    }
    Timer { id: cleanJob; interval: 250; property var done: null; property string file: ""; property int frames: 0; onTriggered: win.cleanFinish(false) }
    Connections {
        target: cleanJob.done ? paper.Window.window : null
        function onFrameSwapped() {
            if (!cleanJob.done || ++cleanJob.frames !== 1) return
            const r = paper.Screen.devicePixelRatio > 0 ? paper.Screen.devicePixelRatio : 1
            // written under a temporary name, then renamed: the lock loads it the moment it exists (a half-written PNG failed)
            const f = cleanJob.file, part = f.replace(/\.png$/, ".part.png")
            const ok = cleanBox.grabToImage(res => {
                const saved = res.saveToFile(part)
                if (saved) Quickshell.execDetached(["mv", "-f", part, f])
                win.cleanFinish(saved)
            },
                                            Qt.size(Math.round(cleanBox.width * r), Math.round(cleanBox.height * r)))
            if (!ok) win.cleanFinish(false)
        }
    }
    // test hook (engine IPC `debugGrab`): in ONE grab pass, what the clock's glass samples (its backdrop texture) and
    // the same rect of the wallpaper item: <prefix>-glass.png / <prefix>-paper.png (equal = no copy, no lag)
    function debugGrab(prefix) {
        const c = win.clock
        if (!c) return false
        dbgGlass.width = dbgPaper.width = c.texRect.width
        dbgGlass.height = dbgPaper.height = c.texRect.height
        dbgPaperSrc.sourceRect = c.texRect
        dbgGlass.visible = dbgPaper.visible = true
        dbgGlass.grabToImage(r => r.saveToFile(prefix + "-glass.png"))
        dbgPaper.grabToImage(r => { r.saveToFile(prefix + "-paper.png"); dbgGlass.visible = dbgPaper.visible = false })
        return true
    }
    ShaderEffect { id: dbgGlass; visible: false; opacity: 0.001; property var source: win.clock ? win.clock.source : null }
    Item {
        id: dbgPaper
        visible: false
        opacity: 0.001
        ShaderEffectSource { id: dbgPaperSrc; anchors.fill: parent; sourceItem: paper; hideSource: false; live: true }
    }
    Item {
        id: cleanBox
        opacity: 0          // grabbed only
        ShaderEffectSource { id: cleanSrc; anchors.fill: parent; sourceItem: paper; hideSource: false; live: false }
    }
}
