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
    margins.bottom: 70 + (bars[(screen ? screen.name : "")] === "bottom" ? BarConfig.insetOf(screen) : 0)
    // qmllint enable missing-property
    implicitWidth: 320
    implicitHeight: 56
    color: "transparent"
    // -1 = ignore the monitor's reserved area (the pinned-video strip), so it stays in the screen corner; 0 = follow the bar
    // (Settings > Bar). This window hops between screens: a zone changed in the same tick as the screen was not applied to the
    // re-created layer surface, so it is set a moment after the screen / the option changed.
    readonly property bool respectReserved: BarConfig.respectReserved(screen)
    property int zone: -1
    onRespectReservedChanged: zoneTimer.restart()
    onScreenChanged: zoneTimer.restart()
    Component.onCompleted: zone = respectReserved ? 0 : -1
    Timer { id: zoneTimer; interval: 80; onTriggered: osd.zone = osd.respectReserved ? 0 : -1 }
    exclusiveZone: zone
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
        const nv = Math.max(0, Math.min(1, v))
        if (shown && (nv !== value || k !== kind)) lensHold.restart()
        else if (!shown && !m) lensHold.restart()
        kind = k; value = nv; muted = m
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

    // while the level changes, a small glass lens rides on the end of the fill (GlassLens, Settings > Glass values); it
    // grows on a change, stays while changes keep coming and shrinks `lensHold` after the last one (popup motion tokens;
    // none = instant). Nothing of it exists at rest.
    Timer { id: lensHold; interval: Motion.baseMs * 2 }
    readonly property bool lensWanted: lensHold.running && shown && !muted
    property real grow: 0
    onLensWantedChanged: {
        growAnim.stop()
        growAnim.to = lensWanted ? 1 : 0
        growAnim.easing.type = lensWanted ? Theme.popupEaseOpen : Theme.popupEaseClose
        growAnim.duration = lensWanted ? Math.round(Theme.popupOpenMs * Math.max(0, Math.min(1, 1 - grow)))
                                       : Math.round(Theme.popupCloseMs * Math.max(0, Math.min(1, grow)))
        if (growAnim.duration <= 0) grow = growAnim.to
        else growAnim.start()
    }
    NumberAnimation { id: growAnim; target: osd; property: "grow" }
    readonly property real lensSize: 14 + 10 * grow
    readonly property point lensC: {
        void [meter.fillWidth, meter.x, meter.width, card.width, card.height]
        return meter.mapToItem(card, meter.fillWidth, meter.height / 2)
    }
    GlassLens {
        id: lens
        host: osd.grow > 0.004 ? card : null
        center: osd.lensC
        size: osd.lensSize
        amount: Math.max(0, Math.min(1, osd.grow * 3))
    }

    Rectangle {
        id: card
        readonly property bool isGlassItem: true
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.alpha(Theme.bg, Theme.cardFill)
        border.width: 1
        border.color: Theme.alpha(Theme.overlay, 0.5)
        GlassEdge { anchors.fill: parent; radius: parent.radius }   // the rim without the compositor's glass

        RowLayout {
            anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
            spacing: 14
            Icon {
                font.pixelSize: 22
                color: osd.muted ? Theme.muted : Theme.accent
                text: osd.kind === "brightness" ? "\uf185" : Icons.volumeGlyph(osd.muted, osd.value)
            }
            Meter {
                id: meter
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
