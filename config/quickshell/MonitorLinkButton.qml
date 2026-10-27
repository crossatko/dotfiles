import QtQuick

// Link toggle between two neighbouring monitor chips (MonitorChooser `linkable`: Settings > Bar and > Wallpaper). Linked
// = accent chain, unlinked = muted broken chain, an opaque base under its tint. Tab focuses it, Space / Enter toggle.
// Emits `toggled` only; the page decides what linking means (copy the edited monitor's wallpaper / bar layout to the
// newly linked one).
Rectangle {
    id: btn
    property bool linked: false
    property string tip: ""                // accessible name, e.g. "Link Monitor A and Monitor B"
    signal toggled()

    implicitWidth: 26
    implicitHeight: 26
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    z: 5
    activeFocusOnTab: visible
    Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { btn.toggled(); e.accepted = true } }
    Accessible.role: Accessible.CheckBox
    Accessible.name: tip
    Accessible.checked: linked
    // opaque (the card borders must not show through): the tint blended over the surface colour, so HoverGlow (drawn over
    // this fill, under the glyph) sees one solid colour
    color: Qt.tint(Theme.surface, btn.linked ? Theme.alpha(Theme.accent, glow.hovered ? 0.34 : 0.22) : Theme.alpha(Theme.fg, glow.hovered ? 0.14 : 0.05))
    border.width: 1
    border.color: activeFocus ? Theme.accent : linked ? Theme.alpha(Theme.accent, 0.85) : Theme.alpha(Theme.overlay, 0.6)
    Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }

    HoverGlow { id: glow; area: hoverArea; radius: btn.radius }
    Icon {
        anchors.centerIn: parent
        text: btn.linked ? Icons.link : Icons.linkOff            // link / link-slash
        font.pixelSize: Theme.iconSm
        color: btn.linked ? Theme.accent : Theme.muted
    }
    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.toggled()
    }
}
