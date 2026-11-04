pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings > Voice > Filler words: the sounds dropped from the dictated text ("um", "ehm"), one WordListEditor per
// language (DictationWords: dictation-words.json), and Restore defaults (the built-in conservative list; the button
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
    WordListEditor { title: "Czech"; titleWidth: sec.titleWidth; lang: "cs" }
    WordListEditor { title: "English"; titleWidth: sec.titleWidth; lang: "en" }
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
