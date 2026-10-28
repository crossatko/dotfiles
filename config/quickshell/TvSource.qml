import QtQuick
import "launcher/js/TvSession.js" as Js

// The TV card (TvSession.card) as a media source: the Send to TV session (what we sent; Cast: the TV's own title), else
// what auto-detect found the TV playing by itself (title / artist / art / position from Home Assistant). A tv glyph and
// the TV's name (`device`), the best-known play / pause, and controls that drive the TV: play / pause, previous / next,
// seek back / forward, volume (Cast: a level; else down / up / mute steps), stop (stops the TV; a session ends) and, for a
// sent session only, disconnect (detach). A length from the TV feeds the seek bar (`progress`, read-only). Lock card:
// play / pause only. MediaSources puts a sent session first; an auto-detected one follows the usual pick rule.
MediaSource {
    id: tv
    readonly property var d: TvSession.card
    readonly property bool on: d !== null
    readonly property bool sent: on && d.sent
    readonly property var c: on && d.caps ? d.caps : null

    key: "tv"
    kind: "tv"
    title: on ? d.title : ""
    subtitle: on ? d.subtitle : ""
    caption: on && !d.playing ? "Paused" : ""
    name: on ? d.name : "TV"
    device: on ? d.name : ""
    chipText: title + (on ? "  ·  " + d.name : "")
    artUrl: on ? d.artUrl : ""
    glyph: Icons.tv
    glyphBrand: false
    playing: on && d.playing
    titled: on
    live: on && d.live
    canToggle: !!c && c.toggle
    transport: !!c && c.prevNext
    canPrev: transport
    canNext: transport
    canSeekStep: !!c && c.seek && !d.live
    canStop: !!c && c.stop
    canDisconnect: sent
    canMute: !!c && c.mute
    muted: on && d.muted
    canVolume: !!c && c.volumeSet && d.volume >= 0
    volume: on ? d.volume : -1
    canVolumeStep: !!c && c.volumeStep && !canVolume
    lockControls: canToggle
    lockTransport: false
    onCommand: what => TvSession.control(what)

    progress: QtObject {
        property double tick: Date.now()
        readonly property bool isPlaying: tv.playing
        readonly property bool lengthSupported: tv.on && tv.d.duration > 0 && tv.d.position >= 0
        readonly property real length: lengthSupported ? tv.d.duration : 0
        readonly property real position: lengthSupported ? Js.positionAt(tv.d, tick) : 0
        readonly property bool canSeek: false
        function refresh() { tick = Date.now() }
    }
}
