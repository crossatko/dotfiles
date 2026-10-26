pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

// Desktop clock (opt-in, Settings > Desktop clock, DeskClockPrefs): one small window per monitor on the BOTTOM layer,
// right above the wallpaper and under every window, so what lies behind it is always the wallpaper and the glass can
// refract the wallpaper image itself (DeskClockView). Monitors: DeskClockPrefs.shownOn (enabled, not hidden there).
// The window is only the clock's area (DeskClockView.area), no input, no keyboard, and declares no blur region: the
// compositor's blur / glass would draw a pane around the lettering.
// What it refracts: a play-once video wallpaper's own clip, in step with the desktop player (DeskClockVideo, moving during
// a burst), else the still / image hyprpaper shows (LockWallpapers.stillFor). Idle cost: no timers, file watches only.
// Stacking: mpvpaper is on the bottom layer too (-l bottom); the layer rule `order = -1` for qs-deskclock in
// hypr/hyprland/rules.lua keeps the clock above it whichever maps last.
// PanelWindow is an uncreatable interface type in Quickshell's qmltypes (the real window exists at runtime)
// qmllint disable uncreatable-type
Scope {
    id: root
    Variants {
        model: Quickshell.screens.filter(s => DeskClockPrefs.shownOn(s))
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            readonly property string conn: modelData ? modelData.name : ""
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
            }
        }
    }
}
