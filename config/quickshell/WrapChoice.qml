pragma ComponentBehavior: Bound
import QtQuick

// Segmented's wrapping sibling for a long list of choices: Btns in a Flow that fills the width it is given and breaks
// into more lines, never widening its parent. `values` are what picked(v) emits, `labels` what the buttons show, the
// one whose value equals `current` is active. Never changes `current` itself. Sized like Btn (outerRadius / inset).
Flow {
    id: wc
    property var values: []
    property var labels: values
    property var current: undefined
    property real outerRadius: Theme.radius
    property real inset: 12
    property real segHeight: Theme.controlH
    property var objectNames: []                   // optional per-button objectName (test hooks)
    signal picked(var value)

    spacing: 2
    Repeater {
        model: wc.values
        Btn {
            required property var modelData
            required property int index
            objectName: wc.objectNames[index] || ""
            outerRadius: wc.outerRadius
            inset: wc.inset
            implicitHeight: wc.segHeight
            text: String(wc.labels[index])
            active: wc.current === modelData
            onClicked: wc.picked(modelData)
        }
    }
}
