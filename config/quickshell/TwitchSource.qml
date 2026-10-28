import QtQuick
import Quickshell
import Quickshell.Io

// The Twitch player (twitch-qs-mpv, its own repo) as a media source. Embedded libmpv has no MPRIS, so the app publishes
// $XDG_RUNTIME_DIR/twitch-qs-mpv-now.json, rewritten every 15 s and on change, deleted when the player closes; `fresh` =
// written in the last 45 s (an older file = the player is gone). Contract v1: {channel, playing, title, game, live,
// updated (ms)} (title / game "" while offline). v2 adds {v: 2, paused, volume (0..1), muted, viewers (number | null),
// startedAt (epoch ms | null), caps: ["pause", "mute", "volume", "stop", "raise"]}: a control shows only when its cap
// is listed (no `caps` = a v1 app: stop + raise, popup only). Every field is optional here. Actions run the app's CLI
// (`twitch-qs-mpv pause on|off`, `mute on|off`, `volume <0-100>`, `quit`); raise = hyprctl focus by title. Play / pause
// also works from the lock card; stop / raise / volume are popup-only (MediaTransport `lock`). Picture: the channel
// avatar the app caches for the launcher (<cache>/avatars/<login>.<ext>, only if it was fetched).
// Test hooks: QS_TWITCH_NOW_FILE, QS_TWITCH_CACHE_DIR, LAUNCHER_TWITCH_DIR (the app's bin/, as the launcher).
MediaSource {
    id: tw
    key: "twitch"
    kind: "twitch"
    readonly property string nowFile: Quickshell.env("QS_TWITCH_NOW_FILE") || (Quickshell.env("XDG_RUNTIME_DIR") + "/twitch-qs-mpv-now.json")
    readonly property string cacheDir: Quickshell.env("QS_TWITCH_CACHE_DIR") || Quickshell.env("TWITCH_QS_CACHE_DIR") || (Quickshell.env("HOME") + "/.cache/twitch-qs-mpv")
    readonly property string app: (Quickshell.env("LAUNCHER_TWITCH_DIR") || (Quickshell.env("HOME") + "/code/crossatko/twitch-qs-mpv/bin")) + "/twitch-qs-mpv"
    readonly property int staleMs: 45000
    readonly property int pendingMs: 1500   // a requested volume / mute shows at once and for this long, until the file has it

    property var now: null              // the parsed file, null = none / unreadable
    property double clock: Date.now()
    property double stoppedAt: 0        // `updated` of the file when stop was asked: hidden until the app writes again
    readonly property bool fresh: now !== null && clock - now.updated < staleMs && now.updated > stoppedAt
    readonly property string channel: now && typeof now.channel === "string" ? now.channel : ""
    readonly property string login: /^[A-Za-z0-9_]{1,25}$/.test(channel) ? channel.toLowerCase() : ""
    readonly property var caps: now && Array.isArray(now.caps) ? now.caps : []
    readonly property bool v1: caps.length === 0
    function has(cap) { return caps.indexOf(cap) >= 0 }

    title: now && now.title ? String(now.title) : channel
    subtitle: now && now.title ? channel : ""
    category: now && now.game ? String(now.game) : ""
    viewers: live && typeof now.viewers === "number" && now.viewers >= 0 ? Math.floor(now.viewers) : -1
    liveSince: {
        if (!live || now.startedAt === undefined || now.startedAt === null) return 0
        const t = typeof now.startedAt === "number" ? now.startedAt : Date.parse(String(now.startedAt))
        return isFinite(t) && t > 0 ? t : 0
    }
    caption: [live ? "" : "Offline", playing || canToggle ? "" : "Paused"].filter(t => t !== "").join("  ·  ")   // without a play / pause control the state is a word
    name: "Twitch"
    chipText: channel + (category ? "  ·  " + category : "")
    artUrl: avatar
    glyph: Icons.twitch
    playing: !!(now && now.playing)
    titled: channel !== ""
    live: !!(now && now.live)
    canToggle: has("pause")
    canStop: v1 || has("stop")
    canRaise: v1 || has("raise")
    canMute: has("mute")
    canVolume: has("volume")
    lockControls: canToggle
    muted: reqMuted >= 0 ? reqMuted === 1 : !!(now && now.muted)
    volume: reqVolume >= 0 ? reqVolume : now && typeof now.volume === "number" ? Math.max(0, Math.min(1, now.volume)) : -1

    // requests in flight: shown until the file catches up (pendingMs); volume drags are sent at most every volumeMs
    property real reqVolume: -1
    property int reqMuted: -1
    property int sentVolume: -1
    readonly property int volumeMs: 120
    Timer { id: pendingReset; interval: tw.pendingMs; onTriggered: { tw.reqVolume = -1; tw.reqMuted = -1 } }
    Timer { id: volumeGate; interval: tw.volumeMs; onTriggered: tw.sendVolume() }
    function sendVolume() {
        const p = Math.round(reqVolume * 100)
        if (reqVolume < 0 || p === sentVolume) { sentVolume = -1; return }   // nothing new: the gate closes
        sentVolume = p
        Quickshell.execDetached([app, "volume", String(p)])
        volumeGate.restart()
    }

    Timer {
        interval: 10000; running: tw.now !== null; repeat: true
        onRunningChanged: if (running) tw.clock = Date.now()
        onTriggered: tw.clock = Date.now()
    }
    FileView {
        path: tw.nowFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { tw.clock = Date.now(); tw.now = JSON.parse(text()) } catch (e) { tw.now = null } }
        onLoadFailed: tw.now = null
    }

    // channel avatar from the app's cache (extension unknown: whatever the CDN served)
    property string avatar: ""
    function findAvatar() {   // the command is set here, not bound: a binding could still hold the previous login
        avatar = ""
        avatarProc.running = false
        if (login === "") return
        avatarProc.command = ["sh", "-c", 'for f in "$1"/avatars/"$2".*; do [ -f "$f" ] && { printf %s "$f"; exit 0; }; done', "sh", cacheDir, login]
        avatarProc.running = true
    }
    onLoginChanged: findAvatar()
    Component.onCompleted: findAvatar()   // the file can load before the Process exists
    Process {
        id: avatarProc
        stdout: StdioCollector { onStreamFinished: tw.avatar = text !== "" ? "file://" + text : "" }
    }

    onCommand: what => {
        if (what === "stop") { stoppedAt = now ? now.updated : 0; Quickshell.execDetached([app, "quit"]) }
        else if (what === "toggle") {   // explicit on / off (a double click never toggles twice); v2 says whether it is paused
            const running = now && typeof now.paused === "boolean" ? !now.paused : playing
            Quickshell.execDetached([app, "pause", running ? "on" : "off"])
        }
        else if (what === "mute" || what === "unmute") {
            reqMuted = what === "mute" ? 1 : 0
            pendingReset.restart()
            Quickshell.execDetached([app, "mute", what === "mute" ? "on" : "off"])
        } else if (what.indexOf("volume:") === 0) {
            reqVolume = Math.max(0, Math.min(100, parseInt(what.slice(7)) || 0)) / 100
            if (reqVolume > 0) reqMuted = 0      // the app unmutes on a volume above 0
            pendingReset.restart()
            if (!volumeGate.running) sendVolume()
        } else if (what === "raise")
            Quickshell.execDetached(["sh", "-c", "hyprctl clients -j | jq -r '.[]|select(.class==\"org.quickshell\" and (.title|startswith(\"Twitch - \")))|.address' | head -n1 | xargs -I{} hyprctl dispatch 'hl.dsp.focus({window=\"address:{}\"})'"])
    }
}
