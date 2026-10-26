import QtQuick
import QtQuick.Layouts

// A Settings row for one numeric key of a prefs singleton with Motion / LockPrefs-style storage (`store` has
// value(key), set(key, v), overridden(key) and spec[key] = [min, max, decimals]): title, slider over the key's range,
// the value (`format`) and "(default)" while the key is not set. `dragging` = a drag is in progress (the page's
// Flickable must not steal it, see SettingsAnimations).
SettingRow {
    id: row
    property var store: null
    property string key: ""
    property var format: v => String(v)
    property real valueWidth: 52
    property real noteWidth: 64
    readonly property var range: store ? store.spec[key] : [0, 1, 0]
    readonly property real current: store ? store.value(key) : 0
    readonly property bool dragging: hold.running
    Timer { id: hold; interval: 300 }

    Slider {
        wheel: false
        objectName: "slider-" + row.key
        Layout.fillWidth: true
        value: (row.current - row.range[0]) / (row.range[1] - row.range[0])
        mark: row.store ? (row.store.defaults[row.key] - row.range[0]) / (row.range[1] - row.range[0]) : -1
        onMoved: v => { hold.restart(); row.store.set(row.key, row.range[0] + v * (row.range[1] - row.range[0])) }
    }
    Label { text: row.format(row.current); Layout.preferredWidth: row.valueWidth; horizontalAlignment: Text.AlignRight; color: Theme.fg; font.pixelSize: Theme.fontSmall }
    Label { text: row.store && row.store.overridden(row.key) ? "" : "(default)"; Layout.preferredWidth: row.noteWidth; color: Theme.muted; font.pixelSize: Theme.fontCaption }
}
