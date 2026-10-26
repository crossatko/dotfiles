import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io

// The desktop clock's copy of a play-once video wallpaper (DeskClockView refracts it): the same baked clip the desktop
// player (mpvpaper + theme/mpv/winddown.lua) shows on `connector`, played in step with it, so the glass bends the moving
// video during a burst and the held frame at rest. Info: bin/lock-video (file, bursts, idx = the NEXT burst, station).
// Rest: parked on bursts[idx] (a paused MediaPlayer: no decode). A burst starts when the desktop player writes its station
// file (winddown.lua burst_play, right before it unpauses; the trigger is theme/mpv/replay.py on a workspace switch):
// the file watch plays the same burst from the same frame (no seek: the parked frame IS the burst start) and pauses at its
// end, where the desktop player stops too (end=). Only a station that does not follow the parked one (a burst missed
// while the shell was not running, a new bake) seeks once, at that burst's start. `ready` once a real frame arrived.
// Cost: idle none (inotify watch); a burst decodes the clip (hardware decoding where the FFmpeg backend has it).
Item {
    id: v
    property string connector: ""
    property var info: null              // { file, bursts: [t0..tK], idx, cyc, station, tag }
    property int idx: 0                  // the next burst; the held frame is bursts[idx]
    property bool playing: false
    property real endMs: 0
    property bool hadFrame: false
    readonly property bool ready: info !== null && hadFrame
    readonly property var bursts: info ? info.bursts : []
    readonly property int count: Math.max(0, bursts.length - 1)
    readonly property alias output: out

    function probe() { if (connector !== "") Qt.callLater(() => { probeProc.running = true }) }
    onConnectorChanged: probe()
    Process {
        id: probeProc
        command: ["python3", "-I", "-S", Quickshell.shellDir + "/bin/lock-video", v.connector]
        stdout: StdioCollector {
            onStreamFinished: {
                let o = null
                try { o = JSON.parse(text) } catch (e) { o = null }
                if (!o || !o.file || !o.bursts || o.bursts.length < 2) { v.info = null; v.hadFrame = false; return }
                const same = v.info && v.info.file === o.file
                v.idx = o.idx
                v.info = o
                if (same && !v.playing) v.park()
            }
        }
    }
    // the player itself changed (new wallpaper, swapped file): probe again
    FileView {
        path: v.connector !== "" ? (Quickshell.env("XDG_RUNTIME_DIR") || "") + "/theme-video/" + v.connector + ".json" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: v.probe()
    }
    // a burst started on the desktop: "<tag>:<next index>"
    FileView {
        id: station
        path: v.info && v.info.station ? v.info.station : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const m = /^(.*):(\d+)\s*$/.exec(text())
            if (!m || !v.info || m[1] !== v.info.tag || v.count < 1) return
            const n = Number(m[2]) % v.count
            if (n !== v.idx) v.burstTo(n)
        }
    }
    function nextOf(i) { return i + 1 >= count ? Math.min(info.cyc, count - 1) : i + 1 }
    function burstTo(n) {
        if (!ready) { idx = n; park(); return }
        // the burst that ends where `n` is held: normally the parked one
        let b = nextOf(idx) === n ? idx : -1
        if (b < 0) for (let i = 0; i < count; i++) if (nextOf(i) === n) { b = i; break }
        if (b < 0) { idx = n; park(); return }
        const start = Math.round(bursts[b] * 1000)
        endMs = Math.round(bursts[b + 1] * 1000)
        idx = n
        playing = true
        if (Math.abs(player.position - start) > 250) player.position = start   // the parked frame is the start (as LockVideo)
        player.play()
    }
    function park() {
        if (!info || player.mediaStatus === MediaPlayer.NoMedia) return
        playing = false
        player.position = Math.round(bursts[idx] * 1000)
        player.pause()
    }

    MediaPlayer {
        id: player
        source: v.info ? "file://" + v.info.file : ""
        videoOutput: out
        loops: 1
        property bool parkedOnce: false
        onSourceChanged: { parkedOnce = false; v.hadFrame = false }
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.LoadedMedia && (!parkedOnce || (playbackState === MediaPlayer.StoppedState && !v.playing))) {
            parkedOnce = true
            v.park()
        }
        // stop where the desktop player stops (end=): position reports come ~50 ms apart, so each one re-aims a timer at
        // the end (a report-driven pause alone overshot by ~40 ms, a few frames of the wind-down)
        onPositionChanged: {
            if (!v.playing) return
            const left = v.endMs - player.position
            if (left <= 4) v.stopAt()
            else if (left < 120) { stopTimer.interval = Math.max(1, Math.round(left - 4)); stopTimer.restart() }
        }
    }
    Timer { id: stopTimer; onTriggered: v.stopAt() }
    function stopAt() { stopTimer.stop(); if (playing) { player.pause(); playing = false } }
    Connections {
        target: out.videoSink
        function onVideoFrameChanged() { if (!v.hadFrame && v.info !== null) v.hadFrame = true }
    }
    VideoOutput {
        id: out
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop      // = mpvpaper panscan=1.0
        layer.enabled: true     // a texture provider for the glass (a ShaderEffectSource of a bare VideoOutput stays empty)
        layer.smooth: true
    }
}
