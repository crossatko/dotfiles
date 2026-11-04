pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings row editing one word list of DictationWords (the fillers of one language): the words as removable chips
// (WordChip) and a field + Add to put in a new one. A word the list refuses (empty, two words, not letters, too long,
// already there) is not added and the reason shows in red under the field until the next keystroke. `lang` = "cs" | "en".
SettingRow {
    id: ed
    property string lang: "en"
    readonly property var words: DictationWords.fillersOf(lang)
    property string problem: ""
    titleTopAt: 15

    function add() {
        const e = DictationWords.addFiller(ed.lang, box.text)
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
                    onRemoved: DictationWords.removeFiller(ed.lang, wc.modelData)
                }
            }
            Label {
                visible: ed.words.length === 0
                text: "No filler words: nothing is removed"
                color: Theme.muted; font.pixelSize: Theme.fontCaption
            }
        }
        RowLayout {
            spacing: Theme.controlGap
            FieldBox {
                id: box
                objectName: "filler-input-" + ed.lang
                Layout.preferredWidth: 180
                implicitHeight: 26
                placeholder: "Add a filler sound"
                maximumLength: DictationWords.maxFillerLen + 8
                outerRadius: Theme.radiusPage; inset: 9
                onAccepted: ed.add()
                Connections { target: box.input; function onTextChanged() { ed.problem = ""; box.error = false } }
            }
            Btn {
                objectName: "btn-filler-add-" + ed.lang
                text: "Add"
                implicitHeight: 26
                outerRadius: Theme.radiusPage; inset: 9
                enabledLook: box.text.trim() !== ""
                onClicked: ed.add()
            }
        }
        Label {
            objectName: "filler-problem-" + ed.lang
            visible: ed.problem !== ""
            text: ed.problem
            color: Theme.red; font.pixelSize: Theme.fontCaption
        }
    }
}
