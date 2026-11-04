pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings -> Diacritics (fix the diacritics of Czech text with a local model, on one key). One self-contained section
// component per topic, stacked in the order both feature pages share (SettingsVoice): key, pill, model, the feature's own
// settings, word lists; adding a topic = one line here (its component takes `titleWidth`) plus its store in the PageReset
// below. All state is DiacriticsPrefs (diacritics.json).
//   DiacriticsKeySection      the key (applied to Hyprland at once)
//   DiacriticsPillSection     the pill: live preview, real text or a generic animation, where it sits (PillSection)
//   DiacriticsModelSection    the model file, idle unload
//   DiacriticsIgnoredSection  window classes where the key does nothing
//   DiacriticsCorrectionsSection  words the model gets wrong (DiacriticsWords, diacritics-words.json)
Item {
    id: pg
    implicitHeight: col.implicitHeight

    readonly property int titleW: 120
    readonly property bool dragging: pill.dragging     // a slider drag: the Settings page must not scroll

    // the conflict check and the key's status read the Hyprland binds PttPrefs keeps fresh while a page watches them
    Component.onCompleted: { PttPrefs.watchers++; PttPrefs.refresh(); DiacriticsPrefs.refreshModels() }
    Component.onDestruction: PttPrefs.watchers--

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Theme.pad

        DiacriticsKeySection { titleWidth: pg.titleW }
        DiacriticsPillSection { id: pill; titleWidth: pg.titleW; Layout.topMargin: 6 }
        DiacriticsModelSection { titleWidth: pg.titleW; Layout.topMargin: 6 }
        DiacriticsIgnoredSection { titleWidth: pg.titleW; Layout.topMargin: 6 }
        DiacriticsCorrectionsSection { titleWidth: pg.titleW; Layout.topMargin: 6 }

        PageReset {
            objectName_: "btn-diacritics-reset"
            dirty: DiacriticsPrefs.changed
            info: "Key, model, idle time, ignored windows and the pill, saved in diacritics.json. Your corrections are kept."
            onReset: DiacriticsPrefs.resetAll()
        }
    }
}
