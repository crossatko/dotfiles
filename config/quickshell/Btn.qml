import QtQuick

// Small text button used inside the popups.
Rectangle {
    id: btn
    property string text: ""
    property bool active: false
    property bool enabledLook: true
    property bool icon: false     // text is a Font Awesome glyph
    // Concentric corner: the radius of whatever the button sits in and the padding between them.
    // Default = directly in a popup card (outer R, 12 px padding) = Theme.radiusItem. A button inside an
    // item-level box sets e.g. outerRadius: Theme.radiusItem; inset: 8. Never more than a third of the
    // height, so a small button stays a rounded rectangle instead of turning into a pill at large R.
    property real outerRadius: Theme.radius
    property real inset: 12
    signal clicked(var mouse)

    implicitWidth: label.implicitWidth + 22
    implicitHeight: 30
    radius: Math.min(Theme.inner(outerRadius, inset), Math.floor(height / 3))
    opacity: enabledLook ? 1 : 0.5
    color: active ? Theme.alpha(Theme.accent, 0.3)
         : glow.hovered ? Theme.alpha(Theme.fg, 0.14)
         : Theme.alpha(Theme.fg, 0.07)
    border.width: active ? 1 : 0
    border.color: Theme.alpha(Theme.accent, 0.8)
    Behavior on color { ColorAnimation { duration: 100 } }

    HoverGlow { id: glow; area: hoverArea; radius: btn.radius }
    Label { id: label; anchors.centerIn: parent; text: btn.text; font.pixelSize: btn.icon ? 14 : 12; font.family: btn.icon ? Theme.iconFont : Theme.font; font.styleName: btn.icon ? "Regular" : "";  color: btn.active ? Theme.accent : Theme.fg }
    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => btn.clicked(mouse)
    }
}
