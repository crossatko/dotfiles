import QtQuick

// Link toggle between two neighbouring monitor cards (Settings > Bar and > Wallpaper & theme). Linked = accent chain,
// unlinked = muted broken chain. It sits in a round notch cut into the cards (MonitorCardRow notchesOf / NotchMask),
// above them (z), with an opaque base under its tint. Emits `toggled` only; the page decides what linking means
// (copy the edited monitor's wallpaper / bar layout to the newly linked one).
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
    Accessible.role: Accessible.CheckBox
    Accessible.name: tip
    Accessible.checked: linked
    // opaque (the card borders must not show through): the tint blended over the surface colour, so HoverGlow (drawn over
    // this fill, under the glyph) sees one solid colour
    color: Qt.tint(Theme.surface, btn.linked ? Theme.alpha(Theme.accent, glow.hovered ? 0.34 : 0.22) : Theme.alpha(Theme.fg, glow.hovered ? 0.14 : 0.05))
    border.width: 1
    border.color: linked ? Theme.alpha(Theme.accent, 0.85) : Theme.alpha(Theme.overlay, 0.6)
    Behavior on color { ColorAnimation { duration: 100 } }

    HoverGlow { id: glow; area: hoverArea; radius: btn.radius }
    Icon {
        anchors.centerIn: parent
        text: btn.linked ? "" : ""            // link / link-slash
        font.pixelSize: 12
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
