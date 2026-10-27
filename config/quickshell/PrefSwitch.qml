import QtQuick
import QtQuick.Layouts

// A primary Settings row for one boolean key of a prefs singleton (see PrefToggle): the title in the title column,
// then the switch and a muted hint. Same objectName as PrefToggle's switch (toggle-<key>).
SettingRow {
    id: row
    property var store: null
    property string key: ""
    property string hint: ""
    property string info: ""               // a technical note, shown by an InfoTip glyph on hover
    property string infoIcon: ""           // circle-info; Icons.lock lock / Icons.warning warning for a disabled thing
    property color infoColor: Theme.muted
    Toggle {
        objectName: "toggle-" + row.key
        checked: row.store ? row.store.value(row.key) : false
        onToggled: want => row.store.set(row.key, want)
    }
    InfoTip { objectName: "info-" + row.key; text: row.info; icon: row.infoIcon !== "" ? row.infoIcon : Icons.info; color: row.infoColor }
    Label { text: row.hint; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true; elide: Text.ElideRight }
}
