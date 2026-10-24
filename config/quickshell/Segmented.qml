pragma ComponentBehavior: Bound
import QtQuick

// Segmented choice: a row of Btns 2 px apart, the one whose value equals `current` is `active`.
// `values` are what picked(v) emits, `labels` what the buttons show (defaults to the values). Size and the
// concentric radius are set like Btn's (outerRadius / inset of the box it sits in). Never changes `current`
// itself; picked() fires even while !enabledLook (the user decides).
Row {
    id: seg
    property var values: []
    property var labels: values
    property var current: undefined
    property bool enabledLook: true
    property real outerRadius: Theme.radius
    property real inset: 12
    property real segWidth: 0                      // 0 = each button as wide as its label needs
    property real segHeight: 30
    property var objectNames: []                   // optional per-button objectName (test hooks)
    signal picked(var value)

    spacing: 2
    Repeater {
        model: seg.values
        Btn {
            required property var modelData
            required property int index
            objectName: seg.objectNames[index] || ""
            outerRadius: seg.outerRadius
            inset: seg.inset
            implicitHeight: seg.segHeight
            width: seg.segWidth > 0 ? seg.segWidth : implicitWidth
            text: String(seg.labels[index])
            active: seg.current === modelData
            enabledLook: seg.enabledLook
            onClicked: seg.picked(modelData)
        }
    }
}
