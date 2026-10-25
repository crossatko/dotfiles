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
    // > 0: the row fills this width. Equal buttons when every label fits its equal share, otherwise each button is
    // its label's width plus an equal share of what is left (one long label does not force abbreviations).
    property real fillWidth: 0
    property real segHeight: 30
    property var objectNames: []                   // optional per-button objectName (test hooks)
    signal picked(var value)

    spacing: 2

    FontMetrics { id: fm; font.family: Theme.font; font.pixelSize: 12 }   // Btn's label font
    readonly property var naturals: (labels || []).map(l => Math.ceil(fm.advanceWidth(String(l))) + 22)
    readonly property real _free: fillWidth - spacing * Math.max(0, naturals.length - 1)
    readonly property bool _equal: naturals.every(w => w <= _free / Math.max(1, naturals.length))
    readonly property real _extra: naturals.length ? (_free - naturals.reduce((a, b) => a + b, 0)) / naturals.length : 0
    function widthOf(i) {
        if (fillWidth > 0) {
            const w = j => Math.floor(_equal ? _free / naturals.length : naturals[j] + _extra)
            if (i < naturals.length - 1) return w(i)
            let used = 0                       // the last button takes the rounding remainder: flush right edge
            for (let j = 0; j < i; j++) used += w(j)
            return _free - used
        }
        return segWidth > 0 ? segWidth : -1
    }

    Repeater {
        model: seg.values
        Btn {
            required property var modelData
            required property int index
            objectName: seg.objectNames[index] || ""
            outerRadius: seg.outerRadius
            inset: seg.inset
            implicitHeight: seg.segHeight
            width: seg.widthOf(index) >= 0 ? seg.widthOf(index) : implicitWidth
            text: String(seg.labels[index])
            active: seg.current === modelData
            enabledLook: seg.enabledLook
            onClicked: seg.picked(modelData)
        }
    }
}
