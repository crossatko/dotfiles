import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

// Now playing: art, title, transport controls, seek bar.
ColumnLayout {
    id: media
    spacing: 10
    implicitHeight: 230

    readonly property var player: {
        const ps = Mpris.players.values
        return ps.find(p => p.isPlaying) || ps.find(p => p.trackTitle) || ps[0] || null
    }
    function fmt(s) { s = Math.max(0, Math.floor(s)); return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2) }

    // position isn't pushed by MPRIS, it has to be re-read while playing
    Timer {
        interval: 1000
        repeat: true
        running: media.player && media.player.isPlaying
        onTriggered: media.player.positionChanged()
    }

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

        Rectangle {
            id: artFrame
            Layout.preferredWidth: 84; Layout.preferredHeight: 84
            radius: Theme.radiusItem
            color: Theme.alpha(Theme.fg, 0.08)
            clip: true
            Image {
                anchors.fill: parent
                source: media.player ? media.player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                // clip only cuts to the bounding box; mask the cover to the frame's rounded shape
                layer.enabled: artFrame.radius > 0
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: artMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }
            }
            Rectangle {
                id: artMask
                anchors.fill: parent
                radius: artFrame.radius
                visible: false
                layer.enabled: true
                layer.smooth: true
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Label { Layout.fillWidth: true; text: media.player ? media.player.trackTitle : ""; font.bold: true; font.pixelSize: 15; elide: Text.ElideRight; wrapMode: Text.Wrap; maximumLineCount: 2 }
            Label { Layout.fillWidth: true; text: media.player ? media.player.trackArtist : ""; color: Theme.fgDim; elide: Text.ElideRight }
            Label { Layout.fillWidth: true; text: media.player ? media.player.identity : ""; color: Theme.muted; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight }
        }
    }

    // seek bar
    ColumnLayout {
        visible: media.player !== null && media.player.lengthSupported && media.player.length > 0 && media.player.length < 100000
        Layout.fillWidth: true
        spacing: 3
        Rectangle {
            Layout.fillWidth: true
            height: 6; radius: Math.min(height / 2, Theme.radius)     // pill like Slider; square at radius 0
            color: Theme.alpha(Theme.fg, 0.15)
            Rectangle {
                width: parent.width * (media.player && media.player.length > 0 ? Math.min(1, media.player.position / media.player.length) : 0)
                height: parent.height; radius: parent.radius
                color: Theme.accent
            }
            MouseArea {
                anchors { fill: parent; topMargin: -8; bottomMargin: -8 }
                enabled: media.player && media.player.canSeek
                onClicked: mouse => {
                    media.player.position = media.player.length * (mouse.x / width)
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Label { text: media.player ? media.fmt(media.player.position) : ""; color: Theme.muted; font.pixelSize: Theme.fontCaption }
            Item { Layout.fillWidth: true }
            Label { text: media.player ? media.fmt(media.player.length) : ""; color: Theme.muted; font.pixelSize: Theme.fontCaption }
        }
    }

    RowLayout {
        visible: media.player !== null
        Layout.alignment: Qt.AlignHCenter
        spacing: 8
        Btn { icon: true; text: "\uf048"; enabledLook: media.player && media.player.canGoPrevious; onClicked: media.player.previous() }
        Btn { icon: true; text: media.player && media.player.isPlaying ? "\uf04c" : "\uf04b"; active: true; onClicked: media.player.togglePlaying() }
        Btn { icon: true; text: "\uf051"; enabledLook: media.player && media.player.canGoNext; onClicked: media.player.next() }
    }
}
