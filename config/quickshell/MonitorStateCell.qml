import QtQuick

// The per-monitor on / off control of Settings: a square cell at the end of a MonitorChip / LabelSwitch showing the
// state as a glyph pair (eye = shown here, eye-slash = hidden; `glyphOn` / `glyphOff`), accent while on, muted while
// off (DESIGN.md: colour carries state; the same eye-slash as OffMark on the dimmed sections). No knob: the cell IS
// the switch. Click = `clicked()` (the owner flips the real state; this never flips itself). `enabledLook: false`
// = locked (a lock glyph, no hover, the reason in `tip`). A hairline on its left separates it from the chip's body
// (`divider`); its right corners follow the chip (`radius`). Hover = a wash + the tooltip (`tip`, also the accessible
// name); press = the glyph sinks (PressFeedback).
Item {
    id: cell
    property bool on: false
    property bool enabledLook: true
    property string tip: ""
    property string glyphOn: Icons.eye
    property string glyphOff: Icons.eyeOff
    property real radius: 0
    property bool divider: true
    signal clicked()

    implicitWidth: Theme.rowH                             // a square in a rowH chip
    implicitHeight: Theme.rowH
    Accessible.role: Accessible.CheckBox
    Accessible.name: tip
    Accessible.checked: on

    Rectangle {
        anchors.fill: parent
        topRightRadius: cell.radius; bottomRightRadius: cell.radius
        topLeftRadius: 0; bottomLeftRadius: 0
        color: Theme.alpha(Theme.fg, tap.containsMouse && cell.enabledLook ? 0.08 : 0)
        Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
    }
    Rectangle { visible: cell.divider; x: 0; y: Theme.gapRow; width: 1; height: parent.height - 2 * Theme.gapRow; color: Theme.edge }
    // the two glyphs cross-fade (a swap would cut)
    Item {
        id: glyphs
        anchors.centerIn: parent
        width: Theme.iconMd + 4; height: Theme.iconMd + 4
        Icon {
            anchors.centerIn: parent
            text: cell.enabledLook ? cell.glyphOn : Icons.lock
            font.pixelSize: Theme.iconMd
            color: cell.enabledLook ? Theme.accent : Theme.muted
            opacity: cell.on || !cell.enabledLook ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
        }
        Icon {
            anchors.centerIn: parent
            text: cell.glyphOff
            font.pixelSize: Theme.iconMd
            color: Theme.muted
            opacity: cell.on || !cell.enabledLook ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
        }
    }
    PressFeedback { area: tap; target: glyphs; depth: 3 }
    MouseArea {
        id: tap
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: cell.enabledLook ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (cell.enabledLook) cell.clicked()
    }
    TipBubble { anchors.fill: tap; text: cell.tip; shown: tap.containsMouse }
}
