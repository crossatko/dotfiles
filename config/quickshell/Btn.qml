import QtQuick

// Small text button used inside the popups.
Rectangle {
    id: btn
    property string text: ""
    property bool active: false
    property bool enabledLook: true
    property bool icon: false     // text is a Vadivam glyph
    property string glyph: ""     // an Icons glyph before the text (icon font, iconSm): never mixed into `text` (the text font has no glyphs)
    property bool activeFill: true   // false: an active button draws no fill / outline of its own (Segmented's gliding marker does)
    property string tip: ""       // hover / keyboard-focus bubble (TipBubble): the name of an icon-only button; it also makes the button a Tab stop (Space / Enter click)
    property color ink: active ? Theme.accent : Theme.fg   // the label's colour (a state glyph: TvButton)
    property real inkOpacity: 1      // the label alone (a pulsing state glyph), the fill stays
    // Concentric corner: the radius of whatever the button sits in and the padding between them.
    // Default = directly in a popup card (outer R, 12 px padding) = Theme.radiusItem. A button inside an
    // item-level box sets e.g. outerRadius: Theme.radiusItem; inset: 8. Never more than a third of the
    // height, so a small button stays a rounded rectangle instead of turning into a pill at large R.
    property real outerRadius: Theme.radius
    property real inset: 12
    signal clicked(var mouse)

    property real minWidth: 0     // e.g. a square icon button
    implicitWidth: Math.max(minWidth, content.implicitWidth + 2 * Theme.padSm + 2)
    implicitHeight: Theme.controlH
    radius: Math.min(Theme.inner(outerRadius, inset), Math.floor(height / 3))
    opacity: enabledLook ? 1 : Theme.disabledOpacity
    color: active && activeFill ? (glow.hovered ? Theme.accentHover : Theme.accentFill)
         : active ? Theme.alpha(Theme.fg, 0)
         : glow.hovered ? Theme.itemActive
         : Theme.itemFill
    border.width: activeFocus || (active && activeFill) ? 1 : 0
    border.color: activeFocus ? Theme.alpha(Theme.fg, 0.6) : Theme.accentEdge
    Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
    Behavior on border.color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }

    activeFocusOnTab: tip !== "" && visible
    Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { btn.clicked(null); e.accepted = true } }
    Accessible.role: Accessible.Button
    Accessible.name: tip !== "" ? tip : text

    HoverGlow { id: glow; area: hoverArea; radius: btn.radius }
    PressFeedback { area: hoverArea }
    Row {
        id: content
        anchors.centerIn: parent
        spacing: Theme.controlGap
        Icon { visible: btn.glyph !== ""; anchors.verticalCenter: parent.verticalCenter; text: btn.glyph; font.pixelSize: Theme.iconSm; color: label.color }
        Label { id: label; visible: btn.text !== ""; anchors.verticalCenter: parent.verticalCenter; text: btn.text; font.pixelSize: btn.icon ? Theme.fontSize : Theme.fontSmall; font.family: btn.icon ? Theme.iconFont : Theme.font; font.styleName: btn.icon ? "Regular" : "";  color: btn.ink; opacity: btn.inkOpacity }
    }
    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => btn.clicked(mouse)
    }
    TipBubble { anchors.fill: parent; text: btn.tip; shown: glow.hovered || btn.activeFocus }
}
