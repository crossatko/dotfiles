import QtQuick
import QtQuick.Layouts

// The reminder's minutes as one big editable number: "[-]  15  [+]" with the unit under it. The owner holds the value
// (DateStepper pattern): `value` is what it shows, every change the user makes is `moved(v)` and the owner sets `value`.
// Typed digits are checked as they come: more than `max` is replaced by `max` at once and the unit line says the limit;
// an empty field or 0 moves 0 (the owner refuses to start) and the line says the range. Buttons / wheel step by `step`
// within min..max. Enter = accepted().
ColumnLayout {
    id: st
    property int value: 15
    property int min: 1
    property int max: 1440
    property int step: 1
    property string unit: "minutes"
    property string limit: ""          // why the typed number was changed / is refused: shown in place of the unit
    signal moved(int value)
    signal accepted()
    function focusField() { field.forceActiveFocus(); field.selectAll() }

    function stepBy(d) {
        const v = Math.max(min, Math.min(max, value + d))
        limit = ""
        if (v !== value) moved(v)
        else field.text = String(value)          // 0 typed, then "-": back to the shown value
    }
    function typed() {
        const t = field.text
        const n = t === "" ? 0 : parseInt(t, 10)
        if (n > max) { field.text = String(max); limit = "at most " + max + " " + unit; moved(max); return }
        limit = n < min ? min + " to " + max + " " + unit : ""
        moved(n)
    }
    // a value from outside (preset, step): show it; the field's own text already says it after a typed change
    onValueChanged: {
        if (field.text === "" ? value === 0 : parseInt(field.text, 10) === value) return
        field.text = String(value)
        limit = ""
    }

    spacing: 0
    WheelHandler { onWheel: ev => st.stepBy(ev.angleDelta.y > 0 ? st.step : -st.step) }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.controlGap
        Btn {
            icon: true; text: Icons.minus; tip: "Less"
            minWidth: Theme.rowH; implicitHeight: Theme.rowH
            enabledLook: st.value > st.min
            onClicked: st.stepBy(-st.step)
        }
        // the font of the numeral (BigDigits) without drawing one
        BigDigits { id: look; visible: false }
        TextInput {
            id: field
            Layout.fillWidth: true
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            font: look.font
            color: st.value >= st.min ? Theme.fg : Theme.muted
            selectionColor: Theme.accent
            selectedTextColor: Theme.bg
            maximumLength: String(st.max).length
            inputMethodHints: Qt.ImhDigitsOnly
            validator: IntValidator { bottom: 0 }
            text: String(st.value)
            onTextEdited: st.typed()
            onAccepted: st.accepted()
            Keys.onUpPressed: st.stepBy(st.step)
            Keys.onDownPressed: st.stepBy(-st.step)
            Keys.onEscapePressed: { Popups.escAt = Date.now(); field.focus = false }
        }
        Btn {
            icon: true; text: Icons.plus; tip: "More"
            minWidth: Theme.rowH; implicitHeight: Theme.rowH
            enabledLook: st.value < st.max
            onClicked: st.stepBy(st.step)
        }
    }
    Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: st.limit !== "" ? st.limit : st.unit
        color: st.limit !== "" ? Theme.red : Theme.fgDim
        font.pixelSize: Theme.fontSmall
    }
}
