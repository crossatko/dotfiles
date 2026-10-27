import QtQuick
import QtQuick.Layouts

// A Settings row for one numeric key of a prefs singleton with Motion / LockPrefs-style storage (`store` has
// value(key), set(key, v), unset(key), overridden(key), defaults[key] and spec[key] = [min, max, decimals]): title, slider
// over the key's range (notches: the default, plus `extras` such as the preset values), the value (`format`) and a
// reset glyph that is lit while the key is set (a double-click on the slider does the same)
// (the same row anatomy as GlassOptRow: every slider row of Settings lines up). `dragging` = a drag is in progress (the
// page's Flickable must not steal it, see SettingsAnimations).
SettingRow {
    id: row
    property var store: null
    property string key: ""
    property var format: v => String(v)
    property var extras: []                // further notches in the key's units (e.g. Presets.lockSize.map(p => p.v))
    property real valueWidth: 62           // the value column of every Settings slider row (GlassOptRow's valueW)
    readonly property var range: store ? store.spec[key] : [0, 1, 0]
    readonly property real current: store ? store.value(key) : 0
    readonly property bool own: store ? store.overridden(key) : false
    readonly property bool dragging: hold.running
    Timer { id: hold; interval: 300 }
    function norm(v) { return (v - range[0]) / (range[1] - range[0]) }

    Slider {
        wheel: false
        objectName: "slider-" + row.key
        Layout.fillWidth: true
        value: row.norm(row.current)
        notches: row.store ? [{ v: row.norm(row.store.defaults[row.key]), kind: "default" }].concat((row.extras || []).map(e => ({ v: row.norm(e), kind: "extra" }))) : []
        step: Math.max(0.01, Math.pow(10, -row.range[2]) / (row.range[1] - row.range[0]))
        resetToNotch: false
        onResetRequested: if (row.own) row.store.unset(row.key)
        onMoved: v => { hold.restart(); row.store.set(row.key, row.range[0] + v * (row.range[1] - row.range[0])) }
    }
    Label { text: row.format(row.current); Layout.preferredWidth: row.valueWidth; horizontalAlignment: Text.AlignRight; color: Theme.fg; font.pixelSize: Theme.fontSmall }
    // reset to the default (GlassOptRow's reset button: 24 x 20, dim while the key is not set)
    ResetBtn {
        objectName: "reset-" + row.key
        set: row.own
        onClicked: if (row.own) row.store.unset(row.key)
    }
}
