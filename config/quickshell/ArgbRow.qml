pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// One colour with alpha (0xAARRGGBB integer) as a Settings control: a swatch row (swatch, hex, reset) and one A / R / G / B
// slider row each. Used by GlassAdvanced (solid_glass tint, alpha = absorption) and BlurOptRow (acrylic / aurora /
// fluid jar colours). `value` is what is shown; edited(shift, argb) says which channel moved (24 alpha, 16 red,
// 8 green, 0 blue) and the whole new colour; the owner stores it. Children go between the swatch row and the sliders
// (e.g. a "from theme" switch). objectNames: reset-<prefix>, slider-<prefix>-<shift>.
ColumnLayout {
    id: argb
    property real value: 0
    property real defaultValue: 0
    property string title: "Colour"
    property string alphaName: "Alpha (A)"
    property string objectPrefix: "colour"
    property real titleW: 120
    property real valueW: 62
    property bool changed: Math.abs(value - defaultValue) > 0.5
    default property alias between: slot.data
    signal edited(int shift, real argb)
    signal reset()

    spacing: 12
    Layout.fillWidth: true

    function channel(shift) { return (Math.round(value) >>> shift) & 255 }
    function withChannel(shift, v) {
        const t = Math.round(value) >>> 0
        return ((t & ~(255 << shift)) | (Math.round(v) << shift)) >>> 0
    }
    readonly property color tintColor: Qt.rgba(channel(16) / 255, channel(8) / 255, channel(0) / 255, channel(24) / 255)
    function hex(v) { return "0x" + ("00000000" + (Math.round(v) >>> 0).toString(16).toUpperCase()).slice(-8) }

    SettingRow {
        title: argb.title
        titleWidth: argb.titleW
        Rectangle {
            implicitWidth: 44; implicitHeight: 20
            radius: Math.min(5, Theme.radiusDeep)
            color: "#808080"
            clip: true
            border.width: 1; border.color: Theme.alpha(Theme.fg, 0.3)
            Rectangle { anchors.fill: parent; color: argb.tintColor }
            Rectangle { width: parent.width / 2; height: parent.height; color: Qt.rgba(argb.tintColor.r, argb.tintColor.g, argb.tintColor.b, 1) }
        }
        Label {
            Layout.fillWidth: true
            text: argb.hex(argb.value)
            color: Theme.fgDim; font.pixelSize: Theme.fontSmall
        }
        ResetBtn {
            objectName: "reset-" + argb.objectPrefix
            set: argb.changed
            onClicked: argb.reset()
        }
    }
    ColumnLayout {
        id: slot
        visible: children.length > 0
        Layout.fillWidth: true
        spacing: 12
    }
    Repeater {
        model: [
            { n: argb.alphaName, s: 24 },
            { n: "Red", s: 16 },
            { n: "Green", s: 8 },
            { n: "Blue", s: 0 }
        ]
        SettingRow {
            id: crow
            required property var modelData
            title: modelData.n
            titleWidth: argb.titleW
            readonly property int cur: argb.channel(modelData.s)
            Slider {
                wheel: false
                objectName: "slider-" + argb.objectPrefix + "-" + crow.modelData.s
                Layout.fillWidth: true
                value: crow.cur / 255
                notches: [((Math.round(argb.defaultValue) >>> crow.modelData.s) & 255) / 255]   // the default colour's channel
                onMoved: v => argb.edited(crow.modelData.s, argb.withChannel(crow.modelData.s, v * 255))
            }
            Label { text: crow.cur; Layout.preferredWidth: argb.valueW; horizontalAlignment: Text.AlignRight; color: Theme.fg; font.pixelSize: Theme.fontSmall }
            Item { Layout.preferredWidth: 24 }      // where the reset button sits on the other rows
        }
    }
}
