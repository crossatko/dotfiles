import QtQuick

// The glass card of a small surface that opens / closes with an OpenMotion (OSD pill, dictation pill): popup-style fade,
// scale and slide towards its anchor edge (`fromTop`: the card hangs from the top edge, else from the bottom), the
// glass region shrinking in the last part of a close (Theme.glassScaleAt, read by Glass.qml through `glassScale`),
// card fill, hairline edge and the rim (GlassEdge). Content goes inside as children, drawn above the rim.
Rectangle {
    id: mc
    required property OpenMotion openMotion
    property bool fromTop: false

    readonly property bool isGlassItem: true
    readonly property real glassScale: Theme.glassScaleAt(openMotion.t)   // see PopupHost's card
    opacity: Math.max(0, Math.min(1, openMotion.t))
    layer.enabled: openMotion.moving                                     // fade as one texture
    transform: [
        Scale { origin.x: mc.width / 2; origin.y: mc.fromTop ? 0 : mc.height; xScale: mc.openMotion.popScale; yScale: mc.openMotion.popScale },
        Translate { y: (mc.fromTop ? -1 : 1) * mc.openMotion.slide }
    ]
    radius: Theme.radius
    color: Theme.alpha(Theme.bg, Theme.cardFill)
    border.width: 1
    border.color: Theme.edge
    GlassEdge { anchors.fill: parent; radius: parent.radius }   // the rim without the compositor's glass
}
