pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

// One per screen. A full-screen transparent overlay (click outside = close) holding the
// popup card, hung off the bar edge at the x position of the chip that opened it.
// PanelWindow is an uncreatable interface type in Quickshell's qmltypes (the real window exists at runtime)
// qmllint disable uncreatable-type
PanelWindow {
    id: host

    required property var modelData
    screen: modelData
    readonly property bool active: Popups.name !== "" && Popups.screen === modelData.name
    readonly property bool hasBar: Popups.bars[modelData.name] !== undefined

    // Motion (tokens: Theme.popup*; speed / curve / style from Settings -> Animations, Motion.qml). Everything is driven by two things:
    //  - `t` (0..1): open/close progress of the whole card (fade + a small scale/slide from the bar side). Ease-out
    //    on open, faster ease-in on close; interrupting either retargets from the current value.
    //  - switching chips while open: `content` (what is shown; Popups.name is only the request) is swapped between
    //    a fade-out and a fade-in of the content, while the card's x / width / height glide to the new target
    //    (Behaviors enabled only during that `morphing` window, so a panel resizing itself later is not smoothed twice).
    // The card's content is loaded before the card starts moving (cold open: short delay for the layer surface to
    // map), and on close it stays until the fade is done.
    property string content: ""
    property real center: 1e6            // chip centre the card hangs from; updated together with `content`
    property real t: 0
    property real contentOpacity: 1
    property bool morphing: false
    property string pending: ""
    property real pendingCenter: 1e6
    // Open / close are two explicit animations, started from the current t (interrupt-safe). NOT a Behavior with
    // `easing.type: host.active ? open : close`: that binding was still the OPEN easing when the close started, so
    // with an overshooting curve (Back) the close crossed t = 0 at ~35 % of its time, `visible` (t > 0.01) dropped
    // and the popup vanished mid-fade (measured 2026-10-20: t 1 -> 0 in 72 of 200 ms, then -0.1 while hidden).
    // A retarget runs only the remaining distance's share of the duration.
    NumberAnimation {
        id: openAnim
        target: host; property: "t"; to: 1
        easing.type: Theme.popupEaseOpen
    }

    NumberAnimation {
        id: closeAnim
        target: host; property: "t"; to: 0
        easing.type: Theme.popupEaseClose
        onFinished: host.finishClose()
    }
    function startOpen() {
        closeAnim.stop()
        if (t >= 1 && !openAnim.running) return
        openAnim.stop()
        openAnim.duration = Math.round(Theme.popupOpenMs * Math.max(0, Math.min(1, 1 - t)))
        openAnim.start()
    }
    function startClose() {
        openAnim.stop()
        if (t <= 0) { finishClose(); return }
        closeAnim.stop()
        closeAnim.duration = Math.round(Theme.popupCloseMs * Math.max(0, Math.min(1, t)))
        closeAnim.start()
    }
    // the close has finished: drop the content (the window hides with t = 0)
    // open / close in progress (or stopped half way): the card is in motion
    readonly property bool moving: openAnim.running || closeAnim.running || opener.running || (t > 0 && t < 1)
    function finishClose() { if (!active) { t = 0; content = ""; contentOpacity = 1; morphing = false } }

    function sync() {
        if (active) {
            if (content === "") {                 // cold open: window is hidden
                morphing = false; contentOpacity = 1
                content = Popups.name; center = Popups.center
                opener.restart()
            } else if (content !== Popups.name) { // switching (also: another chip clicked while closing)
                pending = Popups.name; pendingCenter = Popups.center
                swap.restart()
                if (!opener.running) startOpen()  // was closing: come back
            } else if (!opener.running) {         // same popup re-requested while fading out: resume
                startOpen()
            }
        } else {
            opener.stop(); swap.stop(); morphTimer.stop(); startClose()
        }
    }
    onActiveChanged: { if (!active) armed = false; sync(); if (active) keys.forceActiveFocus() }
    Connections {
        target: Popups
        function onNameChanged() { if (host.active) host.sync() }
    }
    Timer { id: opener; interval: 40; onTriggered: if (host.active) host.startOpen() }
    Timer { id: morphTimer; interval: Theme.popupMoveMs + 60; onTriggered: host.morphing = false }
    SequentialAnimation {
        id: swap
        NumberAnimation { target: host; property: "contentOpacity"; to: 0; duration: Theme.popupFadeOutMs; easing.type: Easing.InQuad }
        ScriptAction { script: { host.morphing = true; morphTimer.restart(); host.content = host.pending; host.center = host.pendingCenter } }
        NumberAnimation { target: host; property: "contentOpacity"; to: 1; duration: Theme.popupFadeInMs; easing.type: Easing.OutQuad }
    }
    visible: active || t > 0 || closeAnim.running
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-popup"
    BackgroundEffect.blurRegion: Region { regions: glass.instances }
    Glass { id: glass; root: host.contentItem; active: visible }
    // OnDemand keyboard focus (Wi-Fi password field) only once the popup has been open for a moment. If the surface
    // maps already asking for keyboard focus, Hyprland pulls the pointer off the bar (wl_pointer.leave) and the
    // popup never gets it; with the mouse at rest the next click on the same chip then went nowhere (it needed a
    // 1 px move to close the popup). Flipping to OnDemand after the map keeps the pointer on the bar.
    property bool armed: false
    Timer { id: armTimer; interval: 150; running: host.active; onTriggered: host.armed = true }
    WlrLayershell.keyboardFocus: armed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors { left: true; right: true; top: true; bottom: true }

    // Esc closes. A focused field inside a card (Wi-Fi password) handles its own Esc first.
    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: Popups.close()
    }

    MouseArea { id: scrim; anchors.fill: parent; onClicked: Popups.close() }

    // The bar strip (bar + a floating bar's gap) is cut out of this window's input region, so clicks there
    // go straight to the bar underneath: clicking another chip opens its popup in ONE click (Popups.toggle
    // swaps them) instead of the scrim eating the click just to close the current one.
    Item {
        id: barStrip
        width: parent.width
        height: host.hasBar ? Theme.barReserve : 0
        y: card.atTop ? 0 : parent.height - height
    }
    mask: Region { item: scrim; regions: [ Region { item: barStrip; intersection: Intersection.Subtract } ] }

    Rectangle {
        id: card
        readonly property bool isGlassItem: true
        readonly property bool atTop: Popups.edgeOf(host.modelData.name) === "top"
        // Glass: the card's glass region is the card itself (Glass.qml maps it through the Scale / Translate below, so
        // it grows / slides with the card every frame). Its STRENGTH follows the card's opacity only on a compositor
        // whose solid_glass honours the layer's content alpha (the fork patch "glass alpha from layer content", see
        // AGENTS.md); on the current build the glass cannot fade, so its region shrinks away in the last part of the
        // motion instead (glassScale below, Theme.glassScaleAt).
        // bar edge: past the bar (incl. a floating bar's CURRENT gap, so it follows the compact animation) plus popupGap; other sides: `side` from the screen
        // edge (docked keeps the old 8 px, floating lines up with the bar's gapOut)
        readonly property real inset: (host.hasBar ? Theme.barHeight + Popups.barGapOf(host.modelData.name) : 0) + Theme.popupGap
        readonly property real side: Theme.barFloating ? Theme.edgeGap : 8

        // target size; the card itself follows it with a Behavior while `morphing`
        readonly property real targetW: host.content === "center" ? 420 : host.content === "cal" ? 390 : host.content === "ha" || host.content === "ai" ? 400 : 380
        // the control / notification center never gets shorter than 480 px; the others fit their content
        readonly property real minHeight: host.content === "center" ? 480 : 0
        readonly property real targetH: Math.min(host.height - inset - side, Math.max(minHeight, ((loader.item as Item)?.implicitHeight ?? 60) + 24))
        // x is computed from the TARGET width, so x and width animate together (same curve) instead of x chasing a
        // moving width. y hangs off the bar edge, so the card grows away from the bar.
        // Plain computed position, not anchors: switching a card between top / bottom anchors at runtime
        // (the bar edge is configurable per monitor now) left stale anchors behind: a full-height slab on one
        // monitor, a background-less squashed card on the other.
        // centred on the chip that opened it, clamped to `side` from both screen edges
        width: targetW
        height: targetH
        x: Math.max(side, Math.min(host.center - targetW / 2, host.width - targetW - side))
        y: atTop ? inset : host.height - inset - height
        Behavior on x { enabled: host.morphing; NumberAnimation { duration: Theme.popupMoveMs; easing.type: Theme.popupEaseMove } }
        Behavior on width { enabled: host.morphing; NumberAnimation { duration: Theme.popupMoveMs; easing.type: Theme.popupEaseMove } }
        Behavior on height { enabled: host.morphing; NumberAnimation { duration: Theme.popupMoveMs; easing.type: Theme.popupEaseMove } }

        radius: Theme.radius
        color: Theme.alpha(Theme.bg, Theme.cardFill)
        border.width: 1
        border.color: Theme.alpha(Theme.overlay, 0.5)

        opacity: Math.max(0, Math.min(1, host.t))
        // glass region scale (Glass.qml): 1, except the last part of the motion on a compositor whose glass cannot fade
        readonly property real glassScale: Theme.glassScaleAt(host.t)
        // fade-in/out as one flattened texture (no text-over-background double blending), only while opening/closing
        layer.enabled: (openAnim.running || closeAnim.running) && !host.morphing
        // a small scale from the bar side + slide, so it feels attached to the bar
        transform: [
            Scale {
                origin.x: Math.max(0, Math.min(card.width, host.center - card.x))
                origin.y: card.atTop ? 0 : card.height
                xScale: Theme.popupScaleFrom + (1 - Theme.popupScaleFrom) * host.t
                yScale: Theme.popupScaleFrom + (1 - Theme.popupScaleFrom) * host.t
            },
            Translate { y: (1 - host.t) * (card.atTop ? -Theme.popupSlidePx : Theme.popupSlidePx) }
        ]

        MouseArea { anchors.fill: parent }   // clicks on the card don't reach the close-scrim

        // Content keeps its TARGET size (not the animating card size), so it never re-lays out per frame while the
        // card resizes; the card just reveals / crops it. Clipped only while morphing (dropdowns may overhang otherwise).
        Item {
            x: 12; y: 12
            width: card.width - 24; height: card.height - 24
            clip: host.morphing
            opacity: host.contentOpacity
            Loader {
                id: loader
                width: card.targetW - 24; height: card.targetH - 24
                source: ({
                    center: "CenterPanel.qml", net: "NetPanel.qml", bt: "BtPanel.qml",
                    cal: "CalPanel.qml", media: "MediaPanel.qml", audio: "AudioPanel.qml", ha: "HaPanel.qml",
                    ai: "AiPanel.qml"
                })[host.content] || ""
            }
        }
    }
}
