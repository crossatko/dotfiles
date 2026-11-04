pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings > Voice > Replacements: words the recognizer gets wrong, typed the way you want (heard -> typed, phrases
// allowed, whole words, case-insensitive; Any / a selected language picks the language it applies to). One ReplacementRow
// per entry (folded when there are many), the empty row at the end adds one. All state is DictationWords (dictation-words.json).
ColumnLayout {
    id: sec
    property real titleWidth: 120

    Layout.fillWidth: true
    spacing: Theme.gapRow

    SectionHead {
        title: "Replacements"
        InfoTip { text: "Whole words or phrases, any capitalisation, e.g. “century” → “sentry”. The first letter's capital carries over. Edit a row and press Enter, or leave it, to save." }
    }
    AdvancedFold {
        objectName: "fold-replacements"
        visible: DictationWords.replacements.length > 0
        label: DictationWords.replacements.length + (DictationWords.replacements.length === 1 ? " replacement" : " replacements")
        count: DictationWords.replacements.length
        bodySpacing: Theme.gapRow
        Repeater {
            model: DictationWords.replacements
            ReplacementRow {
                id: rr
                required property var modelData
                Layout.fillWidth: true
                entry: rr.modelData
            }
        }
    }
    ReplacementRow { objectName: "repl-new"; index: -1 }
}
