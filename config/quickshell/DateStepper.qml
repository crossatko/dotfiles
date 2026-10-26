import QtQuick
import QtQuick.Layouts
import "launcher/js/CalEvent.js" as CalEvent

// Day stepper: "‹  Wed 28 Oct  ›" in one Btn-style box. `value` is a YYYY-MM-DD date, never before `min`;
// the arrows (or the mouse wheel over it) move it a day. `sameText` replaces the date while value === min.
Rectangle {
    id: ds
    property string value: ""
    property string min: ""
    property string sameText: ""
    property real outerRadius: Theme.radius
    property real inset: 12
    readonly property bool atMin: min !== "" && value <= min
    signal moved(string value)

    function step(n) {
        let v = CalEvent.shiftDate(value, n)
        if (min !== "" && v < min) v = min
        if (v !== value) moved(v)
    }
    function pretty(s) {
        if (!CalEvent.validDate(s)) return s
        const p = s.split("-")
        return Qt.formatDate(new Date(+p[0], +p[1] - 1, +p[2]), "ddd d MMM")
    }

    implicitHeight: 30
    implicitWidth: row.implicitWidth
    radius: Math.min(Theme.inner(outerRadius, inset), Math.floor(height / 3))
    color: Theme.alpha(Theme.fg, 0.07)

    WheelHandler { onWheel: ev => ds.step(ev.angleDelta.y > 0 ? 1 : -1) }

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 0
        StepArrow { glyph: "\uf053"; r: ds.radius; off: ds.atMin; onHit: ds.step(-1) }
        Label {
            Layout.fillWidth: true
            Layout.minimumWidth: 84
            horizontalAlignment: Text.AlignHCenter
            text: ds.atMin && ds.sameText !== "" ? ds.sameText : ds.pretty(ds.value)
            color: ds.atMin && ds.sameText !== "" ? Theme.fgDim : Theme.fg
            font.pixelSize: Theme.fontSmall
        }
        StepArrow { glyph: "\uf054"; r: ds.radius; onHit: ds.step(1) }
    }

    component StepArrow: Rectangle {
        id: arrow
        property string glyph: ""
        property bool off: false
        property real r: 0
        signal hit()
        Layout.preferredWidth: 28
        Layout.fillHeight: true
        radius: r
        color: glow.hovered && !off ? Theme.alpha(Theme.fg, 0.10) : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }
        HoverGlow { id: glow; area: ma; radius: arrow.r }
        Icon { anchors.centerIn: parent; text: arrow.glyph; font.pixelSize: 10; color: arrow.off ? Theme.alpha(Theme.muted, 0.5) : Theme.fgDim }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; enabled: !arrow.off; onClicked: arrow.hit() }
    }
}
