pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// One brightness slider per controllable display (Brightness singleton: DDC/CI or backlight), in the
// style of AudioSection. Hidden when nothing supports it. Re-reads the real values every time it is
// created (the control center opens), so changes made elsewhere (keys, steam-tv-dim, hypridle) show up.
ColumnLayout {
    id: bs
    spacing: 6
    visible: Brightness.available

    Component.onCompleted: Brightness.refresh()

    // all name labels as wide as the longest, so the sliders line up
    TextMetrics {
        id: longest
        font.family: Theme.font
        font.pixelSize: Theme.fontSmall
        text: Brightness.displays.reduce((a, b) => b.length > a.length ? b : a, "")
    }

    Repeater {
        model: Brightness.displays
        LevelRow {
            id: row
            required property string modelData
            readonly property int pct: Brightness.percentOf(modelData)
            icon: "\uf185"
            label: modelData
            labelWidth: Math.ceil(longest.advanceWidth)
            value: pct / 100
            floor: Brightness.minPercent / 100
            onMoved: v => Brightness.set(row.modelData, v * 100)
            valueText: pct + "%"
        }
    }
}
