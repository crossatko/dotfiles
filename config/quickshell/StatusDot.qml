import QtQuick

// A small round state marker (8 px): a running VM, an online machine, a calendar colour, the recording light.
// `tint` = its colour (semantic: green ok / red recording or problem / a calendar's own colour); `pulse` breathes it
// slowly (recording), on the heartbeat tokens: a state, not a transition, so it is not speed-scaled.
Rectangle {
    id: dot
    property color tint: Theme.accent
    property bool pulse: false
    property int size: 8

    implicitWidth: size
    implicitHeight: size
    radius: size / 2
    color: tint

    SequentialAnimation on opacity {
        running: dot.pulse; loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: Theme.heartbeatMs; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: Theme.heartbeatMs; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) dot.opacity = 1
    }
}
