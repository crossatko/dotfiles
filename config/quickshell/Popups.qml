pragma Singleton
import QtQuick
import Quickshell

// Which bar popup (notification center, network, bluetooth, calendar, media) is open,
// on which screen, and how far from the right screen edge it hangs. One at a time.
// Also the registry for the other click-away things (launcher, Settings window, tray menus):
// only one of all of them is open at once, and ClickCatcher closes it on a click on any other monitor.
Singleton {
    id: root
    property string name: ""
    property string screen: ""
    property real right: 8
    // set by shell.qml: {"DP-5": "bottom", ...}, so a popup knows which edge the bar is on
    property var bars: ({})

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

    function toggle(n, scr, r) {
        if (name === n && screen === scr) { close(); return }
        if (name === "") dismiss("host")
        name = n; screen = scr; right = r
    }
    function close() { name = "" }
    function closeAll() { name = ""; dismiss("") }
    function edgeOf(scr) { return bars[scr] || "bottom" }

    function opened(kind, scr) {
        name = ""
        dismiss(kind)
        extKind = kind; extScreen = scr || ""
    }
    function closed(kind) {
        if (extKind === kind) { extKind = ""; extScreen = "" }
    }
}
