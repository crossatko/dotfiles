import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire

// Volume / brightness pill, bottom-center of the focused monitor. Volume is observed from
// Pipewire (so wpctl keybinds just work); brightness when the keys step it (Brightness.stepped)
// PanelWindow is an uncreatable interface type in Quickshell's qmltypes (the real window exists at runtime)
// qmllint disable uncreatable-type
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
    // above a (floating) bottom bar
    // qmllint disable missing-property
    margins.bottom: 70 + (bars[(screen ? screen.name : "")] === "bottom" ? BarConfig.reserveOf(screen) : 0)
    // qmllint enable missing-property
    implicitWidth: 320
    implicitHeight: 56
    color: "transparent"
    exclusiveZone: -1                  // ignore the monitor's reserved area (the pinned-video strip), so it stays in the screen corner
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-osd"
    BackgroundEffect.blurRegion: Region { regions: glass.instances }
    Glass { id: glass; root: osd.contentItem; active: visible }
    mask: Region {}                      // never takes input

    function focusScreen() {
        const s = Popups.focusedScreen()
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
        readonly property bool isGlassItem: true
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.alpha(Theme.bg, Theme.cardFill)
        border.width: 1
        border.color: Theme.alpha(Theme.overlay, 0.5)

        RowLayout {
            anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
            spacing: 14
            Icon {
                font.pixelSize: 22
                color: osd.muted ? Theme.muted : Theme.accent
                text: osd.kind === "brightness" ? "\uf185" : Icons.volumeGlyph(osd.muted, osd.value)
            }
            Meter {
                Layout.fillWidth: true
                radius: Math.min(height / 2, Theme.inner(Theme.radius, 18))
                color: Theme.alpha(Theme.fg, 0.15)
                value: osd.muted ? 0 : osd.value
                animMs: 80
                easingType: Easing.Linear
            }
            Label { text: osd.muted ? "muted" : Math.round(osd.value * 100) + "%"; Layout.preferredWidth: 46; horizontalAlignment: Text.AlignRight }
        }
    }
}
