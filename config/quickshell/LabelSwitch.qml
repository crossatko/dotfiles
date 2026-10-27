import QtQuick
import QtQuick.Layouts

// A compact L1 tile: leading icon, a one- or two-word label, an optional InfoTip and a Toggle at the end (Settings >
// Monitors: Bar / Lock clock / Desktop clock per monitor). Like Toggle it never flips itself: bind `checked` to the real
// state and act on `toggled(want)`. `enabledLook: false` dims it and ignores input (the reason goes in `tip`, e.g. with
// Icons.lock). Keyboard: Tab focuses it (accent-free focus edge), Space / Enter toggle.
Rectangle {
    id: ls
    property string icon: ""
    property string label: ""
    property bool checked: false
    property bool enabledLook: true
    property string tip: ""
    property string tipIcon: Icons.info
    signal toggled(bool want)

    function flip() { if (ls.enabledLook) ls.toggled(!ls.checked) }

    implicitHeight: Theme.controlH + Theme.gapRow
    implicitWidth: row.implicitWidth + Theme.padSm * 2
    radius: Theme.inner(Theme.radiusPage, Theme.pad)        // an item inside a page card
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
    // the whole tile toggles; the Toggle on top keeps its own press lens
    MouseArea { id: tapArea; anchors.fill: parent; hoverEnabled: true; cursorShape: ls.enabledLook ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: ls.flip() }

    RowLayout {
        id: row
        anchors { fill: parent; leftMargin: Theme.padSm; rightMargin: Theme.padSm }
        spacing: Theme.gapRow
        Icon {
            text: ls.icon
            font.pixelSize: Theme.iconMd
            horizontalAlignment: Text.AlignHCenter
            Layout.preferredWidth: Theme.iconLg
            color: !ls.enabledLook ? Theme.muted : ls.checked ? Theme.accent : Theme.fgDim
            Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
        }
        Label { text: ls.label; font.pixelSize: Theme.fontSmall; color: ls.enabledLook ? Theme.fg : Theme.fgDim; elide: Text.ElideRight; Layout.fillWidth: true }
        InfoTip { visible: ls.tip !== ""; text: ls.tip; icon: ls.tipIcon }
        Toggle {
            objectName: ls.objectName !== "" ? ls.objectName + "-toggle" : ""
            checked: ls.checked
            enabledLook: ls.enabledLook
            onToggled: want => { if (ls.enabledLook) ls.toggled(want) }
        }
    }
}
