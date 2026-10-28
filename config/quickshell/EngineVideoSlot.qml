import QtQuick
import QtMultimedia
import Quickshell

// One player of the wallpaper engine (EngineVideo keeps two: the clip on screen and the next one loading under it).
// `rec` = this monitor's player record from theme.py (theme-video/engine/players.json, see engine.qml):
//   { video, file, mode: "loop" | "once", baked, bursts: [t0..tK] (s), cyc, tag, station, stop (s, unbaked once) }
// Loop: MediaPlayer loops forever (gapless: the FFmpeg backend wraps inside the decoder, no seek).
// Play-once: `begin(fromMs, toMs)` plays a stretch and PAUSES on its last frame before `toMs` (exclusive; frames are
// counted between the backend's ~50 ms position reports, see below). The player loops for these too, so it never stops at
// the file's end (EndOfMedia empties the output). A baked
// clip (theme.py bake_*) holds the ease-in / wind-down in the file: the first play is 0..bursts[0], burst i is
// bursts[i]..bursts[i+1] (winddown.lua semantics, `idx` = the NEXT burst, `cyc` = where the cycle continues after the
// last one); an unbaked clip plays 0..stop (no runtime speed ramp: a plain pause at t_stop = play + wind x WIND_AVG).
// `park(ms)` = paused on that frame (no decode). `hadFrame` latches once a decoded frame arrived (the slot is shown
// only then: no black frame at a swap). `held` = engine-wide pause (lock, cover, DPMS): no decode, resumes in place.
Item {
    id: s
    property var rec: null
    readonly property string file: rec && typeof rec.file === "string" ? rec.file : ""
    readonly property bool loop: !!rec && rec.mode === "loop"
    readonly property var bursts: rec && Array.isArray(rec.bursts) ? rec.bursts : []
    readonly property int count: Math.max(0, bursts.length - 1)
    property int idx: 0
    property bool playing: false        // a play-once stretch is running (first play / burst / replay)
    property real endMs: -1
    property bool hadFrame: false
    property bool held: false
    // what to do once the clip is loaded: { play: bool, at: ms, to: ms (play-once end), half: park half a frame before `at` }
    property var plan: null
    readonly property alias player: mp
    readonly property alias output: out
    readonly property real fps: {
        const r = Number(mp.metaData.value(MediaMetaData.VideoFrameRate))
        return r > 1 && r < 1000 ? r : 30
    }
    readonly property real frameMs: 1000 / fps
    readonly property bool loaded: mp.mediaStatus === MediaPlayer.LoadedMedia || mp.mediaStatus === MediaPlayer.BufferedMedia
                                   || mp.mediaStatus === MediaPlayer.BufferingMedia || mp.mediaStatus === MediaPlayer.EndOfMedia
    signal stretchDone()
    readonly property bool debug: Quickshell.env("QS_ENGINE_DEBUG") === "1"     // log positions / frames / status of stretches
    property real reportPos: 0
    property int sinceReport: 0
    readonly property real frameAt: reportPos + Math.max(0, sinceReport) * frameMs     // media ms of the frame just delivered

    function url(p) { return p ? "file://" + p.split("/").map(encodeURIComponent).join("/") : "" }
    function load(r, p) {
        rec = r
        plan = p
        hadFrame = false
        playing = false
        endMs = -1
        mp.source = url(file)
        if (loaded) start()
    }
    function unload() {
        mp.stop()
        mp.source = ""
        rec = null
        plan = null
        playing = false
        hadFrame = false
    }
    function start() {
        const p = plan
        plan = null
        if (!p) return
        if (p.play) begin(p.at, p.to)
        else park(p.half ? p.at - frameMs * 0.5 : p.at)     // half: the frame just before `at` (a stretch's end is exclusive)
    }
    function park(ms) {
        playing = false
        endMs = -1
        mp.position = Math.max(0, Math.round(ms))
        mp.pause()
    }
    // play from `fromMs` (no seek when the player already stands there: a burst continues from the held frame) to `toMs`
    // (-1 = loop / to the end)
    function begin(fromMs, toMs) {
        endMs = loop ? -1 : (toMs > 0 ? toMs : Math.max(1, mp.duration))
        playing = !loop
        if (Math.abs(mp.position - fromMs) > frameMs * 1.5) mp.position = Math.max(0, Math.round(fromMs))
        if (!held) mp.play()
    }
    function finish() {
        if (debug) console.log("EV finish " + Date.now() + " at " + frameAt + " pos " + mp.position + " status " + mp.mediaStatus)
        mp.pause()
        playing = false
        endMs = -1
        stretchDone()
    }
    onHeldChanged: {
        if (!file) return
        if (held) mp.pause()
        else if (loop || playing) mp.play()
    }

    MediaPlayer {
        id: mp
        videoOutput: out
        // play-once clips loop too: at the end of the file a single-pass player stops (EndOfMedia) and its output goes
        // EMPTY (measured: the still under it showed through); looping, the decoder wraps and the stretch pauses on the
        // last frame before the wrap is shown (frameAt), the next burst seeks anyway
        loops: MediaPlayer.Infinite
        onMediaStatusChanged: {
            if (s.debug) console.log("EV status " + Date.now() + " " + mp.mediaStatus + " pos " + mp.position + " state " + mp.playbackState)
            if (mp.mediaStatus === MediaPlayer.LoadedMedia && s.plan) s.start()
            // a play-once clip reached its end after all (a stretch planned to the very end): hold, never show the EOF black
            if (mp.mediaStatus === MediaPlayer.EndOfMedia && !s.loop && s.playing) s.finish()
        }
        // the backend reports the position only every ~50 ms (3 frames at 60 fps), right before the frame at that time
        // arrives; the frames in between are counted (frameAt), so the stretch pauses on its exact last frame
        onPositionChanged: {
            s.reportPos = mp.position
            s.sinceReport = -1
            if (s.debug && s.playing) console.log("EV pos " + Date.now() + " " + mp.position + " end " + s.endMs)
            if (s.playing && s.endMs > 0 && mp.position >= s.endMs - s.frameMs * 0.5) s.finish()   // (frames missed: at least stop now)
        }
        onErrorOccurred: (error, message) => console.warn("engine: " + s.file + ": " + message)
    }
    Connections {
        target: out.videoSink
        function onVideoFrameChanged() {
            if (!s.hadFrame && s.file !== "") s.hadFrame = true
            s.sinceReport += 1
            if (s.debug && s.playing) console.log("EV frame " + Date.now() + " at " + s.frameAt)
            // the backend delivers ONE more frame after pause() (it is already queued; measured: always exactly one, also the
            // wrapped first frame at the file's end), so pause on the second-to-last frame before the end (exclusive)
            if (s.playing && s.endMs > 0 && s.frameAt + s.frameMs * 2.5 > s.endMs) s.finish()
        }
    }
    VideoOutput {
        id: out
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
    }
}
