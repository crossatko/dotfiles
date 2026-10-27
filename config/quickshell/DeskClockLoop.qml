import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The desktop clock's copy of a LOOPING video wallpaper (theme.py mode "loop": mpvpaper loop-file=inf), loaded by
// DeskClockVideo: the same file the desktop player shows, played continuously in QtMultimedia and kept in step with it
// through the player's mpv JSON-IPC socket (one persistent client).
// Sync: observe_property pause / path / duration / container-fps (events only on change), `time-pos` asked every 2.5 s
// (0.6 s while correcting; and 250 ms after each `playback-restart` event = mpv's wrap). Offset = copy position (the
// last positionChanged report extrapolated to the reply's moment) - mpv time-pos - `lead`, modulo the clip length.
// Within half a frame: nothing; up to `seekOver`: a playbackRate nudge (+-3 %, invisible) or, when early, a hold (the
// copy pauses on its frame exactly that long). Beyond: a CUE. A seek while playing (FFmpeg backend) stands still
// 0.35-1.4 s and then either catches up or not (0-0.45 s late, unpredictably), so a cue seeks while PAUSED to
// `cueAhead` ahead of mpv, waits for that frame, and play()s when mpv gets there (pause / play has no such latency).
// The wrap: mpv's loop-file seek back takes longer than the copy's (~50 ms): the copy holds its last frame that long
// (`wrapHold`, learned from the offset right after each wrap). A cue never lands in the clip's last moments (the backend
// then plays on past the end on a frozen frame): the copy holds its frame until mpv wraps.
// Decodes only while wanted: shown (no ancestor hidden or at opacity 0: DeskClock hides the clock while locked), no
// fullscreen window on the monitor, the monitor not off (DPMS), mpv not paused and really advancing (a desktop player
// that stops moving while unpaused pauses the copy too). `ready` once a decoded frame arrived and one sample was
// in step; a missing / unplayable file stays not ready (DeskClockView keeps the still).
// Test hook: QS_DESKCLOCK_SYNC_LOG=1 logs every sample (copy vs mpv).
Item {
    id: l
    property string connector: ""
    property string socketPath: ""
    property int pid: 0                       // the player's; a new one (new wallpaper, restarted player) reconnects
    property string probeFile: ""             // bin/lock-video's; mpv's own `path` wins once it arrives (e.g. after a swap)
    property string mpvPath: ""
    readonly property string file: mpvPath !== "" ? mpvPath : probeFile
    readonly property bool ready: hadFrame && synced && file !== ""
    readonly property alias output: out

    // tuning (ms)
    property real lead: -8                    // presentation: with 0 the copy showed ~1 frame early at 60 fps (frame-matched screenshots)
    property real seekOver: 120
    property real maxNudge: 0.03
    property real cueAhead: 1000              // grows when a cued frame comes too late
    property real wrapHold: 50

    property bool hadFrame: false
    property bool synced: false
    property bool mpvPaused: false
    property real mpvDuration: 0              // ms
    property real frameMs: 1000 / 60          // mpv container-fps
    property bool stalled: false
    property real lastMpv: -1                 // last time-pos (ms) and when it was taken, for the stall check
    property real lastMpvWall: 0
    property bool held: false                 // this wrap's hold happened (learn from the next post-wrap sample)
    property bool afterWrap: false
    property bool afterCue: false
    property int cues: 0                      // cues in a row (reset once in step): no cue loop
    readonly property bool log: Quickshell.env("QS_DESKCLOCK_SYNC_LOG") === "1"

    readonly property var hmon: Hyprland.monitors.values.find(m => m.name === l.connector) ?? null
    readonly property bool covered: hmon?.activeWorkspace?.lastIpcObject?.hasfullscreen ?? false
    // every ancestor visible and not transparent (the binding follows each of them)
    readonly property bool shown: {
        for (let o = l; o; o = o.parent) if (!o.visible || o.opacity <= 0) return false
        return true
    }
    // screen off (DPMS): Hyprland sends no event for it, so the monitor state is re-read every 3 s while the copy would play
    readonly property bool screenOff: hmon?.lastIpcObject?.dpmsStatus === false
    Timer {
        interval: 3000; repeat: true
        running: l.file !== "" && sock.connected && l.shown && !l.covered && !l.mpvPaused
        onTriggered: Hyprland.refreshMonitors()
    }
    readonly property bool wanted: file !== "" && sock.connected && shown && !covered && !screenOff && !mpvPaused && !stalled
    onWantedChanged: {
        if (log) console.log("deskclock-sync", connector, "wanted", wanted, "shown", shown, "covered", covered, "off", screenOff, "paused", mpvPaused, "stalled", stalled)
        apply()
    }
    onPidChanged: reconnect()
    onSocketPathChanged: reconnect()
    function reconnect() {
        synced = false; stalled = false; lastMpv = -1; mpvPath = ""
        sock.connected = false
        retry.tries = 0; retry.interval = 500
        if (socketPath !== "") Qt.callLater(() => { sock.connected = true })
    }
    // theme.py writes the state file right after spawning the player, before mpv opens its socket: retry a few times
    // (0.5 s doubling, 6 tries; a dead player's leftover socket gives up)
    Timer {
        id: retry
        property int tries: 0
        interval: 500
        running: l.socketPath !== "" && !sock.connected && tries < 6
        onTriggered: { tries++; interval *= 2; sock.connected = true }
    }

    function stopTimers() { holdTimer.stop(); startTimer.stop(); cueTimeout.stop(); wrapTimer.stop(); cueing = false }
    function apply() {
        if (player.mediaStatus === MediaPlayer.NoMedia || player.mediaStatus === MediaPlayer.LoadingMedia
            || player.mediaStatus === MediaPlayer.InvalidMedia) return
        if (!wanted) { stopTimers(); player.pause(); player.playbackRate = 1; return }
        ask()           // play()s / cues on the reply
    }

    // ---- mpv IPC ----
    Socket {
        id: sock
        path: l.socketPath
        onConnectedChanged: {
            if (!connected) { l.synced = false; return }
            retry.tries = 0; retry.interval = 500
            l.send({ command: ["observe_property", 1, "pause"] })
            l.send({ command: ["observe_property", 2, "path"] })
            l.send({ command: ["observe_property", 3, "duration"] })
            l.send({ command: ["observe_property", 4, "container-fps"] })
        }
        parser: SplitParser {
            onRead: line => l.onMpv(line)
        }
    }
    function send(o) { sock.write(JSON.stringify(o) + "\n"); sock.flush() }
    property real askWall: 0
    property int reqId: 100
    function ask() {
        if (!sock.connected) return
        reqId = reqId >= 1000000 ? 100 : reqId + 1
        askWall = Date.now()
        send({ command: ["get_property", "time-pos"], request_id: reqId })
    }
    function onMpv(line) {
        let m = null
        try { m = JSON.parse(line) } catch (e) { return }
        if (!m) return
        if (m.event === "property-change") {
            if (m.id === 1) mpvPaused = m.data === true
            else if (m.id === 2 && typeof m.data === "string" && m.data !== "" && m.data !== mpvPath) { synced = false; mpvPath = m.data }
            else if (m.id === 3) mpvDuration = typeof m.data === "number" ? m.data * 1000 : 0
            else if (m.id === 4 && typeof m.data === "number" && m.data > 1) frameMs = 1000 / m.data
        } else if (m.event === "playback-restart") {
            if (wanted) { afterWrap = true; soon.restart() }   // the wrap (or a seek / new file): check right after it
        } else if (m.request_id === reqId && m.error === "success" && typeof m.data === "number") {
            sample(m.data * 1000, (askWall + Date.now()) / 2)
        }
    }

    // the copy's position now: the last report, extrapolated (reports come every ~50 ms)
    property real repPos: 0
    property real repWall: 0
    function copyPos(wall) {
        if (player.playbackState !== MediaPlayer.PlayingState) return player.position
        return repPos + (wall - repWall) * player.playbackRate
    }
    function clipLen() { return mpvDuration > 0 ? mpvDuration : player.duration }
    function wrapped(d) {
        const len = clipLen()
        if (len <= 0) return d
        d = d % len
        if (d > len / 2) d -= len
        if (d < -len / 2) d += len
        return d
    }
    function sample(framePos, wall) {
        // time-pos is the shown frame's start; mpv's clock is anywhere in that frame: on average half a frame further
        const mpvPos = framePos + frameMs / 2
        // stall: an unpaused player whose position did not move for a second or more (output off)
        if (lastMpv >= 0 && wall - lastMpvWall >= 900 && !mpvPaused) {
            const moved = Math.abs(mpvPos - lastMpv) > 1
            if (!moved !== stalled) stalled = !moved
        }
        if (lastMpv < 0 || Math.abs(mpvPos - lastMpv) > 1 || wall - lastMpvWall > 5000) { lastMpv = mpvPos; lastMpvWall = wall }
        if (!wanted || holdTimer.running || startTimer.running || cueing) return
        const now = Date.now()
        const target = mpvPos + lead + (now - wall)       // where the copy should be now
        if (player.playbackState !== MediaPlayer.PlayingState) {
            // paused in step (mpv was paused too): just go on, after the time it is early; else cue
            const d0 = wrapped(player.position - target)
            if (Math.abs(d0) <= seekOver && cues === 0) {
                if (d0 > frameMs) { startTimer.interval = Math.round(d0); startTimer.restart() } else play()
            } else cue(target)
            return
        }
        const d = wrapped(copyPos(wall) - mpvPos - lead)
        const wrapNow = afterWrap, cueNow = afterCue
        if (afterWrap) {
            afterWrap = false
            if (held && Math.abs(d) < 4 * frameMs) wrapHold = Math.max(0, Math.min(300, wrapHold + d * 0.4))   // mpv's wrap time varies: smooth
            held = false
        }
        afterCue = false
        if (log) console.log("deskclock-sync", connector, "mpv", Math.round(framePos), "copy", Math.round(copyPos(wall)), "off", Math.round(d),
                             "rate", Math.round(player.playbackRate * 1000) / 1000, "hold", Math.round(wrapHold), wrapNow ? "wrap" : "", cueNow ? "cue" : "")
        if (d > 2 * frameMs && d < 1500 && (cueNow || d > seekOver)) {
            // early: stand still exactly that long
            player.playbackRate = 1
            player.pause()
            holdTimer.interval = Math.round(d)
            holdTimer.restart()
            if (log) console.log("deskclock-sync", connector, "hold", Math.round(d))
            return
        }
        if (Math.abs(d) > (cues >= 3 ? 1500 : seekOver)) {
            cue(target)
            return
        }
        synced = true
        armWrap()
        if (Math.abs(d) <= frameMs / 2) {   // within half a frame: the same picture (time-pos is frame-quantized)
            player.playbackRate = 1
            tick.interval = 2500
            cues = 0
        } else {
            const m = Math.abs(d) > seekOver ? 0.15 : maxNudge
            player.playbackRate = 1 - Math.max(-m, Math.min(m, d / 2000))
            tick.interval = 600
            if (Math.abs(d) <= seekOver) cues = 0
        }
    }
    function play() { player.playbackRate = 1; player.play(); afterCue = true; soon.restart() }

    // ---- cue: a paused seek ahead, started when mpv gets there ----
    property bool cueing: false
    property real cuePos: 0
    property real cueStart: 0                 // wall time mpv reaches cuePos
    property real cueWall: 0
    function cue(t) {
        const len = clipLen()
        let p = t + cueAhead
        if (len > 0 && p > len - Math.min(800, len / 4)) {
            // not into the last moments, not across the wrap: hold this frame until mpv wraps
            player.pause()
            tick.interval = 400
            if (log) console.log("deskclock-sync", connector, "wait for the wrap")
            return
        }
        if (len > 0) p = ((p % len) + len) % len
        cues++
        cueing = true
        player.playbackRate = 1
        player.pause()
        cuePos = Math.round(p)
        cueWall = Date.now()
        cueStart = cueWall + cueAhead
        player.position = cuePos
        cueTimeout.restart()
        if (log) console.log("deskclock-sync", connector, "cue", cuePos, "ahead", Math.round(cueAhead))
    }
    function cued() {
        // the cued frame is up
        cueTimeout.stop()
        cueing = false
        const wait = cueStart - Date.now()
        if (log) console.log("deskclock-sync", connector, "cued after", Date.now() - cueWall, "wait", Math.round(wait))
        if (wait > 0) { startTimer.interval = Math.max(1, Math.round(wait)); startTimer.restart() }
        else { cueAhead = Math.min(3000, cueAhead * 1.5); ask() }     // too slow: again, further ahead
    }
    Timer { id: cueTimeout; interval: 4000; onTriggered: { l.cueing = false; l.cueAhead = Math.min(3000, l.cueAhead * 1.5); l.ask() } }
    Timer { id: startTimer; onTriggered: if (l.wanted) l.play() }

    // the wrap: hold the copy's last frame as long as mpv's wrap takes (armed by every sample; the copy's rate is known)
    function armWrap() {
        const len = player.duration
        if (len <= 0 || player.playbackState !== MediaPlayer.PlayingState) { wrapTimer.stop(); return }
        const left = (len - frameMs / 2 - copyPos(Date.now())) / player.playbackRate
        if (left > 0 && left < 6000) { wrapTimer.interval = Math.max(1, Math.round(left)); wrapTimer.restart() }
        else wrapTimer.stop()
    }
    Timer {
        id: wrapTimer
        onTriggered: {
            if (!l.wanted || player.playbackState !== MediaPlayer.PlayingState) return
            l.held = true           // learn from this wrap even with no hold (it may need one again)
            if (l.wrapHold < 4) return
            player.pause()
            holdTimer.interval = Math.round(l.wrapHold)
            holdTimer.restart()
        }
    }
    Timer { id: holdTimer; onTriggered: if (l.wanted) { player.play(); soon.restart() } }
    Timer { id: tick; interval: 2500; repeat: true; running: l.wanted || l.stalled; onTriggered: l.ask() }
    Timer { id: soon; interval: 250; onTriggered: l.ask() }

    // fullscreen state: lastIpcObject is refreshed on these events (as Bar.qml), again a bit later (the first refresh can
    // still see the old state)
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (["fullscreen", "workspacev2", "focusedmonv2", "movewindowv2", "closewindow", "openwindow"].includes(ev.name)) {
                fsRefresh.restart(); fsRefresh2.restart()
            }
        }
    }
    Timer { id: fsRefresh; interval: 30; onTriggered: Hyprland.refreshWorkspaces() }
    Timer { id: fsRefresh2; interval: 400; onTriggered: Hyprland.refreshWorkspaces() }

    MediaPlayer {
        id: player
        // only while the desktop player answers: a file it cannot play (it exits) is not looped here either (the FFmpeg
        // backend spins on a broken file with loops = Infinite, even paused)
        source: l.file !== "" && sock.connected ? "file://" + l.file : ""
        videoOutput: out
        loops: MediaPlayer.Infinite
        onSourceChanged: { l.hadFrame = false; l.synced = false; l.wrapHold = 50; l.cues = 0; l.stopTimers() }
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.LoadedMedia) l.apply()
        onPositionChanged: { l.repPos = player.position; l.repWall = Date.now() }
        onErrorOccurred: (error, errorString) => { l.hadFrame = false }
    }
    Connections {
        target: out.videoSink
        function onVideoFrameChanged() {
            if (!l.hadFrame && l.file !== "") l.hadFrame = true
            if (l.cueing) l.cued()
        }
    }
    VideoOutput {
        id: out
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop      // = mpvpaper panscan=1.0
        layer.enabled: true     // a texture provider for the glass (a ShaderEffectSource of a bare VideoOutput stays empty)
        layer.smooth: true
    }
}
