pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Which bar popup (notification center, network, bluetooth, calendar, media) is open,
// on which screen, and the screen x of the chip it hangs from. One at a time.
// Also the registry for the other click-away things (launcher, Settings window, tray menus):
// only one of all of them is open at once, and ClickCatcher closes it on a click on any other monitor.
Singleton {
    id: root
    property string name: ""
    property string screen: ""
    // x of the opening chip's centre in SCREEN coordinates (PopupHost centres the card on it, clamped to the margin)
    property real center: 1e6
    // set by each Bar: {"DP-5": <Bar>, ...}, so a popup opened without a click (IPC, control-center shortcuts) can find its chip
    property var barObjs: ({})
    // each Bar's current (compact-animated) gap to the screen edge, {"DP-5": 14, ...}; reassigned on change so bindings follow
    property var barGaps: ({})
    function setBarGap(scr, g) { const o = Object.assign({}, barGaps); o[scr] = g; barGaps = o }
    function barGapOf(scr) { return barGaps[scr] ?? Theme.barGap }
    // set by shell.qml: {"DP-5": "bottom", ...}, so a popup knows which edge the bar is on
    property var bars: ({})
    // The bar popups: name -> { source (loaded by PopupHost), width (Theme.popupW = lists and controls; wider cards
    // name their own width) }. A chip opens one with bar.pop(name, chip); "notif" is the notification stack (Toasts),
    // not listed. Adding a popup = the panel file + one entry here + the chip.
    readonly property var panels: ({
        center: { source: "CenterPanel.qml", width: Theme.popupWide },
        net:    { source: "NetPanel.qml",    width: Theme.popupW },
        bt:     { source: "BtPanel.qml",     width: Theme.popupW },
        cal:    { source: "CalPanel.qml",    width: 390 },               // the month grid
        media:  { source: "MediaPanel.qml",  width: Theme.popupW },
        audio:  { source: "AudioPanel.qml",  width: Theme.popupW },
        ha:     { source: "HaPanel.qml",     width: 400 },               // entity cards with controls
        ai:     { source: "AiPanel.qml",     width: 400 },               // profile cards
        vm:     { source: "VmPanel.qml",     width: 440 }                // VM cards with meters
    })

    // the open non-PopupHost thing ("menu", "settings", "tray-...") and its screen
    property string extKind: ""
    property string extScreen: ""

    readonly property bool anyOpen: name !== "" || extKind !== ""
    // the monitor the open thing lives on (its own window handles clicks there)
    readonly property string ownerScreen: name !== "" ? screen : extScreen

    // everything except `except` closes: PopupHost popups via `name`, the rest listen to dismiss()
    signal dismiss(string except)
    // Settings window (Settings.qml) requests: action "open" | "close" | "toggle", page "" = keep the current one
    signal settingsRequest(string action, string page)

    // c = chip centre x on that screen; omitted / negative = look the chip up by name (else the right end)
    function chipCenter(n, scr) {
        const b = barObjs[scr]
        const c = b ? b.chipCenter(n) : -1
        return c >= 0 ? c : 1e6
    }
    function toggle(n, scr, c) {
        if (name === n && screen === scr) { close(); return }
        if (name === "") dismiss("host")
        center = (c === undefined || c < 0) ? chipCenter(n, scr) : c
        name = n; screen = scr
    }
    function close() { name = "" }
    // Esc arrives from a Hyprland keybind (hypr/hyprland/binds.lua, `qs ipc call popup esc`) because the popup
    // surface has no keyboard focus right after opening. A field that handled that same Esc itself (Wi-Fi password)
    // stamps escAt so the popup stays open.
    property double escAt: 0
    function esc() { if (Date.now() - escAt > 400) close() }
    function closeAll() { name = ""; dismiss("") }
    function edgeOf(scr) { return bars[scr] || "bottom" }
    // the focused monitor (where keybind-opened things appear): its name ("" if unknown) / its screen (else the first)
    function focusedName() { return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "" }
    function focusedScreen() {
        const n = focusedName()
        return Quickshell.screens.find(s => s.name === n) || Quickshell.screens[0]
    }

    function opened(kind, scr) {
        name = ""
        dismiss(kind)
        extKind = kind; extScreen = scr || ""
    }
    function closed(kind) {
        if (extKind === kind) { extKind = ""; extScreen = "" }
    }
}
