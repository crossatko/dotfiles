import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire

// Volume / brightness pill, bottom-center of the focused monitor. Volume is observed from
// Pipewire (so wpctl keybinds just work); brightness when the keys step it (Brightness.stepped)
// Test hook: `qs ipc call osd level volume -1` shows the muted pill (a negative level = muted, see show()).
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
    readonly property int pillW: 320    // the pill: wide enough for the meter to read as a scale, two bar heights tall
    readonly property int pillH: 56
    readonly property int glyphCol: Theme.iconXl + Theme.padSm   // 32: the widest OSD glyph (volume-high at iconXl) centred, so the meter never shifts
    readonly property int valueW: Theme.iconCol + Theme.iconXl   // 44: "100%" / "muted" right-aligned in a fixed column
    readonly property int sidePad: Theme.pad + Theme.controlGap  // 18: the pill's side inset (a pill breathes more than a card)

    screen: target
    // shell-side open / close (OpenMotion, popup style): with the compositor's glass the pill fades out and its glass
    // shrinks away before the surface unmaps (the layer fade alone left the glass box behind for the whole fade, then
    // dropped it at once). Without it (stock) the blur is the whole window and cannot shrink: unmap at once and let
    // Hyprland's layer fade take the pill out as before.
    visible: Theme.glass ? motion.shown : osd.shown
    OpenMotion { id: motion; open: osd.shown; delay: 40 }
    anchors { bottom: true }
    // above a (floating) bottom bar
    // qmllint disable missing-property
    margins.bottom: 70 + (bars[(screen ? screen.name : "")] === "bottom" ? BarConfig.insetOf(screen) : 0)
    // qmllint enable missing-property
    implicitWidth: pillW
    implicitHeight: pillH
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
        if (v < 0) m = true                // test hook (see the header): a negative level stands for "muted"
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
    readonly property real lensSize: Theme.iconMd + (Theme.iconXl - Theme.iconSm) * grow   // 14 -> 24 px: the lens grows from a dot to a bead on the fill's end
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
        opacity: Math.max(0, Math.min(1, motion.t))
        readonly property real glassScale: Theme.glassScaleAt(motion.t)   // see PopupHost's card
        layer.enabled: motion.moving                                      // fade as one texture
        transform: [
            Scale { origin.x: card.width / 2; origin.y: card.height; xScale: motion.popScale; yScale: motion.popScale },
            Translate { y: motion.slide }
        ]
        radius: Theme.radius
        color: Theme.alpha(Theme.bg, Theme.cardFill)
        border.width: 1
        border.color: Theme.edge
        GlassEdge { anchors.fill: parent; radius: parent.radius }   // the rim without the compositor's glass

        RowLayout {
            anchors { fill: parent; leftMargin: osd.sidePad; rightMargin: osd.sidePad }
            spacing: Theme.pad
            // the glyph carries the state: accent while live, muted when muted (as the bar chip)
            Icon {
                font.pixelSize: Theme.iconXl
                color: osd.muted ? Theme.muted : Theme.accent
                text: osd.kind === "brightness" ? Icons.sun : Icons.volumeGlyph(osd.muted, osd.value)
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: osd.glyphCol
            }
            Meter {
                id: meter
                Layout.fillWidth: true
                radius: Math.min(height / 2, Theme.inner(Theme.radius, osd.sidePad))
                color: Theme.alpha(Theme.fg, 0.15)
                value: osd.muted ? 0 : osd.value
                animMs: Motion.pressMs
                easingType: Easing.Linear
            }
            Label {
                text: osd.muted ? "muted" : Math.round(osd.value * 100) + "%"
                Layout.preferredWidth: osd.valueW
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
