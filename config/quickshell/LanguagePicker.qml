pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "launcher/js/DictLangs.js" as D

// A search field over whisper's languages (launcher/js/DictLangs.js): type a name or a code, the best matches that are
// not chosen yet list below (LanguageOption), click one or press Enter (the first) to choose it: `picked(code)`. The
// list shows while the field has text; Esc clears it. `skip` = the codes already chosen, `maxRows` the list's length.
ColumnLayout {
    id: pick
    property var skip: []
    property int maxRows: 6
    signal picked(string code)

    readonly property var matches: box.text.trim() === "" ? [] : D.search(box.text, skip).slice(0, maxRows)
    function choose(code) { pick.picked(code); box.text = "" }

    spacing: Theme.gapTight

    FieldBox {
        id: box
        objectName: "lang-search"
        Layout.preferredWidth: 220
        implicitHeight: 26
        placeholder: "Add a language: name or code"
        outerRadius: Theme.radiusPage; inset: 9
        onAccepted: if (pick.matches.length) pick.choose(pick.matches[0].code)
        onCancelled: box.text = ""
    }
    Repeater {
        model: pick.matches
        LanguageOption {
            id: lo
            required property var modelData
            required property int index
            Layout.preferredWidth: 220
            code: lo.modelData.code; name: lo.modelData.name
            highlighted: lo.index === 0
            onPicked: pick.choose(lo.modelData.code)
        }
    }
    Label {
        visible: box.text.trim() !== "" && pick.matches.length === 0
        text: "No such language"
        color: Theme.muted; font.pixelSize: Theme.fontCaption
    }
}
