pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

// Desktop clock (opt-in, Settings > Desktop clock, DeskClockPrefs): one small window per monitor on the BOTTOM layer,
// right above the wallpaper and under every window, so what lies behind it is always the wallpaper and the glass can
// refract the wallpaper image itself (DeskClockView). Monitors: DeskClockPrefs.shownOn (enabled, not hidden there).
// The window is only the clock's area (DeskClockView.area), no input, no keyboard, and declares no blur region: the
// compositor's blur / glass would draw a pane around the lettering.
// Reveal: the lock clock's (GlassReveal) when a window is created (shell start, enabled in Settings, a monitor
// appears) and after an unlock (see `hidden`); not on minute changes (they morph, GlassText), video bursts or workspace
// switches.
// What it refracts: a play-once video wallpaper's own clip, in step with the desktop player (DeskClockVideo, moving during
// a burst), else the still / image hyprpaper shows (LockWallpapers.stillFor). Idle cost: no timers, file watches only.
// Stacking: mpvpaper is on the bottom layer too (-l bottom); the layer rule `order = -1` for qs-deskclock in
// hypr/hyprland/rules.lua keeps the clock above it whichever maps last.
// PanelWindow is an uncreatable interface type in Quickshell's qmltypes (the real window exists at runtime)
// qmllint disable uncreatable-type
Scope {
    id: root
    // Lock (shell.qml wires it to Lock): a clock stays on screen and in the desktop snapshot; the lock surface fades it
    // out by laying `patches` (the clean backdrop of its rect, grabClean() at the lock request) over the snapshot, so the
    // unlock ring opens onto a desktop without the clock. `hidden` once the lock is up (under the lock surface); a clock
    // in `hiddenOn` (covered by a window / popup: the patch would paint over it) hides before the snapshot instead
    // (Lock.snapHideS). When the unlock is done (Lock.unlocked) they show again and the clock forms, its first digit at
    // once (the ring was the pause). The window renders its first frame a moment after the unlock; the reveal starts
    // from nothing then. `hidden` unmaps the windows (under the lock), `hiddenOn` = content opacity 0 (see below).
    property bool hidden: false
    property var hiddenOn: []           // connectors
    // the wallpaper engine owns the clock (theme.toml wallpaper_backend "engine": engine.qml draws it with the wallpaper)
    property bool disabled: false
    // connector -> { result (ItemGrabResult; its url is the image), x, y, w, h (screen px) }; null = the grab failed
    property var patches: ({})
    property int grabGen: 0
    signal grab()
    function grabClean() { grabGen += 1; patches = ({}); grab() }
    function dropPatches() { grabGen += 1; patches = ({}) }
    // connector -> [x, y, w, h]: what each clock paints (DeskClockView.ink), global layout px (bin/lock-clock-cover)
    readonly property var inkRects: {
        const m = {}
        for (const w of clocks.instances) if (w && w.conn !== "") m[w.conn] = w.inkRect
        return m
    }
    // connectors that show a clock
    readonly property var shownOn: root.disabled ? [] : Quickshell.screens.filter(s => DeskClockPrefs.shownOn(s)).map(s => s.name)
    // delay (ms): until the first digit starts
    function formAll(delay) { formed(delay) }
    signal formed(int delay)
    Variants {
        id: clocks
        model: root.disabled ? [] : Quickshell.screens.filter(s => DeskClockPrefs.shownOn(s))
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            // locked (under the lock surface): unmapped. Hiding by content opacity alone left the clock in the window's
            // last committed buffer (no frame callbacks under the lock: the opacity-0 frame was never presented while
            // the clock redraws every frame, e.g. over a video), and that old clock showed for a moment after the unlock.
            // The unmap / fade-out happens under the lock; the new surface after the unlock starts empty (the reveal).
            visible: !root.hidden
            readonly property string conn: modelData ? modelData.name : ""
            readonly property var inkRect: modelData ? [Math.round(modelData.x + view.ink.x), Math.round(modelData.y + view.ink.y),
                                                        Math.round(view.ink.width), Math.round(view.ink.height)] : []
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "qs-deskclock"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true }
            // qmllint disable missing-property
            margins { top: Math.round(view.area.y); left: Math.round(view.area.x) }
            // qmllint enable missing-property
            implicitWidth: Math.max(1, Math.ceil(view.area.width))
            implicitHeight: Math.max(1, Math.ceil(view.area.height))
            color: "transparent"
            mask: Region {}
            BackgroundEffect.blurRegion: Region {}

            DeskClockView {
                id: view
                x: -Math.round(view.area.x); y: -Math.round(view.area.y)
                width: win.modelData ? win.modelData.width : 0
                height: win.modelData ? win.modelData.height : 0
                wallpaper: LockWallpapers.stillFor(win.modelData)
                connector: win.conn
                screen: win.modelData
                // hidden before the snapshot (a covered clock) by its content, not by unmapping: an unmapped layer fades
                // out on the visible desktop (Hyprland's layer animation); this is gone in the next frame
                opacity: root.hidden || root.hiddenOn.indexOf(win.conn) >= 0 ? 0 : 1
            }
            Connections {
                target: root
                function onFormed(delay) { view.form(delay) }
                function onGrab() {
                    const conn = win.conn, a = view.ink, gen = root.grabGen
                    view.grabClean(res => {
                        if (gen !== root.grabGen) return
                        const m = Object.assign({}, root.patches)
                        m[conn] = res ? { result: res, x: a.x, y: a.y, w: a.width, h: a.height } : null
                        root.patches = m
                    })
                }
            }
        }
    }
}
