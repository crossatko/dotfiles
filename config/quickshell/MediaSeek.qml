import QtQuick
import QtQuick.Layouts

// A player's progress: seek bar (click = seek, where the player can) and position / length under it. Shown only for a
// track with a known, finite length (`usable`). MPRIS does not push the position: it is re-read once a second while
// playing and shown. MediaPanel, LockMedia.
ColumnLayout {
    id: seek
    property var player: null
    property bool times: true
    readonly property bool usable: player !== null && !!player.lengthSupported && player.length > 0 && player.length < 100000
    function fmt(s) { s = Math.max(0, Math.floor(s)); return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2) }
    visible: usable
    spacing: Theme.gapTight

    Timer {
        interval: 1000
        repeat: true
        running: seek.visible && seek.player !== null && !!seek.player.isPlaying && typeof seek.player.positionChanged === "function"
        onTriggered: seek.player.positionChanged()
    }
    Meter {
        Layout.fillWidth: true
        color: Theme.itemActive
        value: seek.player && seek.player.length > 0 ? seek.player.position / seek.player.length : 0
        MouseArea {
            anchors { fill: parent; topMargin: -8; bottomMargin: -8 }
            enabled: !!(seek.player && seek.player.canSeek)
            onClicked: mouse => {
                seek.player.position = seek.player.length * (mouse.x / width)
            }
        }
    }
    RowLayout {
        visible: seek.times
        Layout.fillWidth: true
        Label { text: seek.player ? seek.fmt(seek.player.position) : ""; color: Theme.muted; font.pixelSize: Theme.fontCaption }
        Item { Layout.fillWidth: true }
        Label { text: seek.player ? seek.fmt(seek.player.length) : ""; color: Theme.muted; font.pixelSize: Theme.fontCaption }
    }
}
