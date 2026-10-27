import QtQuick

// Small text button used inside the popups.
Rectangle {
    id: btn
    property string text: ""
    property bool active: false
    property bool enabledLook: true
    property bool icon: false     // text is a Font Awesome glyph
    property bool activeFill: true   // false: an active button draws no fill / outline of its own (Segmented's gliding marker does)
    // Concentric corner: the radius of whatever the button sits in and the padding between them.
    // Default = directly in a popup card (outer R, 12 px padding) = Theme.radiusItem. A button inside an
    // item-level box sets e.g. outerRadius: Theme.radiusItem; inset: 8. Never more than a third of the
    // height, so a small button stays a rounded rectangle instead of turning into a pill at large R.
    property real outerRadius: Theme.radius
    property real inset: 12
    signal clicked(var mouse)

    implicitWidth: label.implicitWidth + 2 * Theme.padSm + 2
    implicitHeight: Theme.controlH
    radius: Math.min(Theme.inner(outerRadius, inset), Math.floor(height / 3))
    opacity: enabledLook ? 1 : Theme.disabledOpacity
    color: active && activeFill ? (glow.hovered ? Theme.accentHover : Theme.accentFill)
         : active ? Theme.alpha(Theme.fg, 0)
         : glow.hovered ? Theme.itemActive
         : Theme.itemFill
    border.width: active && activeFill ? 1 : 0
    border.color: Theme.accentEdge
    Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
    Behavior on border.color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }

    HoverGlow { id: glow; area: hoverArea; radius: btn.radius }
    PressFeedback { area: hoverArea }
    Label { id: label; anchors.centerIn: parent; text: btn.text; font.pixelSize: btn.icon ? Theme.fontSize : Theme.fontSmall; font.family: btn.icon ? Theme.iconFont : Theme.font; font.styleName: btn.icon ? "Regular" : "";  color: btn.active ? Theme.accent : Theme.fg }
    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => btn.clicked(mouse)
    }
}
