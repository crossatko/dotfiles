pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "launcher/js/DictLangs.js" as D

// Settings > Voice > Filler words: the sounds dropped from the dictated text ("um", "ehm"), one WordListEditor per
// selected language (PttPrefs.languages) (DictationWords: dictation-words.json), and Restore defaults (the built-in conservative list; the button
// is dim while the lists are the defaults). `changed` of the page's reset comes from DictationWords.
ColumnLayout {
    id: sec
    property real titleWidth: 120

    Layout.fillWidth: true
    spacing: Theme.gapRow

    SectionHead {
        title: "Filler words"
        detail: DictationWords.fillersCustom ? "edited" : ""
        InfoTip { text: "Sounds removed from what you dictate, whole words only, per language. Keep it to real filler sounds: a word that is also a word of the language (such as Czech “no”) would vanish from your text." }
    }
    Repeater {
        model: DictationWords.langs
        WordListEditor { id: wl; required property string modelData; title: D.name(wl.modelData); titleWidth: sec.titleWidth; lang: wl.modelData }
    }
    Label {
        visible: DictationWords.langs.length === 0
        text: "Select a language above to edit its filler words."
        color: Theme.muted; font.pixelSize: Theme.fontCaption
    }
    SettingRow {
        titleWidth: sec.titleWidth
        Btn {
            objectName: "btn-fillers-restore"
            text: "Restore defaults"
            implicitHeight: 26
            outerRadius: Theme.radiusPage; inset: 9
            enabledLook: DictationWords.fillersCustom
            onClicked: if (DictationWords.fillersCustom) DictationWords.restoreFillers()
        }
        Item { Layout.fillWidth: true }
    }
}
