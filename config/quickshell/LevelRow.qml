import QtQuick
import QtQuick.Layouts

// Icon + optional name + Slider + value text, the volume / microphone / brightness rows of the control center and
// Audio popup. Same contract as Slider: `value` is the truth, dragging emits moved(v). `iconClickable` makes the
// icon a button (mute) that emits iconClicked().
RowLayout {
    id: lr
    property string icon: ""
    property color iconColor: Theme.accent      // the icon names the slider: accent while live, muted while that source is muted
    property bool iconClickable: false
    property string label: ""                  // "" = no name column
    property real labelWidth: 0                // name column width (all rows the same, so the sliders line up)
    property real value: 0
    property bool dim: false
    property real floor: 0
    property var notches: []                   // Slider notches (Presets.volumeNotches, ...)
    property string valueText: ""
    signal moved(real v)
    signal iconClicked()

    Layout.fillWidth: true
    spacing: Theme.padSm

    // value column: as wide as the widest value ("100%")
    TextMetrics { id: valueMetrics; font.family: Theme.font; font.pixelSize: Theme.fontSmall; text: "100%" }

    Icon {
        text: lr.icon
        horizontalAlignment: Text.AlignHCenter
        Layout.preferredWidth: Theme.iconCol
        font.pixelSize: Theme.iconLg
        color: lr.iconColor
        MouseArea { anchors.fill: parent; anchors.margins: -Theme.gapTight; enabled: lr.iconClickable; cursorShape: Qt.PointingHandCursor; onClicked: lr.iconClicked() }
    }
    Label { visible: lr.label !== ""; text: lr.label; Layout.preferredWidth: lr.labelWidth; color: Theme.fgDim; font.pixelSize: Theme.fontSmall }
    Slider {
        Layout.fillWidth: true
        value: lr.value
        dim: lr.dim
        floor: lr.floor
        notches: lr.notches
        onMoved: v => lr.moved(v)
    }
    Label { text: lr.valueText; Layout.preferredWidth: Math.ceil(valueMetrics.advanceWidth); horizontalAlignment: Text.AlignRight; color: Theme.fgDim; font.pixelSize: Theme.fontSmall }
}
