import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

// Volume / brightness pill, bottom-center of the focused monitor. Volume is observed from
// Pipewire (so wpctl keybinds just work); brightness when the keys step it (Brightness.stepped)
PanelWindow {
    id: osd

    property var bars: ({})
    property var target: Quickshell.screens[0]
    property string kind: "volume"
    property real value: 0
    property bool muted: false
    property bool shown: false
    property bool armed: false          // ignore the volume values Pipewire reports while starting

    screen: target
    visible: shown
    anchors { bottom: true }
    margins.bottom: 70 + (bars[(screen ? screen.name : "")] === "bottom" ? Theme.barReserve : 0)   // above a (floating) bottom bar
    implicitWidth: 320
    implicitHeight: 56
    color: "transparent"
    exclusiveZone: -1                  // ignore the monitor's reserved area (the pinned-video strip), so it stays in the screen corner
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-osd"
    mask: Region {}                      // never takes input

    function focusScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        const s = Quickshell.screens.find(x => x.name === name) || Quickshell.screens[0]
        if (!shown && s !== target) target = s
    }
    function show(k, v, m) {
        focusScreen()
        kind = k; value = Math.max(0, Math.min(1, v)); muted = m
        shown = true
        hideTimer.restart()
    }

    Timer { interval: 3000; running: true; onTriggered: osd.armed = true }
    Timer { id: hideTimer; interval: 1500; onTriggered: osd.shown = false }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property var audio: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
    Connections {
        target: osd.audio
        function onVolumeChanged() { if (osd.armed) osd.show("volume", osd.audio.volume, osd.audio.muted) }
        function onMutedChanged() { if (osd.armed) osd.show("volume", osd.audio.volume, osd.audio.muted) }
    }

    // brightness: the keys go through the Brightness backend (qs ipc call brightness step N), shown here
    Connections {
        target: Brightness
        function onStepped(name, percent) { osd.show("brightness", percent / 100, false) }
    }
    function brightness() {                // legacy `qs ipc call osd brightness`: show the focused display's value
        const n = Brightness.focused()
        if (n) osd.show("brightness", Brightness.percentOf(n) / 100, false)
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.alpha(Theme.bg, Math.min(1, Theme.barOpacity + 0.3))
        border.width: 1
        border.color: Theme.alpha(Theme.overlay, 0.5)

        RowLayout {
            anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
            spacing: 14
            Icon {
                font.pixelSize: 22
                color: osd.muted ? Theme.muted : Theme.accent
                text: osd.kind === "brightness" ? "\uf185" : osd.muted ? "\uf6a9" : osd.value < 0.01 ? "\uf026" : osd.value < 0.5 ? "\uf027" : "\uf028"
            }
            Rectangle {
                Layout.fillWidth: true
                height: 6
                radius: Math.min(height / 2, Theme.inner(Theme.radius, 18))
                color: Theme.alpha(Theme.fg, 0.15)
                Rectangle {
                    width: parent.width * (osd.muted ? 0 : osd.value)
                    height: parent.height
                    radius: parent.radius
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 80 } }
                }
            }
            Label { text: osd.muted ? "muted" : Math.round(osd.value * 100) + "%"; Layout.preferredWidth: 46; horizontalAlignment: Text.AlignRight }
        }
    }
}
