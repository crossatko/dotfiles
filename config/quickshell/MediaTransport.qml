import QtQuick
import QtQuick.Layouts

// The controls of a media source (MediaSource): previous / play-pause / next where the source has them (an MPRIS player:
// all three, previous / next dimmed when the player cannot go there), stop / show window / mute where it has those (Twitch;
// mute here only without a volume row). A control the source does not have is not drawn. `lock`: only the transport
// (previous / play-pause / next) of a source whose `lockControls` says it works there (previous / next only with
// `lockTransport`); never stop / raise / mute. The TV session (TvSource) adds seek back / forward around play-pause and
// disconnect at the end (popup only); its stop stops the TV. MediaPanel, LockMedia. Plain Btns (MouseArea): a click never
// takes the keyboard focus.
RowLayout {
    id: tr
    property var source: null
    property bool lock: false
    readonly property bool usable: source !== null && (!lock || source.lockControls)
    readonly property bool prevNext: usable && source.transport && (!lock || source.lockTransport !== false)
    readonly property bool seekSteps: usable && !lock && !!source.canSeekStep
    readonly property bool any: usable && (prevNext || source.canToggle || (!lock && (source.canStop || source.canRaise || source.canDisconnect || (source.canMute && !source.canVolume && !source.canVolumeStep))))
    visible: any
    spacing: Theme.gapRow
    Btn { objectName: "btn-media-previous"; visible: tr.prevNext; icon: true; text: Icons.prev; enabledLook: !!(tr.source && tr.source.canPrev); onClicked: if (tr.source) tr.source.previous() }
    Btn { objectName: "btn-media-back"; visible: tr.seekSteps; icon: true; text: Icons.seekBack; onClicked: if (tr.source) tr.source.seekStep(false) }
    Btn { objectName: "btn-media-play"; visible: tr.usable && tr.source.canToggle; icon: true; text: tr.source && tr.source.playing ? Icons.pause : Icons.play; active: true; onClicked: if (tr.source) tr.source.togglePlaying() }
    Btn { objectName: "btn-media-forward"; visible: tr.seekSteps; icon: true; text: Icons.seekForward; onClicked: if (tr.source) tr.source.seekStep(true) }
    Btn { objectName: "btn-media-next"; visible: tr.prevNext; icon: true; text: Icons.next; enabledLook: !!(tr.source && tr.source.canNext); onClicked: if (tr.source) tr.source.next() }
    Btn { objectName: "btn-media-mute"; visible: tr.usable && !tr.lock && tr.source.canMute && !tr.source.canVolume && !tr.source.canVolumeStep; icon: true; text: Icons.volumeGlyph(!!(tr.source && tr.source.muted), 1); onClicked: if (tr.source) tr.source.setMuted(!tr.source.muted) }
    Btn { objectName: "btn-media-stop"; visible: tr.usable && tr.source.canStop && !tr.lock; icon: true; text: Icons.stop; onClicked: if (tr.source) tr.source.stop() }
    Btn { objectName: "btn-media-raise"; visible: tr.usable && tr.source.canRaise && !tr.lock; icon: true; text: Icons.externalLink; onClicked: if (tr.source) tr.source.raise() }
    Btn { objectName: "btn-media-disconnect"; visible: tr.usable && !tr.lock && !!tr.source.canDisconnect; icon: true; text: Icons.linkOff; onClicked: if (tr.source) tr.source.disconnect() }
}
