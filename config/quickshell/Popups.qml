pragma Singleton
import QtQuick
import Quickshell

// Which bar popup (notification center, network, bluetooth, calendar, media) is open,
// on which screen, and how far from the right screen edge it hangs. One at a time.
Singleton {
    id: root
    property string name: ""
    property string screen: ""
    property real right: 8
    // set by shell.qml: {"DP-5": "bottom", ...}, so a popup knows which edge the bar is on
    property var bars: ({})

    function toggle(n, scr, r) {
        if (name === n && screen === scr) { close(); return }
        name = n; screen = scr; right = r
    }
    function close() { name = "" }
    function edgeOf(scr) { return bars[scr] || "bottom" }
}
