pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// One replacement of the dictation word list (DictationWords.replacements): what you say -> what is typed, and the
// language it applies to (Any / the selected languages). An existing row (`index` >= 0, `entry` = { heard, typed, lang })
// saves when you press Enter, pick a language or leave the row; a row the list refuses (empty or whitespace-only side,
// both sides the same, already replaced for that language, too long) keeps what was typed in red with the reason under
// it, Esc puts the saved text back. The row with `index` -1 is the empty one that adds a new replacement (Enter or the
// plus button). Phrases are fine on both sides.
ColumnLayout {
    id: rr
    required property int index
    property var entry: ({ heard: "", typed: "", lang: "any" })
    readonly property bool isNew: index < 0
    property string lang: entry.lang
    property string problem: ""
    spacing: Theme.gapTight
    // more than three choices (Any and 2+ languages) do not fit beside the fields as buttons: a dropdown with the names
    readonly property bool manyLangs: DictationWords.replLangsFor(lang).length > 3

    Layout.fillWidth: true

    function commit() {
        if (rr.isNew) return
        if (heardBox.text === rr.entry.heard && typedBox.text === rr.entry.typed && rr.lang === rr.entry.lang) { rr.problem = ""; return }
        rr.problem = DictationWords.updateReplacement(rr.index, heardBox.text, typedBox.text, rr.lang)
    }
    function add() {
        const e = DictationWords.addReplacement(heardBox.text, typedBox.text, rr.lang)
        rr.problem = e
        if (e === "") { heardBox.text = ""; typedBox.text = ""; heardBox.focusField() }
    }
    function accept() { if (rr.isNew) rr.add(); else rr.commit() }
    function revert() { heardBox.text = rr.entry.heard; typedBox.text = rr.entry.typed; rr.problem = "" }
    // leaving one field for the other must not save (and rebuild the row) in between
    Timer { id: leave; interval: 60; onTriggered: if (!heardBox.focused && !typedBox.focused) rr.commit() }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.controlGap
        FieldBox {
            id: heardBox
            objectName: "repl-heard-" + rr.index
            Layout.fillWidth: true; Layout.preferredWidth: 100; Layout.alignment: Qt.AlignTop
            implicitHeight: 26
            placeholder: "You say"
            text: rr.entry.heard
            maximumLength: DictationWords.maxHeardLen + 20
            error: rr.problem !== ""
            outerRadius: Theme.radiusPage; inset: 9
            onAccepted: rr.accept()
            onCancelled: if (!rr.isNew) rr.revert()
            onFocusedChanged: if (!focused) leave.restart()
            Connections { target: heardBox.input; function onTextChanged() { if (rr.problem !== "" && heardBox.text !== rr.entry.heard) rr.problem = "" } }
        }
        Icon { text: Icons.arrowRight; font.pixelSize: Theme.iconSm; color: Theme.muted; Layout.alignment: Qt.AlignTop; Layout.topMargin: 5 }
        FieldBox {
            id: typedBox
            objectName: "repl-typed-" + rr.index
            Layout.fillWidth: true; Layout.preferredWidth: 100; Layout.alignment: Qt.AlignTop
            implicitHeight: 26
            placeholder: "Typed instead"
            text: rr.entry.typed
            maximumLength: DictationWords.maxTypedLen + 20
            error: rr.problem !== ""
            outerRadius: Theme.radiusPage; inset: 9
            onAccepted: rr.accept()
            onCancelled: if (!rr.isNew) rr.revert()
            onFocusedChanged: if (!focused) leave.restart()
            Connections { target: typedBox.input; function onTextChanged() { if (rr.problem !== "" && typedBox.text !== rr.entry.typed) rr.problem = "" } }
        }
        Segmented {
            visible: !rr.manyLangs
            Layout.alignment: Qt.AlignTop
            objectNames: values.map(v => "repl-lang-" + v + "-" + rr.index)
            values: DictationWords.replLangsFor(rr.lang)
            labels: DictationWords.replLabelsFor(rr.lang)
            current: rr.lang
            outerRadius: Theme.radiusPage; inset: 9
            segHeight: 26
            onPicked: v => { rr.lang = v; if (!rr.isNew) rr.commit() }
        }
        DropSelect {
            visible: rr.manyLangs
            objectName: "repl-lang-drop-" + rr.index
            Layout.preferredWidth: 150
            Layout.alignment: Qt.AlignTop
            headHeight: 26
            options: DictationWords.replLangsFor(rr.lang).map(l => ({ label: DictationWords.labelOf(l) }))
            currentIndex: DictationWords.replLangsFor(rr.lang).indexOf(rr.lang)
            onPicked: i => { rr.lang = DictationWords.replLangsFor(rr.lang)[i]; if (!rr.isNew) rr.commit() }
        }
        Btn {
            objectName: rr.isNew ? "btn-repl-add" : "btn-repl-remove-" + rr.index
            glyph: rr.isNew ? Icons.plus : Icons.xmark
            tip: rr.isNew ? "Add this replacement" : "Remove"
            minWidth: 26
            Layout.alignment: Qt.AlignTop
            implicitHeight: 26
            enabledLook: !rr.isNew || heardBox.text.trim() !== "" || typedBox.text.trim() !== ""
            outerRadius: Theme.radiusPage; inset: 9
            onClicked: if (rr.isNew) rr.add(); else DictationWords.removeReplacement(rr.index)
        }
    }
    Label {
        objectName: "repl-problem-" + rr.index
        visible: rr.problem !== ""
        text: rr.problem
        color: Theme.red; font.pixelSize: Theme.fontCaption
        Layout.fillWidth: true; wrapMode: Text.WordWrap
    }
}
