import QtQuick

// Animated switch. `checked` is what the *real* state is (bind it to the connection); the switch
// only emits `toggled(wantOn)` on click and never flips itself, so it always shows the truth, and `busy`
// pulses the knob while a change is in flight.
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
        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
        Behavior on color { ColorAnimation { duration: 160 } }

        SequentialAnimation on opacity {
            running: sw.busy
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 380; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 380; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) knob.opacity = 1
        }
    }

    MouseArea {
        anchors { fill: parent; margins: -4 }
        enabled: sw.enabledLook && !sw.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled(!sw.checked)
    }
}
