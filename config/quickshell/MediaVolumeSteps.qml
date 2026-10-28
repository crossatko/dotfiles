import QtQuick
import QtQuick.Layouts

// Volume for a source that can step it but has no level to show (the TV session over key presses: TvSource
// `canVolumeStep`): mute, down, up as icon buttons. A source with a known level gets MediaPanel's LevelRow instead.
// MediaPanel only (never the lock card).
RowLayout {
    id: vs
    property var source: null
    visible: !!(source && source.canVolumeStep)
    spacing: Theme.gapRow
    Btn { objectName: "btn-media-mute-tv"; visible: !!(vs.source && vs.source.canMute); icon: true; text: vs.source && vs.source.muted ? Icons.volumeMuted : Icons.volumeOff; active: !!(vs.source && vs.source.muted); onClicked: if (vs.source) vs.source.setMuted(!vs.source.muted) }
    Btn { objectName: "btn-media-voldown"; icon: true; text: Icons.volumeLow; onClicked: if (vs.source) vs.source.volumeStep(false) }
    Btn { objectName: "btn-media-volup"; icon: true; text: Icons.volumeHigh; onClicked: if (vs.source) vs.source.volumeStep(true) }
}
