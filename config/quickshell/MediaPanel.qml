pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Now playing: art, title, transport controls, seek bar. The parts (MediaPick, MediaArt, MediaSeek, MediaTransport)
// are shared with the lock screen's playback card (LockMedia).
ColumnLayout {
    id: media
    spacing: 10
    implicitHeight: 230

    MediaPick { id: pick }
    readonly property var player: pick.player

    Label {
        visible: !media.player
        text: "Nothing playing"
        color: Theme.muted
        Layout.alignment: Qt.AlignHCenter
    }

    RowLayout {
        visible: media.player !== null
        Layout.fillWidth: true
        spacing: 12

        MediaArt {
            Layout.preferredWidth: 84; Layout.preferredHeight: 84
            url: media.player ? media.player.trackArtUrl : ""
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Label { Layout.fillWidth: true; text: media.player ? media.player.trackTitle : ""; font.bold: true; font.pixelSize: 15; elide: Text.ElideRight; wrapMode: Text.Wrap; maximumLineCount: 2 }
            Label { Layout.fillWidth: true; text: media.player ? media.player.trackArtist : ""; color: Theme.fgDim; elide: Text.ElideRight }
            Label { Layout.fillWidth: true; text: media.player ? media.player.identity : ""; color: Theme.muted; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight }
        }
    }

    MediaSeek { Layout.fillWidth: true; player: media.player }

    MediaTransport {
        visible: media.player !== null
        Layout.alignment: Qt.AlignHCenter
        player: media.player
    }
}
