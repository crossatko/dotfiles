import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io

// The lock screen's live video wallpaper. While the session is locked the compositor draws only the lock surfaces, so the
// desktop's mpvpaper layer is hidden and the lock plays the same baked play-once clip itself: it rests on the frame the
// desktop player holds (a paused MediaPlayer = no decode loop) and `burst()` plays the next burst (bursts[idx]..bursts[idx+1],
// theme/mpv/winddown.lua) then holds again; `burstWhenReady()` plays one as soon as a frame is up (LockView, when the
// lock engages). A burst while one plays is ignored. The desktop player is NOT advanced while locked: its hidden mpvpaper
// layer gets no frame callbacks, so a burst sent to it then stalled and fast-forwarded through the backlog at unlock.
// It stays on its held frame, which is the unlock transition's snapshot, so the desktop continues seamlessly; the lock's
// own bursts are only seen on the lock (the next lock parks on the desktop's station again). Nothing is shown (`ready` false) for an image / loop wallpaper, a missing baked file or before the first frame.
// Info comes from bin/lock-video <connector> (state of theme.py's player); QS_LOCK_VIDEO overrides the helper (tests).
Item {
    id: v
    property string connector: ""
    property var info: null              // { file, bursts: [t0..tK], idx, cyc }
    property int idx: 0
    property bool playing: false
    // latched: the status drops to Buffering while a burst starts (the output keeps its last frame meanwhile), and the
    // lock must not flash back to the still then
    property bool hadFrame: false
    readonly property bool ready: info !== null && hadFrame
    readonly property var bursts: info ? info.bursts : []
    readonly property alias output: out
    // burstWhenReady(): one burst as soon as there is a frame (now, or when the clip has loaded): the lock coming alive
    property bool burstPending: false
    function burstWhenReady() { burstPending = true; if (ready) Qt.callLater(burst) }
    onReadyChanged: if (ready && burstPending) Qt.callLater(burst)

    // The visible playback never seeks, except once to park on the held frame and at the clip's wrap back to the cycle
    // start: a burst plays on from wherever the last one paused (contiguous), a finished burst just pauses (seeking a
    // paused player showed the keyframe before the exact frame: a jump).
    property bool parked: false
    function burst() {
        if (!ready || playing || bursts.length < 2) return
        burstPending = false
        playing = true
        if (Math.abs(player.position - bursts[idx] * 1000) > 250) player.position = Math.round(bursts[idx] * 1000)   // the wrap only
        player.play()
    }
    function finish() {
        player.pause()
        idx = idx + 1 >= bursts.length - 1 ? Math.min(info.cyc, bursts.length - 2) : idx + 1
        playing = false
    }

    // started a tick after the connector is known (running and command are separate bindings: the command lagged)
    onConnectorChanged: if (connector !== "") Qt.callLater(() => { probe.running = true })
    Process {
        id: probe
        command: ["python3", "-I", "-S", Quickshell.env("QS_LOCK_VIDEO") || (Quickshell.shellDir + "/bin/lock-video"), v.connector]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(text)
                    if (o && o.file && o.bursts && o.bursts.length > 1) { v.idx = o.idx; v.info = o }
                } catch (e) { /* no video wallpaper */ }
            }
        }
    }

    MediaPlayer {
        id: player
        source: v.info ? "file://" + v.info.file : ""
        videoOutput: out
        loops: 1
        // park on the held frame once loaded, and again if the backend stopped the player on its own (seen on a second
        // lock surface right after loading: stopped at 0 with no frame, i.e. an empty output)
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.LoadedMedia && (!v.parked || (playbackState === MediaPlayer.StoppedState && !v.playing))) {
            v.parked = true
            position = Math.round(v.bursts[v.idx] * 1000)
            pause()
        }
        onPositionChanged: if (v.playing && player.position >= v.bursts[v.idx + 1] * 1000 - 25) v.finish()
    }
    // ready only once a decoded frame has really arrived (the media status said "loaded" on an output that then showed
    // nothing: an empty backdrop instead of the still)
    Connections {
        target: out.videoSink
        function onVideoFrameChanged() { if (!v.hadFrame && v.info !== null) v.hadFrame = true }
    }
    VideoOutput {
        id: out
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        layer.smooth: true
        layer.enabled: true     // a texture provider for the lock backdrop (a ShaderEffectSource of a bare VideoOutput stays empty)
    }
}
