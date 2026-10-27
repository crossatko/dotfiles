import QtQuick
import QtQuick.Layouts

// Previous / play-pause / next of a player (MediaPanel, LockMedia). Plain Btns (MouseArea): a click never takes the
// keyboard focus.
RowLayout {
    id: tr
    property var player: null
    spacing: Theme.gapRow
    Btn { objectName: "btn-media-previous"; icon: true; text: Icons.prev; enabledLook: !!(tr.player && tr.player.canGoPrevious); onClicked: if (tr.player) tr.player.previous() }
    Btn { objectName: "btn-media-play"; icon: true; text: tr.player && tr.player.isPlaying ? Icons.pause : Icons.play; active: true; onClicked: if (tr.player) tr.player.togglePlaying() }
    Btn { objectName: "btn-media-next"; icon: true; text: Icons.next; enabledLook: !!(tr.player && tr.player.canGoNext); onClicked: if (tr.player) tr.player.next() }
}
