import QtQuick
import QtQuick.Layouts

// The transport of a media source (MediaSource): previous / play-pause / next where the source has them (an MPRIS player:
// all three, previous / next dimmed when the player cannot go there). A control the source does not have is not drawn.
// `lock`: only for a source whose `lockControls` says it works there (previous / next only with `lockTransport`). The TV
// session (TvSource) adds seek back / forward around play-pause (popup only). Stop / show window / mute / disconnect are
// MediaActions (popup only). MediaPanel, LockMedia. Plain Btns (MouseArea): a click never takes the keyboard focus.
RowLayout {
    id: tr
    property var source: null
    property bool lock: false
    readonly property bool usable: source !== null && (!lock || source.lockControls)
    readonly property bool prevNext: usable && source.transport && (!lock || source.lockTransport !== false)
    readonly property bool seekSteps: usable && !lock && !!source.canSeekStep
    readonly property bool any: usable && (prevNext || source.canToggle)
    visible: any
    spacing: Theme.gapRow
    Btn { objectName: "btn-media-previous"; visible: tr.prevNext; icon: true; text: Icons.prev; enabledLook: !!(tr.source && tr.source.canPrev); onClicked: if (tr.source) tr.source.previous() }
    Btn { objectName: "btn-media-back"; visible: tr.seekSteps; icon: true; text: Icons.seekBack; onClicked: if (tr.source) tr.source.seekStep(false) }
    Btn { objectName: "btn-media-play"; visible: tr.usable && tr.source.canToggle; icon: true; text: tr.source && tr.source.playing ? Icons.pause : Icons.play; active: true; onClicked: if (tr.source) tr.source.togglePlaying() }
    Btn { objectName: "btn-media-forward"; visible: tr.seekSteps; icon: true; text: Icons.seekForward; onClicked: if (tr.source) tr.source.seekStep(true) }
    Btn { objectName: "btn-media-next"; visible: tr.prevNext; icon: true; text: Icons.next; enabledLook: !!(tr.source && tr.source.canNext); onClicked: if (tr.source) tr.source.next() }
}
