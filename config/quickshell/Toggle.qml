import QtQuick

// Animated switch. `checked` is what the *real* state is (bind it to the connection); the switch
// only emits `toggled(wantOn)` on click and never flips itself, so it always shows the truth, and `busy`
// pulses the knob while a change is in flight.
// Pressed / moving: a small liquid-glass lens (GlassLens, Settings > Glass values) swells over the knob and refracts it
// with the track and card around it: while pressed and while the knob slides after a click (also when the real state
// arrives later, up to `flipWaitMs`; a change nobody clicked for has no lens), then it shrinks back. The slide and `grow`
// run on the popup motion tokens (Settings > Animations; none = instant). Nothing of it exists at rest; without a usable
// lens (software scene graph) the knob stays as it is.
Item {
    id: sw

    property bool checked: false
    property bool busy: false
    property bool enabledLook: true
    signal toggled(bool wantOn)

    implicitWidth: 42
    implicitHeight: 22
    opacity: enabledLook ? 1 : 0.45

    readonly property real r: Math.min(height / 2, Theme.radius * 2)   // follows the theme: square at radius 0

    Rectangle {
        id: track
        anchors.fill: parent
        radius: sw.r
        color: sw.checked ? Theme.alpha(Theme.accent, 0.38) : Theme.alpha(Theme.fg, 0.10)
        border.width: 1
        border.color: sw.checked ? Theme.alpha(Theme.accent, 0.9) : Theme.alpha(Theme.overlay, 0.7)
        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }
        HoverGlow { area: tap; radius: sw.r }
    }

    Rectangle {
        id: knob
        readonly property real pad: 3
        width: sw.height - pad * 2 - 2
        height: width
        radius: Theme.inner(sw.r, pad + 1)     // knob sits pad + 1 inside the track
        y: (sw.height - height) / 2
        x: sw.checked ? sw.width - width - pad - 1 : pad + 1
        color: sw.checked ? Theme.accent : Theme.muted
        Behavior on x { NumberAnimation { id: slide; duration: Theme.popupMoveMs; easing.type: Theme.popupEaseMove } }
        Behavior on color { ColorAnimation { duration: 160 } }

        SequentialAnimation on opacity {
            running: sw.busy
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: Theme.busyPulseMs; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: Theme.busyPulseMs; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) knob.opacity = 1
        }
    }

    // ---- lens ----
    property bool userFlip: false          // the next slide was asked for by a click
    readonly property int flipWaitMs: 5000
    Timer { id: flipWait; interval: sw.flipWaitMs; onTriggered: sw.userFlip = false }
    readonly property bool lensWanted: tap.pressed || (slide.running && userFlip)
    Connections { target: slide; function onRunningChanged() { if (!slide.running) sw.userFlip = false } }
    property real grow: 0
    property Item host: null
    onLensWantedChanged: {
        if (lensWanted && !host) host = lens.findHost(sw)
        growAnim.stop()
        growAnim.to = lensWanted ? 1 : 0
        growAnim.easing.type = lensWanted ? Theme.popupEaseOpen : Theme.popupEaseClose
        growAnim.duration = lensWanted ? Math.round(Theme.popupFadeInMs * Math.max(0, Math.min(1, 1 - grow)))
                                       : Math.round(Theme.popupCloseMs * Math.max(0, Math.min(1, grow)))
        if (growAnim.duration <= 0) grow = growAnim.to
        else growAnim.start()
    }
    NumberAnimation { id: growAnim; target: sw; property: "grow"; onFinished: if (sw.grow <= 0) sw.host = null }
    onGrowChanged: if (grow <= 0 && !lensWanted && !growAnim.running) host = null
    // knob size -> 1.4x, centred on the knob (follows it while it slides)
    readonly property real lensSize: knob.width * (1 + 0.4 * grow)
    readonly property point lensC: {
        void [knob.x, grow, width, height, x, y, host ? host.width + host.height : 0]
        return host ? sw.mapToItem(host, knob.x + knob.width / 2, knob.y + knob.height / 2) : Qt.point(0, 0)
    }
    GlassLens {
        id: lens
        host: sw.grow > 0.004 ? sw.host : null
        center: sw.lensC
        size: sw.lensSize
        cornerRadius: knob.radius * (1 - sw.grow) + sw.lensSize / 2 * sw.grow
        power: knob.radius >= knob.width / 2 - 0.5 ? 2 : 4
        amount: Math.max(0, Math.min(1, sw.grow * 3))
    }

    MouseArea {
        id: tap
        anchors { fill: parent; margins: -4 }
        enabled: sw.enabledLook && !sw.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: { sw.userFlip = true; flipWait.restart(); sw.toggled(!sw.checked) }
    }
}
