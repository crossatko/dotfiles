pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings row editing one word list (by default the fillers of one DictationWords language, `lang` = "cs" | "en"): the
// words as removable chips (WordChip) and a field + Add to put in a new one. A word the list refuses (empty, two words,
// not letters, too long, already there) is not added and the reason shows in red under the field until the next
// keystroke. Another list: set `words`, `addFn(text)` (-> "" or the reason it refused), `removeFn(word)`, `ns` (the
// objectName prefix), `placeholder`, `emptyText`, `maxLen`.
SettingRow {
    id: ed
    property string lang: "en"
    property string ns: "filler"
    property string placeholder: "Add a filler sound"
    property string emptyText: "No filler words: nothing is removed"
    property int maxLen: DictationWords.maxFillerLen
    property var words: DictationWords.fillersOf(lang)
    property var addFn: t => DictationWords.addFiller(ed.lang, t)
    property var removeFn: w => DictationWords.removeFiller(ed.lang, w)
    property string problem: ""
    titleTopAt: 15

    function add() {
        const e = ed.addFn(box.text)
        ed.problem = e
        if (e === "") box.text = ""
        else box.error = true
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.gapRow
        Flow {
            Layout.fillWidth: true
            spacing: Theme.gapTight
            Repeater {
                model: ed.words
                WordChip {
                    id: wc
                    required property string modelData
                    text: wc.modelData
                    onRemoved: ed.removeFn(wc.modelData)
                }
            }
            Label {
                visible: ed.words.length === 0
                text: ed.emptyText
                color: Theme.muted; font.pixelSize: Theme.fontCaption
            }
        }
        RowLayout {
            spacing: Theme.controlGap
            FieldBox {
                id: box
                objectName: ed.ns + "-input-" + ed.lang
                Layout.preferredWidth: 180
                implicitHeight: 26
                placeholder: ed.placeholder
                maximumLength: ed.maxLen + 8
                outerRadius: Theme.radiusPage; inset: 9
                onAccepted: ed.add()
                Connections { target: box.input; function onTextChanged() { ed.problem = ""; box.error = false } }
            }
            Btn {
                objectName: "btn-" + ed.ns + "-add-" + ed.lang
                text: "Add"
                implicitHeight: 26
                outerRadius: Theme.radiusPage; inset: 9
                enabledLook: box.text.trim() !== ""
                onClicked: ed.add()
            }
        }
        Label {
            objectName: ed.ns + "-problem-" + ed.lang
            visible: ed.problem !== ""
            text: ed.problem
            color: Theme.red; font.pixelSize: Theme.fontCaption
        }
    }
}
