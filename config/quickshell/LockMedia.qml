pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// The lock screen's playback card (LockView, under the password dots; Settings > Lock "Playback card"): the media
// panel's parts (MediaPick / MediaArt / MediaSeek / MediaTransport) in one row: cover, title / artist and progress,
// previous / play-pause / next. With Theme.shellGlass the card is a glass slab (GlassShape over a rounded-rect mask, the
// lock's lettering optics, refracting `backdrop` / `sharpBackdrop`, `origin` = this item's top-left in them) under a
// faint fill; without it a flat card like the popups' (fill, border, GlassEdge). Shown only while a player exists
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

    MediaPick { id: pick }
    readonly property var samplePlayer: ({
        trackTitle: "Track title", trackArtist: "Artist", trackArtUrl: "", identity: "Player",
        isPlaying: true, lengthSupported: true, length: 214, position: 83,
        canGoPrevious: true, canGoNext: true, canSeek: false,
        previous() {}, next() {}, togglePlaying() {}
    })
    readonly property var player: sample ? samplePlayer : pick.player
    readonly property bool on: shown && player !== null
    // what the card shows, kept while it fades out after the player went away
    property string title: ""
    property string artist: ""
    property string art: ""
    Binding { card.title: card.player ? card.player.trackTitle || card.player.identity || "" : ""; when: card.player !== null; restoreMode: Binding.RestoreNone }
    Binding { card.artist: card.player ? card.player.trackArtist || "" : ""; when: card.player !== null; restoreMode: Binding.RestoreNone }
    Binding { card.art: card.player ? card.player.trackArtUrl || "" : ""; when: card.player !== null; restoreMode: Binding.RestoreNone }

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
            placeholder: true
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2
            Label { Layout.fillWidth: true; text: card.title; font.bold: true; elide: Text.ElideRight }
            Label { Layout.fillWidth: true; visible: text !== ""; text: card.artist; color: Theme.fgDim; font.pixelSize: Theme.fontSmall; elide: Text.ElideRight }
            MediaSeek { Layout.fillWidth: true; Layout.topMargin: 4; player: card.player; times: false; visible: usable || card.player === null }
        }
        MediaTransport {
            Layout.alignment: Qt.AlignVCenter
            spacing: 6
            player: card.player
        }
    }
}
