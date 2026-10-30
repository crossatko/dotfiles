import QtQuick
import Quickshell

// Source: the user's existing actions (same commands the key binds use, see hypr/hyprland/binds.lua).
// Commands that open another popup (menus on qs-* layers) wait a moment so the launcher is gone first.
// Sound output / input, Power, Twitch, Screenshot and Record are launcher sections now (SectionsSource.qml).
QtObject {
    id: src

    readonly property var items: [
        cmd("sleep",       "Sleep",            "Suspend the computer", "\ue0d4", ["suspend"],   // moon
            "~/.config/hypr/scripts/suspend.sh"),
        cmd("shutdown",    "Shut down",        "Power off", "\ue126", ["poweroff"],   // power-off
            "hyprshutdown -t 'Shutting down...' --post-cmd 'shutdown now'"),
        cmd("reboot",      "Restart",          "Reboot the computer", "\ue0dc", ["reboot"],   // rotate-right
            "hyprshutdown -t 'Restarting...' --post-cmd 'reboot'"),
        cmd("exit",        "Exit Hyprland",    "End the session", "\ue0ce", ["logout", "quit"],   // arrow-right-from-bracket
            "hyprshutdown"),
        cmd("wallpaper",   "Wallpaper and theme", "Pick a wallpaper, the theme follows", "\ue0c8", ["theme", "colors", "background", "picker"],   // image
            "sleep 0.15; qs ipc call picker toggle")
    ]

    function cmd(id, name, subtitle, glyph, keywords, command) {
        return { id: "cmd:" + id, name: name, subtitle: subtitle, keywords: keywords,
                 kind: "command", source: "Command", glyph: glyph, command: command }
    }

    function run(item) {
        if (item.kind !== "command") return false
        Quickshell.execDetached(["sh", "-c", item.command])
        return true
    }
}
