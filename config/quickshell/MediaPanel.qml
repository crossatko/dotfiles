pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Now playing for any media source (MediaSources: MPRIS players and the Twitch app): art, title / subtitle (FitLabel: 2
// lines, then elided, the full text on hover), category, stats (MediaStats: LIVE, viewers, stream time, the caption),
// seek bar (MPRIS; the TV card's `progress`), transport controls (+ Send to TV: TvButton; the TV session (TvSource): a tv badge, its controls drive the TV), volume (a source with its own: Twitch v2). With more than one source a switcher
// row comes first (the active source first). The parts (MediaArt, MediaSeek, MediaTransport, MediaStats, FitLabel) are
// shared with the lock screen's playback card (LockMedia).
ColumnLayout {
    id: media
    readonly property int artSize: 84      // cover art edge
    readonly property int seekH: 26        // the seek bar's slot (meter + times) is kept while a track has no length: nothing moves between tracks
    spacing: Theme.padSm

    property string picked: ""             // switcher choice (a source key); "" or gone = the first (active) one
    readonly property var sources: MediaSources.list
    readonly property var source: sources.find(s => s.key === picked) || (sources.length > 0 ? sources[0] : null)
    readonly property bool isMpris: source !== null && source.kind === "mpris"
    readonly property var seekPlayer: isMpris ? source.mpris : source && source.progress && source.progress.lengthSupported ? source.progress : null

    Segmented {
        visible: media.sources.length > 1
        Layout.fillWidth: true
        fillWidth: media.width
        values: media.sources.map(s => s.key)
        labels: media.sources.map(s => s.name || s.title)
        current: media.source ? media.source.key : ""
        objectNames: media.sources.map(s => "media-pick-" + s.kind)
        onPicked: v => media.picked = v
    }

    EmptyState {
        visible: !media.source
        icon: Icons.music
        text: "Nothing playing"
    }

    RowLayout {
        visible: media.source !== null
        Layout.fillWidth: true
        spacing: Theme.pad

        MediaArt {
            Layout.preferredWidth: media.artSize; Layout.preferredHeight: media.artSize
            url: media.source ? media.source.artUrl : ""
            glyph: media.source ? media.source.glyph : ""
            glyphBrand: !media.source || media.source.glyphBrand !== false
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.gapTight / 2
            FitLabel { Layout.fillWidth: true; text: media.source ? media.source.title : ""; font.bold: true; font.pixelSize: Theme.fontLead }
            FitLabel { Layout.fillWidth: true; visible: text !== "" || media.isMpris; text: media.source ? media.source.subtitle : ""; color: Theme.fgDim }
            MediaBadge { Layout.fillWidth: true; icon: Icons.gamepad; text: media.source ? media.source.category : "" }
            MediaBadge { Layout.fillWidth: true; icon: Icons.tv; text: media.source ? media.source.device || "" : "" }   // playing on the TV
            MediaStats {
                Layout.fillWidth: true
                live: !!(media.source && media.source.live)
                viewers: media.source ? media.source.viewers : -1
                liveSince: media.source ? media.source.liveSince : 0
                note: media.source ? media.source.caption : ""
            }
        }
    }

    Item {
        visible: media.seekPlayer !== null
        Layout.fillWidth: true
        Layout.preferredHeight: media.seekH
        MediaSeek { anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter } player: media.seekPlayer }
    }

    // transport centred; Send to TV (TvButton) at the row's end, outside the layout: appearing never moves the transport
    Item {
        visible: transport.any || tv.shown
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(transport.implicitHeight, tv.implicitHeight)
        MediaTransport {
            id: transport
            anchors.centerIn: parent
            source: media.source
        }
        TvButton {
            id: tv
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            source: media.source
        }
    }

    // the TV session over key presses: mute / down / up (no level to show)
    MediaVolumeSteps {
        Layout.alignment: Qt.AlignHCenter
        source: media.source
    }

    // a source with its own volume (Twitch app v2): the speaker mutes, the slider sets it
    LevelRow {
        visible: !!(media.source && media.source.canVolume && media.source.volume >= 0)
        icon: media.source ? Icons.volumeGlyph(media.source.muted, media.source.volume) : ""
        iconColor: media.source && media.source.muted ? Theme.muted : Theme.accent
        iconClickable: !!(media.source && media.source.canMute)
        value: media.source ? Math.max(0, media.source.volume) : 0
        dim: !!(media.source && media.source.muted)
        notches: Presets.volumeNotches
        valueText: media.source ? Math.round(Math.max(0, media.source.volume) * 100) + "%" : ""
        onMoved: v => media.source.setVolume(v)
        onIconClicked: media.source.setMuted(!media.source.muted)
    }
}
