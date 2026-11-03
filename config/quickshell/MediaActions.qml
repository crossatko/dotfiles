import QtQuick
import QtQuick.Layouts

// The session actions of a media source (MediaSource), next to its transport (MediaTransport): mute (Twitch: only without
// a volume row or volume steps), stop (the TV session: stops the TV), show window, disconnect (the TV session, detach) and
// Play on PC (PcButton, the TV card). A control the source does not have is not drawn. MediaPanel only (never the lock card).
// Plain Btns (MouseArea): a click never takes the keyboard focus.
RowLayout {
    id: ac
    property var source: null
    readonly property bool usable: source !== null
    readonly property bool mute: usable && source.canMute && !source.canVolume && !source.canVolumeStep
    readonly property bool any: usable && (mute || source.canStop || source.canRaise || !!source.canDisconnect) || pc.shown
    visible: any
    spacing: Theme.gapRow
    Btn { objectName: "btn-media-mute"; visible: ac.mute; icon: true; text: Icons.volumeGlyph(!!(ac.source && ac.source.muted), 1); onClicked: if (ac.source) ac.source.setMuted(!ac.source.muted) }
    Btn { objectName: "btn-media-stop"; visible: ac.usable && ac.source.canStop; icon: true; text: Icons.stop; onClicked: if (ac.source) ac.source.stop() }
    Btn { objectName: "btn-media-raise"; visible: ac.usable && ac.source.canRaise; icon: true; text: Icons.externalLink; onClicked: if (ac.source) ac.source.raise() }
    Btn { objectName: "btn-media-disconnect"; visible: ac.usable && !!ac.source.canDisconnect; icon: true; text: Icons.linkOff; onClicked: if (ac.source) ac.source.disconnect() }
    PcButton { id: pc; source: ac.source }
}
