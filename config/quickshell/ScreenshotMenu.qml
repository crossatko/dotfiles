import QtQuick
import QtQuick.Layouts
import Quickshell

// Screenshot mode picker (CTRL+Print; see hyprland/binds.lua and hypr/scripts/screenshot-key.sh).
// A small floating window (ModalWindow, title qs-screenshot) with Region / Window / Screen tiles; SUPER+LMB drags it.
// Keys: 1/2/3 take a shot, arrows / Tab move, Enter/Space activates, Escape closes.
//   qs ipc call screenshot menu | close
// Choosing a mode hides the window first and starts screenshot.sh only after `launchDelay`, so the popup is
// unmapped before slurp grabs the pointer and is never in the picture. QS_SHOT_SCRIPT overrides the script
// (isolated tests only).
ModalWindow {
    id: win

    kind: "screenshot"
    heading: "Screenshot"
    icon: ""                    // camera

    readonly property string script: Quickshell.env("QS_SHOT_SCRIPT")
        || (Quickshell.env("HOME") + "/.config/hypr/scripts/screenshot.sh")
    readonly property int launchDelay: 200

    readonly property var modes: [
        { id: "region", title: "Region", sub: "Drag a rectangle", icon: "" },   // vector-square
        { id: "window", title: "Window", sub: "Click a window",   icon: "" },   // window-maximize
        { id: "output", title: "Screen", sub: "Whole monitor",    icon: "" }    // display
    ]

    property int cur: 0               // highlighted mode tile
    property int lastMode: 0          // the menu reopens on the last used mode
    property string pendingMode: ""

    onOpening: cur = lastMode
    onKeyPressed: ev => { if (win.handleKey(ev.key)) ev.accepted = true }

    // close first, start the recorder once the window is gone
    function choose(i) {
        if (!shown || i < 0 || i >= modes.length) return
        lastMode = i
        pendingMode = modes[i].id
        shown = false
        launch.restart()
    }

    function activate() { choose(cur) }

    // keyboard (also what an isolated test drives); returns false for keys it doesn't use
    function handleKey(k) {
        if (k === Qt.Key_Escape) close()
        else if (k === Qt.Key_1 || k === Qt.Key_2 || k === Qt.Key_3) choose(k - Qt.Key_1)
        else if (k === Qt.Key_Left) cur = Math.max(0, cur - 1)
        else if (k === Qt.Key_Right) cur = Math.min(2, cur + 1)
        else if (k === Qt.Key_Tab) cur = (cur + 1) % 3
        else if (k === Qt.Key_Backtab) cur = (cur + 2) % 3
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) activate()
        else return false
        return true
    }

    Timer {
        id: launch
        interval: win.launchDelay
        onTriggered: {
            if (win.pendingMode === "") return
            Quickshell.execDetached([win.script, win.pendingMode])
            win.pendingMode = ""
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        Repeater {
            model: win.modes
            ModeTile {
                required property var modelData
                required property int index
                icon: modelData.icon
                title: modelData.title
                sub: modelData.sub
                badge: index + 1
                sel: win.cur === index
                onHovered: win.cur = index
                onClicked: win.choose(index)
            }
        }
    }

    Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: "1 2 3 capture · ←→ Enter · Esc close"
        color: Theme.muted
        font.pixelSize: Theme.fontCaption
    }
}
