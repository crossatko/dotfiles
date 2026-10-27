pragma ComponentBehavior: Bound
import QtQuick

// Segmented choice: a row of Btns 2 px apart, the one whose value equals `current` is `active`.
// `values` are what picked(v) emits, `labels` what the buttons show (defaults to the values). Size and the
// concentric radius are set like Btn's (outerRadius / inset of the box it sits in). Never changes `current`
// itself; picked() fires even while !enabledLook (the user decides).
// The active look is one marker under the row that glides to the picked button (GlideHighlight).
Item {
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
    property real segHeight: Theme.controlH
    property var objectNames: []                   // optional per-button objectName (test hooks)
    signal picked(var value)

    readonly property real spacing: 2
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    // keyboard: Tab focuses the row (the marker gets a brighter outline), Left / Right pick the neighbour
    activeFocusOnTab: true
    Keys.onLeftPressed: step(-1)
    Keys.onRightPressed: step(1)
    function step(d) {
        const i = values.indexOf(current)
        const n = i < 0 ? (d > 0 ? 0 : values.length - 1) : Math.max(0, Math.min(values.length - 1, i + d))
        if (n !== i && values[n] !== undefined) picked(values[n])
    }

    FontMetrics { id: fm; font.family: Theme.font; font.pixelSize: Theme.fontSmall }   // Btn's label font
    readonly property var naturals: (labels || []).map(l => Math.ceil(fm.advanceWidth(String(l))) + 2 * Theme.padSm + 2)   // Btn's implicitWidth
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

    GlideHighlight {
        target: { void rep.count; return rep.itemAt(seg.values.indexOf(seg.current)) }
        radius: Math.min(Theme.inner(seg.outerRadius, seg.inset), Math.floor(height / 3))   // Btn's radius
        color: Theme.accentFill
        border.width: 1
        border.color: seg.activeFocus ? Theme.accent : Theme.accentEdge
        opacity: seg.enabledLook ? 1 : Theme.disabledOpacity
    }
    // focus ring around the whole row while it has the keyboard focus
    Rectangle {
        anchors { fill: parent; margins: -3 }
        radius: Math.min(Theme.inner(seg.outerRadius, seg.inset - 3), Math.floor(height / 3))
        color: "transparent"
        border.width: 1
        border.color: Theme.alpha(Theme.fg, 0.5)
        visible: seg.activeFocus
    }
    Row {
        id: row
        spacing: seg.spacing
        Repeater {
            id: rep
            model: seg.values
            Btn {
                activeFill: false
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
}
