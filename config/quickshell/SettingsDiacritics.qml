pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings -> Diacritics (fix the diacritics of Czech text with a local model, on one key). One self-contained section
// component per topic, stacked; adding a topic = one line here (its component takes `titleWidth`) plus its store in the
// PageReset below. All state is DiacriticsPrefs (diacritics.json).
//   DiacriticsKeySection      the key (applied to Hyprland at once)
//   DiacriticsModelSection    the model file, idle unload
//   DiacriticsIgnoredSection  window classes where the key does nothing
//   DiacriticsCorrectionsSection  words the model gets wrong (DiacriticsWords, diacritics-words.json)
//   DiacriticsPillSection     real text or a generic animation in the pill
Item {
    id: pg
    implicitHeight: col.implicitHeight

    readonly property int titleW: 120

    // the conflict check and the key's status read the Hyprland binds PttPrefs keeps fresh while a page watches them
    Component.onCompleted: { PttPrefs.watchers++; PttPrefs.refresh(); DiacriticsPrefs.refreshModels() }
    Component.onDestruction: PttPrefs.watchers--

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Theme.pad

        DiacriticsKeySection { titleWidth: pg.titleW }
        DiacriticsModelSection { titleWidth: pg.titleW; Layout.topMargin: 6 }
        DiacriticsIgnoredSection { titleWidth: pg.titleW; Layout.topMargin: 6 }
        DiacriticsCorrectionsSection { titleWidth: pg.titleW; Layout.topMargin: 6 }
        DiacriticsPillSection { titleWidth: pg.titleW; Layout.topMargin: 6 }

        PageReset {
            objectName_: "btn-diacritics-reset"
            dirty: DiacriticsPrefs.changed || DiacriticsWords.changed
            info: "Key, model, idle time, ignored windows, corrections and the pill option, saved in diacritics.json and diacritics-words.json."
            onReset: { DiacriticsPrefs.resetAll(); DiacriticsWords.resetAll() }
        }
    }
}
