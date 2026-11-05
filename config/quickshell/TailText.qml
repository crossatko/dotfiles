import QtQuick
import QtQuick.Effects

// Live text that keeps its END in view (a live caption: the newest words), wrapped over up to `maxLines` lines. The box is as
// tall as the text needs (`implicitHeight` = shown lines x one line of the label's font; every line is exactly that tall, so a
// fallback-font glyph (emoji, CJK) arriving mid-sentence cannot make it taller). When the text needs more lines than
// `maxLines`, the newest lines stay at the bottom and the oldest scroll up and out, fading over the top `fadeH` px. Never
// changes its own width. Style it through `label` (Label: Theme font / colour).
//   lineCount  wrapped lines at the current width    shownLines  min(lineCount, maxLines)    overflows  lineCount > maxLines
//   naturalW   the width of the text on one line (independent of the wrapping: for deciding whether a wider box is wanted)
// The fade is a mask layer, only while the text overflows.
Item {
    id: tt
    property string text: ""
    property int maxLines: 1
    property real fadeH: lineH
    readonly property alias label: lbl
    readonly property Item maskItem: fadeMask
    readonly property real lineH: Math.ceil(fm.height)
    readonly property int lineCount: Math.max(1, lbl.lineCount)
    readonly property int shownLines: Math.max(1, Math.min(maxLines, lineCount))
    readonly property bool overflows: lineCount > maxLines
    readonly property real naturalW: ruler.implicitWidth

    implicitHeight: shownLines * lineH
    FontMetrics { id: fm; font: lbl.font }
    clip: true

    Label {      // measures the text on one line (same font as `lbl`)
        id: ruler
        visible: false
        text: tt.text
        wrapMode: Text.NoWrap
        font: lbl.font
    }
    Item {
        id: body
        anchors.fill: parent
        layer.enabled: tt.overflows
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: tt.maskItem   // qmllint disable unqualified
            maskThresholdMin: 0.5   // with spread 1: mask alpha 0..1 -> smoothstep(0, 1), a soft ramp
            maskSpreadAtMin: 1
        }
        Label {
            id: lbl
            width: parent.width
            text: tt.text
            wrapMode: Text.Wrap
            lineHeight: tt.lineH
            lineHeightMode: Text.FixedHeight
            verticalAlignment: Text.AlignTop
            height: Math.max(1, tt.lineCount) * tt.lineH
            y: Math.min(0, parent.height - height)        // the newest lines stay in view while the box is still growing
        }
    }
    // alpha ramp 0 -> 1 over fadeH from the top edge (only rendered as the mask source)
    Item {
        id: fadeMask
        anchors.fill: parent
        visible: false
        layer.enabled: tt.overflows
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0) }
                GradientStop { position: Math.min(1, tt.fadeH / Math.max(1, tt.height)); color: "white" }
            }
        }
    }
}
