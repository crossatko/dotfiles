import QtQuick

// A media hand-off button (TvButton: Send to TV, PcButton: Play on PC): an icon button like the transport's whose glyph is
// the progress: `restGlyph` at rest, search while it looks the item up, power while a TV wakes, circle-play while the
// player opens (the working ones pulse; still with motion off), check once done, warning when it failed (the tooltip
// says why), then the rest glyph again. `usable` false = shown dimmed, clicks ignored, the tooltip says why (a TV card
// whose item the PC cannot play). Fades in / out in place (`shown`): the caller keeps its slot, nothing moves.
Btn {
    id: hb
    property bool shown: false
    property bool usable: true
    property string phase: ""                      // "" | "finding" | "waking" | "opening" | "sent" | "failed"
    property string restGlyph: Icons.tv
    property string tipText: ""
    signal activated()
    readonly property bool working: phase === "finding" || phase === "waking" || phase === "opening"

    icon: true
    text: phase === "finding" ? Icons.search : phase === "waking" ? Icons.power : phase === "opening" ? Icons.circlePlay
        : phase === "sent" ? Icons.check : phase === "failed" ? Icons.warning : restGlyph
    active: working
    ink: phase === "failed" ? Theme.red : working || phase === "sent" ? Theme.accent : Theme.fg
    enabledLook: usable || phase !== ""
    opacity: shown ? 1 : 0
    visible: opacity > 0
    enabled: shown
    Accessible.name: tipText
    Behavior on opacity { NumberAnimation { duration: Motion.ms(Motion.moveMs); easing.type: Motion.easeEnter } }
    onClicked: if (hb.usable || hb.working) hb.activated()

    SequentialAnimation on inkOpacity {
        running: hb.working && !Motion.reduced
        loops: Animation.Infinite
        onRunningChanged: if (!running) hb.inkOpacity = 1
        NumberAnimation { to: 0.35; duration: Theme.busyPulseMs; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: Theme.busyPulseMs; easing.type: Easing.InOutSine }
    }

    HoverHandler { id: hh }
    TipBubble {
        anchors.fill: parent
        shown: hh.hovered && hb.shown && hb.tipText !== ""
        text: hb.tipText
    }
}
