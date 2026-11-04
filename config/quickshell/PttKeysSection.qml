pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings > Voice: the push-to-talk keys (PttPrefs, one PttKeyRow each): Auto (always there) and per selected language
// its own key and its "to English" key, folded when there are many (AdvancedFold). No default keys: until one is set a
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
        InfoTip { text: "Auto detects the language when you start talking (among your languages, when there are any). Hold a key (or mouse button) to talk, release to type. Type a key such as SUPER + F9 or mouse:276, or press it in the field. Keys Hyprland already uses never reach the field: type those." }
    }

    Notice {
        objectName: "ptt-first-run"
        visible: !PttPrefs.anySet
        Label { text: "No push-to-talk keys yet: choose one for Auto or for each language."; color: Theme.fgDim; font.pixelSize: Theme.fontSmall; wrapMode: Text.Wrap; Layout.fillWidth: true }
    }

    AdvancedFold {
        objectName: "fold-ptt-keys"
        label: PttPrefs.entries.length + " keys"
        detail: PttPrefs.entries.filter(e => PttPrefs.keysOf(e.name) !== "").length + " set"
        count: PttPrefs.entries.length
        bodySpacing: Theme.gapRow
        Repeater {
            model: PttPrefs.entries
            PttKeyRow { id: kr; required property var modelData; entry: kr.modelData; titleWidth: sec.titleWidth }
        }
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
