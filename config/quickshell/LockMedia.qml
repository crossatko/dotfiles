pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// The lock screen's playback card (LockView, under the password dots; Settings > Lock "Playback card"): the media
// panel's parts (MediaArt / MediaSeek / MediaTransport / MediaStats / FitLabel) for `MediaSources.current` (MPRIS or the Twitch app)
// in one row: cover, title (2 lines, then elided) / artist (1 line) and progress or the live stats (MediaStats: LIVE,
// viewers, stream time, category), previous / play-pause / next (only controls that work from the lock: `lockControls`;
// Twitch: play / pause with a v2 app, nothing with a v1 one; never stop / show window / volume here). With Theme.shellGlass the card is a glass slab (GlassShape over a rounded-rect mask, the
// lock's lettering optics, refracting `backdrop` / `sharpBackdrop`, `origin` = this item's top-left in them) under a
// faint fill; without it a flat card like the popups' (fill, border, GlassEdge). Shown only while a source exists
// (`shown`), fading in / out on the popup motion tokens. The buttons are MouseAreas: clicks never take the keyboard
// focus from the password field. `sample` (Settings preview): a made-up track, inert buttons.
Item {
    id: card
    property bool shown: true
    property bool sample: false
    property alias backdrop: slab.backdrop
    property alias sharpBackdrop: slab.sharpBackdrop
    property alias sharpInset: slab.sharpInset
    property alias dim: slab.dim
    property point origin: Qt.point(0, 0)
    property alias backdropSize: slab.backdropSize

    // Settings preview: a made-up track (a plain object with MediaSource's fields; `mpris` feeds the seek bar)
    readonly property var sampleSource: ({
        key: "sample", kind: "mpris", title: "Track title", subtitle: "Artist", caption: "Player", artUrl: "", glyph: "",
        playing: true, live: false, canToggle: true, transport: true, canPrev: true, canNext: true, canStop: false,
        canRaise: false, lockControls: true, category: "", viewers: -1, liveSince: 0, canMute: false, muted: false,
        canVolume: false, volume: -1,
        mpris: { isPlaying: true, lengthSupported: true, length: 214, position: 83, canSeek: false },
        previous() {}, next() {}, togglePlaying() {}, stop() {}, raise() {}
    })
    readonly property var source: sample ? sampleSource : MediaSources.current
    readonly property bool on: shown && source !== null
    // what the card shows, kept while it fades out after the source went away
    property string title: ""
    property string artist: ""
    property string art: ""
    property string glyph: ""
    property bool live: false
    property string category: ""
    property int viewers: -1
    property double liveSince: 0
    Binding { card.title: card.source ? card.source.title || card.source.caption || "" : ""; when: card.source !== null; restoreMode: Binding.RestoreNone }
    Binding { card.artist: card.source ? card.source.subtitle || "" : ""; when: card.source !== null; restoreMode: Binding.RestoreNone }
    Binding { card.art: card.source ? card.source.artUrl || "" : ""; when: card.source !== null; restoreMode: Binding.RestoreNone }
    Binding { card.glyph: card.source ? card.source.glyph || "" : ""; when: card.source !== null; restoreMode: Binding.RestoreNone }
    Binding { card.live: card.source ? !!card.source.live : false; when: card.source !== null; restoreMode: Binding.RestoreNone }
    Binding { card.category: card.source ? card.source.category || "" : ""; when: card.source !== null; restoreMode: Binding.RestoreNone }
    Binding { card.viewers: card.source && card.source.viewers !== undefined ? card.source.viewers : -1; when: card.source !== null; restoreMode: Binding.RestoreNone }
    Binding { card.liveSince: card.source ? card.source.liveSince || 0 : 0; when: card.source !== null; restoreMode: Binding.RestoreNone }
    readonly property var player: !source ? null : source.kind === "mpris" ? source.mpris : source.progress || null   // seek bar

    readonly property int padIn: 14
    readonly property int pad: 24            // the glass's shadow / caustic around the slab
    implicitHeight: row.implicitHeight + 2 * padIn
    visible: opacity > 0
    opacity: on ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: card.on ? Theme.popupOpenMs : Theme.popupCloseMs; easing.type: Easing.InOutSine } }

    // ---- the card ----
    Item {
        id: slabMask
        x: -card.pad; y: -card.pad
        width: card.width + 2 * card.pad; height: card.height + 2 * card.pad
        visible: false
        layer.enabled: Theme.shellGlass && card.visible
        layer.smooth: true
        layer.mipmap: true
        layer.textureSize: Qt.size(width * slab.ss, height * slab.ss)
        Rectangle { x: card.pad; y: card.pad; width: card.width; height: card.height; radius: Theme.radius; color: "white" }
    }
    GlassShape {
        id: slab
        x: -card.pad; y: -card.pad
        width: slabMask.width; height: slabMask.height
        mask: Theme.shellGlass ? slabMask : null
        pad: card.pad
        strokeHalf: 9
        shade: 0.3
        origin: Qt.point(card.origin.x - card.pad, card.origin.y - card.pad)
    }
    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.alpha(Theme.bg, slab.refracting ? Theme.cardFill * 0.6 : Theme.cardFill)
        border.width: slab.refracting ? 0 : 1
        border.color: Theme.alpha(Theme.overlay, 0.5)
        GlassEdge { anchors.fill: parent; radius: parent.radius }   // the rim without the compositor's glass
    }

    // ---- content ----
    RowLayout {
        id: row
        anchors { fill: parent; margins: card.padIn }
        spacing: 12
        MediaArt {
            Layout.preferredWidth: 52; Layout.preferredHeight: 52
            Layout.alignment: Qt.AlignVCenter
            url: card.art
            glyph: card.glyph
            glyphBrand: !card.source || card.source.glyphBrand !== false
            placeholder: true
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2
            FitLabel { Layout.fillWidth: true; text: card.title; font.bold: true; tip: false }
            FitLabel { Layout.fillWidth: true; visible: text !== ""; text: card.artist; color: Theme.fgDim; font.pixelSize: Theme.fontSmall; lines: 1; tip: false }
            MediaSeek { Layout.fillWidth: true; Layout.topMargin: 4; player: card.player; times: false; visible: usable || card.source === null }
            MediaStats {
                Layout.fillWidth: true
                Layout.topMargin: 2
                live: card.live
                viewers: card.viewers
                liveSince: card.liveSince
                category: card.category
                withCategory: true
            }
        }
        MediaTransport {
            id: transport
            Layout.alignment: Qt.AlignVCenter
            spacing: 6
            source: card.source
            lock: true
        }
    }
}
