import QtQuick
import QtQuick.Effects

// One line of live text that keeps its END in view (a live caption: the newest words): left-aligned while it fits,
// otherwise pinned to the right edge with the overflowing start fading out over `fadeW` px. Never wraps and never
// changes its own width or height (`implicitHeight` is one line of the label's font, so a fallback-font glyph (emoji, CJK)
// arriving mid-sentence cannot make it taller). Style it through `label` (Label: Theme font / colour).
// The fade is a mask layer, only while the text overflows.
Item {
    id: tl
    property string text: ""
    property real fadeW: Theme.pad + Theme.controlGap
    readonly property alias label: lbl
    readonly property Item maskItem: fadeMask
    readonly property bool overflows: lbl.implicitWidth > width + 0.5

    implicitHeight: Math.ceil(fm.height)
    FontMetrics { id: fm; font: lbl.font }
    clip: true

    Item {
        id: body
        anchors.fill: parent
        layer.enabled: tl.overflows
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: tl.maskItem   // qmllint disable unqualified
            maskThresholdMin: 0.5   // with spread 1: mask alpha 0..1 -> smoothstep(0, 1), a soft ramp
            maskSpreadAtMin: 1
        }
        Label {
            id: lbl
            text: tl.text
            wrapMode: Text.NoWrap
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            x: tl.overflows ? tl.width - implicitWidth : 0
        }
    }
    // alpha ramp 0 -> 1 over fadeW from the left edge (only rendered as the mask source)
    Item {
        id: fadeMask
        anchors.fill: parent
        visible: false
        layer.enabled: tl.overflows
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0) }
                GradientStop { position: Math.min(1, tl.fadeW / Math.max(1, tl.width)); color: "white" }
            }
        }
    }
}
