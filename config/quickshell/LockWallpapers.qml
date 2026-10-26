pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Each monitor's wallpaper still for the lock screen (Lock.qml) and its Settings preview (LockPreview.qml), as the
// desktop has it: theme.py's wallpapers.json maps monitor keys (Appearance.monitorKey) to an image path or a video
// {video, still}; monitors not in it show the primary's (Theme.wallpaper). QS_LOCK_WALLPAPER (tests) overrides every
// monitor; QS_WALLPAPERS_FILE another state file (as SettingsWallpaper.qml).
Singleton {
    id: root
    readonly property string override: Quickshell.env("QS_LOCK_WALLPAPER") || ""
    readonly property string primary: override || Theme.wallpaper.replace(/^~/, Theme.home)
    property var monitors: ({})
    function stillFor(screen) {
        if (override !== "" || !screen) return primary
        const e = monitors[Appearance.monitorKey(screen)]
        const p = typeof e === "string" ? e : e && typeof e.still === "string" ? e.still : ""
        return p !== "" ? p.replace(/^~/, Theme.home) : primary
    }
    FileView {
        path: Quickshell.env("QS_WALLPAPERS_FILE")
              || ((Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/theme/wallpapers.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { const j = JSON.parse(text()); root.monitors = j && j.monitors ? j.monitors : ({}) } catch (e) { root.monitors = ({}) } }
        onLoadFailed: root.monitors = ({})
    }
}
