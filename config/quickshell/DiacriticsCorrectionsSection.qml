pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings > Diacritics > Corrections: words the model got wrong, with the right form (came out as -> should be, whole
// words or short phrases, case-insensitive). One CorrectionRow per entry (folded when there are many), the empty row at the
// end adds one. All state is DiacriticsWords (diacritics-words.json).
ColumnLayout {
    id: sec
    property real titleWidth: 120

    Layout.fillWidth: true
    spacing: Theme.gapRow

    SectionHead {
        title: "Corrections"
        InfoTip { text: "Words or phrases the model gets wrong, e.g. “Zorvelka” → “Zorvelká”. Every entry is shown to the model as a hint; with Always on it is also replaced after the model. Edit a row and press Enter, or leave it, to save." }
    }
    AdvancedFold {
        objectName: "fold-corrections"
        visible: DiacriticsWords.entries.length > 0
        label: DiacriticsWords.entries.length + (DiacriticsWords.entries.length === 1 ? " correction" : " corrections")
        count: DiacriticsWords.entries.length
        bodySpacing: Theme.gapRow
        Repeater {
            model: DiacriticsWords.entries
            CorrectionRow {
                id: cr
                required property var modelData
                Layout.fillWidth: true
                entry: cr.modelData
            }
        }
    }
    CorrectionRow { objectName: "corr-new"; index: -1 }
}
