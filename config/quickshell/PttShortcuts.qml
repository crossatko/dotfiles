pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// The three push-to-talk global shortcuts (appid "quickshell", names from PttPrefs.entries: ptt-cs, ptt-en, ptt-cs-en),
// registered with Hyprland from the start (shell.qml references this singleton). Hyprland sends press AND release for
// a `global` bind, keyboard keys and mouse buttons alike; the keys themselves are PttPrefs' (hypr/hyprland/ptt.lua binds
// them). This only reports: pressed(name) / released(name) and `held` (name -> true while down); DictationController
// connects to the signals.
//   qs ipc call pttkeys held          -> the names held right now (comma separated)
Singleton {
    id: root

    signal pressed(string name)
    signal released(string name)
    property var held: ({})
    function isHeld(name) { return held[name] === true }
    property var heldKeys: ({})              // name -> the key it was pressed with
    // a key changed / cleared while held: Hyprland drops the bind and sends no release, so release it here
    Connections {
        target: PttPrefs
        function onDataChanged() {
            for (const n of Object.keys(root.held)) if (PttPrefs.keysOf(n) !== root.heldKeys[n]) root.setHeld(n, false)
        }
    }

    function setHeld(name, down) {
        if (isHeld(name) === down) return
        const h = Object.assign({}, held)
        if (down) h[name] = true
        else delete h[name]
        held = h
        heldKeys = Object.assign({}, heldKeys, { [name]: down ? PttPrefs.keysOf(name) : "" })
        console.info("ptt: " + name + (down ? " pressed" : " released"))
        if (down) pressed(name)
        else released(name)
    }

    Instantiator {
        model: PttPrefs.entries
        delegate: GlobalShortcut {
            required property var modelData
            appid: PttPrefs.appid
            name: modelData.name
            description: modelData.desc
            onPressed: root.setHeld(modelData.name, true)
            onReleased: root.setHeld(modelData.name, false)
        }
    }

    IpcHandler {
        target: "pttkeys"
        function held(): string { return Object.keys(root.held).join(",") }
    }
}
