import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Entry point. Colors: ~/.config/theme/theme.toml -> Theme.qml (live).
ShellRoot {
    id: root
    // Which screens get a bar and on which edge: BarConfig (control center -> panel settings).
    readonly property var bars: BarConfig.bars
    Binding { target: Popups; property: "bars"; value: root.bars }

    Variants {
        model: Quickshell.screens.filter(s => bars[s.name] !== undefined)
        Bar {
            atTop: bars[modelData.name] === "top"
        }
    }

    Variants {
        model: Quickshell.screens.filter(s => bars[s.name] !== undefined)
        BarReserve {
            atTop: bars[modelData.name] === "top"
        }
    }

    Picker { id: picker }
    Menu { id: menu }
    Toasts { bars: root.bars }
    Osd { id: osd; bars: root.bars }

    // one popup host per screen; Popups.* says which is open
    Variants {
        model: Quickshell.screens
        PopupHost {}
    }

    // click-away on the other monitors: closes whatever popup / launcher / picker / tray menu is open
    Variants {
        model: Quickshell.screens
        ClickCatcher {}
    }


    // qs ipc call popup toggle center|net|bt|cal|media   (focused monitor)
    IpcHandler {
        target: "popup"
        function toggle(name: string): void {
            const m = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
            Popups.toggle(name, m, 8)
        }
        function close(): void { Popups.close() }
    }

    // qs ipc call osd brightness   (shows the focused display's brightness)
    IpcHandler {
        target: "osd"
        function brightness(): void { osd.brightness() }
    }

    // qs ipc call brightness step 5 | step -5 | set 60   (brightness keys; focused monitor, DDC/CI or backlight)
    IpcHandler {
        target: "brightness"
        function step(delta: int): void { Brightness.step(delta) }
        function set(percent: int): void { const n = Brightness.focused(); if (n) Brightness.set(n, percent) }
        function get(): string { return Brightness.displays.map(n => n + " " + Brightness.percentOf(n)).join("\n") }
        function refresh(): void { Brightness.refresh() }
    }
    // detect the displays once at start, so the control center's slider section doesn't pop in on first open
    Timer { interval: 4000; running: true; onTriggered: Brightness.refresh() }

    // qs ipc call notif dnd | clear
    IpcHandler {
        target: "notif"
        function dnd(): void { Notifs.setDnd(!Notifs.dnd) }
        function clear(): void { Notifs.clearAll() }
    }

    // qs ipc call picker toggle
    IpcHandler {
        target: "picker"
        function toggle(): void { picker.toggle() }
    }

    // qs ipc call menu drun            (SUPER+D)
    // ... | qmenu --prompt-text 'X: '  (power / sound-output menus; see bin/qmenu)
    IpcHandler {
        target: "menu"
        function drun(): void { menu.openDrun() }
        function dmenu(prompt: string, dir: string): void { menu.openDmenu(prompt, dir) }
        function close(): void { menu.close() }   // cancels the open menu (dmenu callers get exit 1)
    }
}
