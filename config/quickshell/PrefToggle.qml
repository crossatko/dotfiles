import QtQuick
import QtQuick.Layouts

// A Settings row for one boolean key of a prefs singleton (see PrefSlider): toggle, label, a muted hint.
SettingRow {
    id: row
    property var store: null
    property string key: ""
    property string label: ""
    property string hint: ""
    Toggle {
        objectName: "toggle-" + row.key
        checked: row.store ? row.store.value(row.key) : false
        onToggled: want => row.store.set(row.key, want)
    }
    Label { text: row.label; color: Theme.fgDim; font.pixelSize: Theme.fontSmall }
    Label { text: row.hint; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true; elide: Text.ElideRight }
}
