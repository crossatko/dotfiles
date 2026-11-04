pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings > Voice: the three push-to-talk keys (PttPrefs, one PttKeyRow each). No default keys: until one is set a
// Notice asks for them. Customise… holds the per-key click-through switches (the key / click also reaches the window;
// on by default for a mouse button). `titleWidth` lines the rows up with the rest of the page.
ColumnLayout {
    id: sec
    property real titleWidth: 120
    readonly property int foldChanged: PttPrefs.entries.filter(e => PttPrefs.overridden("through:" + e.name)).length

    Layout.fillWidth: true
    spacing: Theme.pad

    SectionHead {
        title: "Push-to-talk"
        InfoTip { text: "Hold a key (or mouse button) to talk, release to type. Type a key such as SUPER + F9 or mouse:276, or press it in the field. Keys Hyprland already uses never reach the field: type those." }
    }

    Notice {
        objectName: "ptt-first-run"
        visible: !PttPrefs.anySet
        Label { text: "No push-to-talk keys yet: choose one for each language."; color: Theme.fgDim; font.pixelSize: Theme.fontSmall; wrapMode: Text.Wrap; Layout.fillWidth: true }
    }

    Repeater {
        model: PttPrefs.entries
        PttKeyRow { id: kr; required property var modelData; entry: kr.modelData; titleWidth: sec.titleWidth }
    }

    AdvancedFold {
        objectName: "fold-ptt"
        detail: sec.foldChanged > 0 ? sec.foldChanged + " changed" : ""
        Repeater {
            model: PttPrefs.entries
            PrefSwitch {
                id: ps
                required property var modelData
                title: ps.modelData.label; titleWidth: sec.titleWidth
                store: PttPrefs; key: "through:" + ps.modelData.name
                hint: "Let the click through"
                info: "The key or click also reaches the window under it (a mouse side button keeps working as back / forward). On by default for mouse buttons; a keyboard key would also type."
            }
        }
    }
}
