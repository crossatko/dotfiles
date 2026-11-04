pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// One correction of the diacritics list (DiacriticsWords.entries): the word as it came out -> the correct word, and
// whether it is also replaced after the model (Always replace; off = only a hint for the model). An existing row
// (`index` >= 0, `entry` = { typed, correct, always }) saves when you press Enter, flip the switch or leave the row; a row
// the list refuses (empty side, both sides the same, already listed, too long) keeps what was typed in red with the
// reason under it, Esc puts the saved text back. The row with `index` -1 is the empty one that adds a new correction
// (Enter or the plus button); a word that is already listed updates that entry.
ColumnLayout {
    id: cr
    required property int index
    property var entry: ({ typed: "", correct: "", always: false })
    readonly property bool isNew: index < 0
    property bool always: entry.always
    property string problem: ""
    spacing: Theme.gapTight

    Layout.fillWidth: true

    function commit() {
        if (cr.isNew) return
        if (typedBox.text === cr.entry.typed && correctBox.text === cr.entry.correct && cr.always === cr.entry.always) { cr.problem = ""; return }
        cr.problem = DiacriticsWords.update(cr.index, typedBox.text, correctBox.text, cr.always)
    }
    function add() {
        const e = DiacriticsWords.add(typedBox.text, correctBox.text, cr.always)
        cr.problem = e
        if (e === "") { typedBox.text = ""; correctBox.text = ""; cr.always = false; typedBox.focusField() }
    }
    function accept() { if (cr.isNew) cr.add(); else cr.commit() }
    function revert() { typedBox.text = cr.entry.typed; correctBox.text = cr.entry.correct; cr.problem = "" }
    // leaving one field for the other must not save (and rebuild the row) in between
    Timer { id: leave; interval: 60; onTriggered: if (!typedBox.focused && !correctBox.focused) cr.commit() }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.controlGap
        FieldBox {
            id: typedBox
            objectName: "corr-typed-" + cr.index
            Layout.fillWidth: true; Layout.preferredWidth: 100; Layout.alignment: Qt.AlignTop
            implicitHeight: 26
            placeholder: "Came out as"
            text: cr.entry.typed
            maximumLength: DiacriticsWords.maxLen
            error: cr.problem !== ""
            outerRadius: Theme.radiusPage; inset: 9
            onAccepted: cr.accept()
            onCancelled: if (!cr.isNew) cr.revert()
            onFocusedChanged: if (!focused) leave.restart()
            Connections { target: typedBox.input; function onTextChanged() { if (cr.problem !== "" && typedBox.text !== cr.entry.typed) cr.problem = "" } }
        }
        Icon { text: Icons.arrowRight; font.pixelSize: Theme.iconSm; color: Theme.muted; Layout.alignment: Qt.AlignTop; Layout.topMargin: 5 }
        FieldBox {
            id: correctBox
            objectName: "corr-correct-" + cr.index
            Layout.fillWidth: true; Layout.preferredWidth: 100; Layout.alignment: Qt.AlignTop
            implicitHeight: 26
            placeholder: "Should be"
            text: cr.entry.correct
            maximumLength: DiacriticsWords.maxLen
            error: cr.problem !== ""
            outerRadius: Theme.radiusPage; inset: 9
            onAccepted: cr.accept()
            onCancelled: if (!cr.isNew) cr.revert()
            onFocusedChanged: if (!focused) leave.restart()
            Connections { target: correctBox.input; function onTextChanged() { if (cr.problem !== "" && correctBox.text !== cr.entry.correct) cr.problem = "" } }
        }
        Label { text: "Always"; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.alignment: Qt.AlignVCenter }
        Toggle {
            objectName: "corr-always-" + cr.index
            Layout.alignment: Qt.AlignVCenter
            checked: cr.always
            onToggled: want => { cr.always = want; if (!cr.isNew) cr.commit() }
        }
        InfoTip {
            Layout.alignment: Qt.AlignVCenter
            text: "Always replace. Off: the entry is only a hint, the model sees it and usually follows it. On: the word is also replaced after the model, whatever it wrote."
        }
        Btn {
            objectName: cr.isNew ? "btn-corr-add" : "btn-corr-remove-" + cr.index
            glyph: cr.isNew ? Icons.plus : Icons.xmark
            tip: cr.isNew ? "Add this correction" : "Remove"
            minWidth: 26
            Layout.alignment: Qt.AlignTop
            implicitHeight: 26
            enabledLook: !cr.isNew || typedBox.text.trim() !== "" || correctBox.text.trim() !== ""
            outerRadius: Theme.radiusPage; inset: 9
            onClicked: if (cr.isNew) cr.add(); else DiacriticsWords.remove(cr.index)
        }
    }
    Label {
        objectName: "corr-problem-" + cr.index
        visible: cr.problem !== ""
        text: cr.problem
        color: Theme.red; font.pixelSize: Theme.fontCaption
        Layout.fillWidth: true; wrapMode: Text.WordWrap
    }
}
