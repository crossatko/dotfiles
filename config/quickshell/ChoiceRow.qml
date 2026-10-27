import QtQuick
import QtQuick.Layouts

// A Settings row with one primary choice: title | Segmented | "Custom" tag | caption. `values` / `labels` as Segmented;
// `current` is the picked value or anything else (e.g. "custom") when the saved values match no option: then the
// Custom tag shows and no segment is active, and the old values stay until the user picks one (Presets.qml decides).
// `caption` explains the picked option in a few words (changes with it). picked(v) on click.
SettingRow {
    id: row
    property var values: []
    property var labels: values
    property var current: undefined
    property var objectNames: []
    property string hint: ""
    property string info: ""
    property real segWidth: 0
    readonly property bool custom: values.indexOf(current) < 0
    signal picked(var value)

    Segmented {
        values: row.values
        labels: row.labels
        objectNames: row.objectNames
        current: row.current
        outerRadius: Theme.radiusPage; inset: 9
        segHeight: 26
        segWidth: row.segWidth
        onPicked: v => row.picked(v)
    }
    CustomTag { visible: row.custom }
    Label {
        visible: row.hint !== ""
        text: row.hint
        color: Theme.muted; font.pixelSize: Theme.fontCaption
        elide: Text.ElideRight
        Layout.maximumWidth: 220
    }
    InfoTip { text: row.info }
    Item { Layout.fillWidth: true }
}
