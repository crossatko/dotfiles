import QtQuick
import QtQuick.Layouts

// A compact L1 tile with a feature glyph, a one- or two-word label and a MonitorStateCell at its end (Settings >
// Monitors: Bar / Lock clock / Desktop clock per monitor; the monitor strip's "All"). The whole tile toggles; the glyph
// is accent while on. `primary` = the PrimaryTag dot after the label. Like Toggle it never flips itself: bind `checked`
// to the real state and act on `toggled(want)`. `enabledLook: false` locks it (the cell shows a lock, input is ignored,
// the reason goes in `tip`); `tip` is otherwise a plain hover note (TipBubble). Keyboard: Tab focuses it (focus edge),
// Space / Enter toggle.
Rectangle {
    id: ls
    property string icon: ""
    property string label: ""
    property bool checked: false
    property bool enabledLook: true
    property bool primary: false
    property string tip: ""
    property string glyphOn: Icons.eye
    property string glyphOff: Icons.eyeOff
    signal toggled(bool want)

    function flip() { if (ls.enabledLook) ls.toggled(!ls.checked) }

    implicitHeight: Theme.rowH
    implicitWidth: row.implicitWidth + 2 * Theme.padSm + cell.implicitWidth
    radius: Theme.radiusPage
    color: glow.hovered ? Theme.itemHover : Theme.itemFill
    border.width: 1
    border.color: ls.activeFocus ? Theme.alpha(Theme.fg, 0.6) : Theme.alpha(Theme.fg, 0)
    Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
    Behavior on border.color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }

    activeFocusOnTab: true
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { ls.flip(); e.accepted = true }
    }
    Accessible.role: Accessible.CheckBox
    Accessible.name: ls.label
    Accessible.checked: ls.checked

    HoverGlow { id: glow; area: tapArea; radius: ls.radius }
    PressFeedback { area: tapArea }
    // the label part toggles too; the cell has its own area (and the tooltip)
    MouseArea {
        id: tapArea
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: cell.left }
        hoverEnabled: true
        cursorShape: ls.enabledLook ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: ls.flip()
    }
    TipBubble { anchors.fill: tapArea; text: ls.tip; shown: tapArea.containsMouse || ls.activeFocus }

    RowLayout {
        id: row
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: cell.left; leftMargin: Theme.padSm; rightMargin: Theme.padSm }
        spacing: Theme.gapRow
        Icon {
            text: ls.icon
            font.pixelSize: Theme.iconMd
            horizontalAlignment: Text.AlignHCenter
            Layout.preferredWidth: Theme.iconLg
            color: !ls.enabledLook ? Theme.muted : ls.checked ? Theme.accent : Theme.fgDim
            Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
        }
        Label {
            id: lbl
            text: ls.label; font.pixelSize: Theme.fontSmall; color: ls.enabledLook ? Theme.fg : Theme.fgDim; elide: Text.ElideRight; Layout.fillWidth: true
            rightPadding: ls.primary ? dot.implicitWidth + Theme.gapTight : 0
            // the primary's dot right after the (possibly elided) label
            PrimaryTag { id: dot; visible: ls.primary; compact: true; x: lbl.contentWidth + Theme.gapTight; anchors.verticalCenter: parent.verticalCenter }
        }
    }
    MonitorStateCell {
        id: cell
        objectName: ls.objectName !== "" ? ls.objectName + "-toggle" : ""
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        on: ls.checked
        enabledLook: ls.enabledLook
        tip: ls.tip
        glyphOn: ls.glyphOn
        glyphOff: ls.glyphOff
        radius: ls.radius
        onClicked: ls.flip()
    }
}
