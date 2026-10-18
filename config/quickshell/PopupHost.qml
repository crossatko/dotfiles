import QtQuick
import Quickshell
import Quickshell.Wayland

// One per screen. A full-screen transparent overlay (click outside = close) holding the
// popup card, hung off the bar edge at the x position of the chip that opened it.
PanelWindow {
    id: host

    required property var modelData
    screen: modelData
    readonly property bool active: Popups.name !== "" && Popups.screen === modelData.name
    readonly property bool hasBar: Popups.bars[modelData.name] !== undefined

    // Open/close as ONE unit: the card's content is loaded first and the card starts moving a moment
    // later (so it never animates half-built), and on close the content stays until the fade is done
    // (so it fades together with the card instead of vanishing first). `content` is what is shown;
    // Popups.name is only the request.
    property string content: ""
    property real t: 0
    Behavior on t { NumberAnimation { duration: host.active ? 150 : 100; easing.type: host.active ? Easing.OutCubic : Easing.InQuad } }
    onActiveChanged: {
        if (active) { content = Popups.name; opener.restart() }
        else { opener.stop(); t = 0 }
    }
    Connections {
        target: Popups
        function onNameChanged() { if (host.active && Popups.name !== "") host.content = Popups.name }   // switching popups: swap in place
    }
    onTChanged: if (t === 0 && !active) content = ""
    Timer { id: opener; interval: 40; onTriggered: if (host.active) host.t = 1 }
    visible: active || t > 0.01
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-popup"
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors { left: true; right: true; top: true; bottom: true }

    MouseArea { anchors.fill: parent; onClicked: Popups.close() }

    Rectangle {
        id: card
        readonly property bool atTop: Popups.edgeOf(host.modelData.name) === "top"
        // bar edge: past the bar (incl. a floating bar's gap) plus popupGap; other sides: `side` from the screen
        // edge (docked keeps the old 8 px, floating lines up with the bar's gapOut)
        readonly property real inset: (host.hasBar ? Theme.barReserve : 0) + Theme.popupGap
        readonly property real side: Theme.barFloating ? Theme.edgeGap : 8

        width: host.content === "center" ? 420 : host.content === "cal" ? 390 : host.content === "ha" || host.content === "ai" ? 400 : 380
        // the control / notification center never gets shorter than 480 px; the others fit their content
        readonly property real minHeight: host.content === "center" ? 480 : 0
        height: Math.min(host.height - inset - side, Math.max(minHeight, (loader.item ? loader.item.implicitHeight : 60) + 24))
        // Plain computed position, not anchors: switching a card between top / bottom anchors at runtime
        // (the bar edge is configurable per monitor now) left stale anchors behind: a full-height slab on one
        // monitor, a background-less squashed card on the other.
        x: host.width - width - Math.max(side, Math.min(Popups.right, host.width - width - side))
        y: atTop ? inset : host.height - inset - height

        radius: Theme.radius
        color: Theme.alpha(Theme.bg, Math.min(1, Theme.barOpacity + 0.3))
        border.width: 1
        border.color: Theme.alpha(Theme.overlay, 0.5)

        opacity: host.t
        transform: Translate { y: (1 - host.t) * (card.atTop ? -28 : 28) }

        MouseArea { anchors.fill: parent }   // clicks on the card don't reach the close-scrim

        Loader {
            id: loader
            anchors { fill: parent; margins: 12 }
            source: ({
                center: "CenterPanel.qml", net: "NetPanel.qml", bt: "BtPanel.qml",
                cal: "CalPanel.qml", media: "MediaPanel.qml", audio: "AudioPanel.qml", ha: "HaPanel.qml",
                ai: "AiPanel.qml"
            })[host.content] || ""
        }
    }
}
