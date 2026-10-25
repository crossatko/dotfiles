pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Entry point. Colors: ~/.config/theme/theme.toml -> Theme.qml (live).
ShellRoot {
    id: root
    // Which screens get a bar and on which edge: BarConfig (Settings -> Bar, monitor cards).
    readonly property var bars: BarConfig.bars
    Binding { target: Popups; property: "bars"; value: root.bars }

    Variants {
        model: Quickshell.screens.filter(s => root.bars[s.name] !== undefined)
        Bar {
            atTop: root.bars[modelData.name] === "top"
        }
    }

    Variants {
        model: Quickshell.screens.filter(s => root.bars[s.name] !== undefined)
        BarReserve {
            atTop: root.bars[modelData.name] === "top"
        }
    }

    Settings { id: settings }
    Launcher { id: launcher }
    Toasts { bars: root.bars }
    Osd { id: osd; bars: root.bars }
    BtNotifier {}

    // one popup host per screen; Popups.* says which is open
    Variants {
        model: Quickshell.screens
        PopupHost {}
    }

    // click-away on the other monitors: closes whatever popup / launcher / Settings / tray menu is open
    Variants {
        model: Quickshell.screens
        ClickCatcher {}
    }


    // qs ipc call popup toggle center|notif|net|bt|cal|media   (focused monitor)
    // No chip to measure: hang it under the right end of the bar, where the bell chip is (same measure
    // as Bar.pop(): screen edge -> bar window (Theme.barGap) -> right section (Theme.barPad); docked = 8).
    IpcHandler {
        target: "popup"
        function toggle(name: string): void {
            Popups.toggle(name, Popups.focusedName())
        }
        // a named monitor instead of the focused one (tests; focus may follow the mouse back)
        function toggleOn(name: string, screen: string): void {
            Popups.toggle(name, screen)
        }
        function close(): void { Popups.close() }
        function esc(): void { Popups.esc() }
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

    // qs ipc call settings toggle | open | close | page bar|wallpaper|appearance   (focused monitor; "monitors" = bar)
    IpcHandler {
        target: "settings"
        function toggle(): void { settings.toggle() }
        function open(): void { settings.open("") }
        function close(): void { settings.close() }
        function page(name: string): void { settings.open(name) }
    }

    // qs ipc call picker toggle   (SUPER+T) -> Settings on the Wallpaper & theme page; closes it when already there
    IpcHandler {
        target: "picker"
        function toggle(): void { settings.togglePage("wallpaper") }
    }

    // qs ipc call record menu | close   (SHIFT+Print via hypr/scripts/screenrec-key.sh; menu = toggle)
    // Alias for `launcher section record` (the recording menu is a launcher section now).
    IpcHandler {
        target: "record"
        function menu(): void { launcher.openSection("record") }
        function close(): void { if (launcher.shown && launcher.section === "record") launcher.close() }
    }

    // qs ipc call screenshot menu | close   (CTRL+Print via hypr/scripts/screenshot-key.sh; menu = toggle)
    // Alias for `launcher section screenshot`.
    IpcHandler {
        target: "screenshot"
        function menu(): void { launcher.openSection("screenshot") }
        function close(): void { if (launcher.shown && launcher.section === "screenshot") launcher.close() }
    }

    // qs ipc call launcher toggle | show | hide | query <text> | section <name>   (Raycast-style launcher, Launcher.qml)
    IpcHandler {
        target: "launcher"
        function toggle(): void { launcher.toggle() }
        function show(): void { launcher.open() }
        function hide(): void { launcher.close() }
        function query(q: string): void { launcher.openWith(q) }   // open prefilled, e.g. "v " = clipboard history
        function section(name: string): void { launcher.openSection(name) }   // open inside a section: sound-output | sound-input | power | twitch | screenshot | record | network | bluetooth | jellyfin | tailscale | mullvad | vms
    }
}
