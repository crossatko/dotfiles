import QtQuick
import "launcher/js/PttKeys.js" as K

// A FieldBox for one Hyprland key in bind syntax ("SUPER + F9", "mouse:276"): type it, or press it while the field
// has focus. A press with SUPER / CTRL / ALT, or of a key that types nothing (F keys, Pause ...), replaces the text
// with that combo; plain typing edits the text. A mouse button other than the left one pressed on the field captures
// it too (with the modifiers held). `captured(keys)` after a capture. Keys or buttons the compositor already grabs
// (its own binds) never reach the window: those can only be typed.
FieldBox {
    id: kf
    signal captured(string keys)
    function take(k) {
        if (k === "") return false
        kf.text = k
        kf.captured(k)
        return true
    }

    placeholder: "Type or press a key"
    keyFilter: e => K.captures(e.key, e.modifiers, e.text) && kf.take(K.fromQt(e.key, e.modifiers, e.nativeScanCode))

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons & ~Qt.LeftButton
        onPressed: m => { kf.focusField(); kf.take(K.fromMouse(m.button, m.modifiers)) }
    }
}
