pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Now playing: art, title, transport controls, seek bar. The parts (MediaPick, MediaArt, MediaSeek, MediaTransport)
// are shared with the lock screen's playback card (LockMedia).
ColumnLayout {
    id: media
    readonly property int artSize: 84      // cover art edge
    readonly property int seekH: 26        // the seek bar's slot (meter + times) is kept while a track has no length: nothing moves between tracks
    spacing: Theme.padSm

    MediaPick { id: pick }
    readonly property var player: pick.player

    EmptyState {
        visible: !media.player
        icon: Icons.music
        text: "Nothing playing"
    }

    RowLayout {
        visible: media.player !== null
        Layout.fillWidth: true
        spacing: Theme.pad

        MediaArt {
            Layout.preferredWidth: media.artSize; Layout.preferredHeight: media.artSize
            url: media.player ? media.player.trackArtUrl : ""
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.gapTight / 2
            Label { Layout.fillWidth: true; text: media.player ? media.player.trackTitle : ""; font.bold: true; font.pixelSize: Theme.fontLead; elide: Text.ElideRight; wrapMode: Text.Wrap; maximumLineCount: 2 }
            Label { Layout.fillWidth: true; text: media.player ? media.player.trackArtist : ""; color: Theme.fgDim; elide: Text.ElideRight }
            Label { Layout.fillWidth: true; text: media.player ? media.player.identity : ""; color: Theme.muted; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight }
        }
    }

    Item {
        visible: media.player !== null
        Layout.fillWidth: true
        Layout.preferredHeight: media.seekH
        MediaSeek { anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter } player: media.player }
    }

    MediaTransport {
        visible: media.player !== null
        Layout.alignment: Qt.AlignHCenter
        player: media.player
    }
}
