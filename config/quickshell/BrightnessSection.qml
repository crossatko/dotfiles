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
        font.pixelSize: 12
        text: Brightness.displays.reduce((a, b) => b.length > a.length ? b : a, "")
    }

    Repeater {
        model: Brightness.displays
        RowLayout {
            id: row
            required property string modelData
            readonly property int pct: Brightness.percentOf(modelData)
            Layout.fillWidth: true
            spacing: 10
            Label {
                text: ""
                font.family: Theme.iconFont; font.styleName: "Regular"
                horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 24
                font.pixelSize: 17
                color: Theme.accent
            }
            Label { text: row.modelData; Layout.preferredWidth: Math.ceil(longest.advanceWidth); color: Theme.fgDim; font.pixelSize: 12 }
            Slider {
                Layout.fillWidth: true
                value: row.pct / 100
                floor: Brightness.minPercent / 100
                onMoved: v => Brightness.set(row.modelData, v * 100)
            }
            Label { text: row.pct + "%"; Layout.preferredWidth: 40; horizontalAlignment: Text.AlignRight; color: Theme.fgDim; font.pixelSize: 12 }
        }
    }
}
