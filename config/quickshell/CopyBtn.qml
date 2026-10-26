import QtQuick
import Quickshell

// Btn that copies `value` with wl-copy and shows "Copied" for 1.2 s.
Btn {
    id: cb
    property string label: "Copy"
    property string value: ""
    property bool copied: false
    text: copied ? "Copied" : label
    active: copied
    onClicked: {
        if (!value) return
        Quickshell.execDetached(["wl-copy", "--", value])
        copied = true
        reset.restart()
    }
    Timer { id: reset; interval: 1200; onTriggered: cb.copied = false }
}
