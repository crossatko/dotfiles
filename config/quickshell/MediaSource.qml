import QtQuick
import Quickshell

// One normalized media source (MediaSources builds them): what the bar chip, the media popup and the lock card show and
// can do, whatever the player is. `kind` "mpris" wraps an MPRIS player (`mpris` = the raw player: seek bar, brand);
// "twitch" = the Twitch app's status file (TwitchSource); "tv" = the Send to TV session (TvSource: controls drive the TV). Actions are requests (`command`); the provider carries them out.
// A field a source cannot fill stays at its default; a `can*` that is false hides that control (MediaTransport).
Scope {
    id: src
    property string key: ""             // stable id across updates (the switcher's pick)
    property string kind: ""            // "mpris" | "twitch"
    property var mpris: null            // MPRIS player (kind mpris), else null
    property var progress: null         // a seek-bar player for a source without MPRIS (MediaSeek: isPlaying, lengthSupported, length,
                                        // position, canSeek, refresh()), null = none (the TV card while the TV reports a length)
    property string title: ""           // the one prominent line (track / stream title)
    property string subtitle: ""        // artist / channel
    property string caption: ""         // the player (identity) / a state word (Offline, Paused)
    property string category: ""        // stream category (Twitch game), "" = none
    property string name: ""            // the player's name (switcher)
    property string chipText: ""        // the bar chip's label
    property string artUrl: ""          // cover / channel picture ("" = placeholder)
    property string glyph: ""           // brand mark (Theme.brandFont) for a missing picture and the switcher; "" = none
    property bool glyphBrand: true      // false: `glyph` is an Icons glyph (Theme.iconFont), e.g. the TV session's tv
    property string device: ""          // where it plays when not here (the TV session: the TV's name), "" = here
    property bool playing: false
    property bool titled: false         // has something to show (a player without a title only shows as the fallback)
    property bool live: false           // a live stream (no length; "LIVE" pill)
    property int viewers: -1            // live viewer count, -1 = unknown
    property double liveSince: 0        // when the live stream started (epoch ms), 0 = unknown
    property bool canToggle: false      // play / pause
    property bool transport: false      // previous / next buttons exist (dimmed when the player cannot go there)
    property bool canPrev: false
    property bool canNext: false
    property bool canStop: false
    property bool canRaise: false
    property bool canMute: false
    property bool muted: false
    property bool canVolume: false
    property real volume: -1            // 0..1, -1 = unknown
    property bool lockControls: true    // play / pause also works from the lock card (stop / raise / volume never show there)
    property bool lockTransport: true   // previous / next on the lock card too (false: play / pause only)
    property bool canSeekStep: false    // seek back / forward buttons (a fixed step: the TV session)
    property bool canVolumeStep: false  // volume down / up / mute buttons (a volume without a known level: the TV session)
    property bool canDisconnect: false  // detach (the TV session: control returns here, the TV keeps playing)
    signal command(string what)         // "toggle" | "previous" | "next" | "stop" | "raise" | "mute" | "unmute" | "volume:<0..100>"
                                        // | "back" | "forward" | "volup" | "voldown" | "disconnect"

    function togglePlaying() { if (canToggle) command("toggle") }
    function previous() { if (transport) command("previous") }   // asked even when dimmed (as MPRIS clients do)
    function next() { if (transport) command("next") }
    function stop() { if (canStop) command("stop") }
    function raise() { if (canRaise) command("raise") }
    function setMuted(on) { if (canMute) command(on ? "mute" : "unmute") }
    function setVolume(v) { if (canVolume) command("volume:" + Math.round(Math.max(0, Math.min(1, v)) * 100)) }
    function seekStep(forward) { if (canSeekStep) command(forward ? "forward" : "back") }
    function volumeStep(up) { if (canVolumeStep) command(up ? "volup" : "voldown") }
    function disconnect() { if (canDisconnect) command("disconnect") }
}
