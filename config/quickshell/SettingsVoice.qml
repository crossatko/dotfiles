pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings -> Voice (speech to text). One self-contained section component per topic, stacked in the order both feature
// pages share (SettingsDiacritics): keys, pill, model, the feature's own settings, word lists, status; adding a topic = one
// line here (its component takes `titleWidth`) plus its store in the PageReset below.
//   LanguagesSection the languages you dictate in (PttPrefs: ptt.json), each with its own keys below
//   PttKeysSection   the push-to-talk keys: Auto and per language (PttPrefs: ptt.json, applied to Hyprland at once)
//   DictationPillSection   the pill: live preview, where it sits (DictationPrefs: dictation-prefs.json; PillSection)
//   SttModelsSection the speech models: roles, downloads, idle unload (SttModels: stt-models.json, model files outside the repo)
//   DictationPrefsSection  microphone, GPU, recognition hints (DictationPrefs)
//   FillerWordsSection     filler sounds per language (DictationWords: dictation-words.json)
//   ReplacementsSection    heard -> typed replacements (DictationWords)
//   VoiceLastError   the last dictation error (dictation-last-error.json, read-only apart from Clear)
// PageReset = every section's store reset.
Item {
    id: pg
    implicitHeight: col.implicitHeight

    readonly property int titleW: 120
    readonly property bool dragging: pill.dragging || models.dragging     // a slider drag: the Settings page must not scroll

    Component.onCompleted: { PttPrefs.watchers++; PttPrefs.refresh() }
    Component.onDestruction: PttPrefs.watchers--

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Theme.pad

        LanguagesSection { titleWidth: pg.titleW }
        PttKeysSection { titleWidth: pg.titleW; Layout.topMargin: 6 }
        DictationPillSection { id: pill; titleWidth: pg.titleW; Layout.topMargin: 6 }
        SttModelsSection { id: models; titleWidth: pg.titleW; Layout.topMargin: 6 }
        DictationPrefsSection { titleWidth: pg.titleW; Layout.topMargin: 6 }
        FillerWordsSection { titleWidth: pg.titleW; Layout.topMargin: 6 }
        ReplacementsSection { titleWidth: pg.titleW; Layout.topMargin: 6 }
        VoiceLastError { titleWidth: pg.titleW; Layout.topMargin: 6 }

        PageReset {
            objectName_: "btn-voice-reset"
            dirty: PttPrefs.changed || SttModels.changed || DictationPrefs.changed || DictationWords.changed
            info: "Keys and languages saved in ptt.json, models in stt-models.json, dictation and pill settings in dictation-prefs.json, word lists in dictation-words.json."
            onReset: { PttPrefs.resetAll(); SttModels.resetAll(); DictationPrefs.resetAll(); DictationWords.resetAll() }
        }
    }
}
