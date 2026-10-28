import QtQuick
import Quickshell.Io

// A monitor's video wallpaper in the wallpaper engine (EngineWindow, over the still / image of WallpaperView): two
// EngineVideoSlot players. A new clip (another file in `record`) loads in the hidden slot, is positioned (loop: the saved
// / carried-over position; play-once: first play, or parked on the held frame) and fades in over the shown one once it
// has a decoded frame (Motion.emphasisMs, the wallpaper's own cross-fade; motion off = a cut), then the old one is
// unloaded: only during a fade do two clips decode. `record` null = no video: the shown clip fades out onto the still.
// A change that arrives while a play-once stretch plays waits for its end (no clip cut mid-burst).
// replay(): the next burst of a play-once clip (workspace switch; ignored while one plays = the debounce).
// `held` (engine: lock, fullscreen cover, DPMS off, IPC pause) pauses both players in place.
// Persistence: `saved` = { file, pos (ms) } from the last run (engine.qml state file): the same file resumes there once.
// The burst index is shared with theme.py and the lock (bin/lock-video) through the station file (winddown.lua's format,
// "<tag>:<next index>"), written when a burst starts.
Item {
    id: v
    property var record: null
    property bool held: false
    property var saved: null
    readonly property var slots: [a, b]
    property int front: 0
    readonly property EngineVideoSlot shown: slots[front]
    readonly property EngineVideoSlot back: slots[1 - front]
    property EngineVideoSlot fading: null
    // a clip is on screen (or fading in / out over the still)
    readonly property bool showing: shown.file !== "" && shown.hadFrame && shown.opacity > 0.5
    readonly property bool busy: (back.file !== "" && !back.hadFrame) || fade.running
    readonly property int fadeMs: Motion.emphasisMs
    readonly property real loadOpacity: 0.004   // a slot loading under the shown one: drawn (an undrawn VideoOutput gets no frames), unseen
    signal changed()

    function same(r1, r2) { return !!r1 && !!r2 && r1.file === r2.file && r1.mode === r2.mode && (r1.tag || "") === (r2.tag || "") }
    function ms(t) { return Math.round(Number(t) * 1000) }

    // where a newly loaded clip starts: { play, at, to, idx }
    function planFor(r, prev) {
        const sv = v.saved && v.saved.file === r.file && Number(v.saved.pos) >= 0 ? v.saved : null
        v.saved = null                                       // a restart's position is used once
        const sameVideo = prev && prev.file !== "" && prev.rec && prev.rec.video === r.video
        if (r.mode === "loop") {
            // an optimized copy of the clip on screen = the same timeline: carry the position over (+ the load time)
            if (sameVideo && prev.loop) return { play: true, at: prev.player.position + 150, to: -1, idx: 0 }
            return { play: true, at: sv ? sv.pos : 0, to: -1, idx: 0 }
        }
        const bursts = Array.isArray(r.bursts) ? r.bursts : []
        if (bursts.length > 1) {
            const k = bursts.length - 1
            const idx = Math.max(0, Math.min(k - 1, v.stationIdx(r)))
            if (sv) return { play: false, at: sv.pos, idx: idx }                          // engine restart: where it was
            // the same video held on screen (its unbaked first play is over): the baked file parks on that frame (H)
            if (sameVideo && !prev.playing) return { play: false, at: v.ms(bursts[idx]), half: true, idx: idx }
            if (idx > 0) return { play: false, at: v.ms(bursts[idx]), half: true, idx: idx }      // the station survived (runtime dir)
            return { play: true, at: 0, to: v.ms(bursts[0]), idx: 0 }                       // a new clip: the first play, held on H
        }
        const stop = Number(r.stop) > 0 ? v.ms(r.stop) : -1
        if (sv) return { play: false, at: sv.pos, idx: 0 }
        if (sameVideo && !prev.playing) return { play: false, at: stop > 0 ? stop : prev.player.position, half: stop > 0, idx: 0 }
        return { play: true, at: 0, to: stop, idx: 0 }
    }
    function stationIdx(r) {
        if (!r.station) return 0
        station.path = r.station
        station.reload()
        const m = /^(.*):(\d+)\s*$/.exec(station.text())
        return m && m[1] === (r.tag || "") ? Number(m[2]) : 0
    }
    FileView { id: station; blockLoading: true; printErrors: false }

    function apply() {
        const r = v.record
        if (fade.running) return                              // the fade's end re-applies
        if (shown.playing && !v.same(r, shown.rec)) return    // mid-burst: after it (stretchDone)
        if (!r || !r.file) {
            back.unload()
            if (shown.file !== "") fadeOut()
            return
        }
        if (v.same(r, shown.rec)) {                           // the same clip: refreshed fields only (stop, ...)
            shown.rec = r
            back.unload()
            return
        }
        if (v.same(r, back.rec)) return                       // already loading
        const p = v.planFor(r, shown)
        back.held = v.held
        back.idx = p.idx
        back.opacity = v.loadOpacity
        back.load(r, p)
    }
    function fadeOut() {
        if (v.fadeMs <= 0) { shown.unload(); shown.opacity = 0; v.changed(); return }
        v.fading = shown
        fadeAnim.from = shown.opacity
        fadeAnim.to = 0
        fade.restart()
    }
    function backReady() {
        if (!back.hadFrame || back.file === "" || fade.running) return
        if (v.fadeMs <= 0) { swap(); return }
        v.fading = back
        fadeAnim.from = back.opacity
        fadeAnim.to = 1
        fade.restart()
    }
    function swap() {
        const old = shown
        back.opacity = 1
        v.front = 1 - v.front
        old.unload()
        old.opacity = 0
        v.changed()
    }
    function fadeDone() {
        if (v.fading === back) swap()
        else if (v.fading === shown) { shown.unload(); shown.opacity = 0; v.changed() }
        v.fading = null
        Qt.callLater(v.apply)
    }

    // the next burst of a play-once clip (baked: bursts[idx]..bursts[idx + 1]; unbaked: 0..stop again); false = ignored
    function replay() {
        const s = shown
        if (!s.rec || s.loop || s.playing || !s.hadFrame || v.held || fade.running) return false
        if (s.count > 0) {
            const i = Math.max(0, Math.min(s.count - 1, s.idx))
            s.begin(v.ms(s.bursts[i]), v.ms(s.bursts[i + 1]))
            s.idx = i + 1 >= s.count ? Math.max(0, Math.min(s.count - 1, Number(s.rec.cyc) || 0)) : i + 1
            if (s.rec.station) { stationOut.path = s.rec.station; stationOut.setText((s.rec.tag || "") + ":" + s.idx + "\n") }
        } else {
            s.begin(0, Number(s.rec.stop) > 0 ? v.ms(s.rec.stop) : -1)
        }
        v.changed()
        return true
    }
    FileView { id: stationOut; printErrors: false }

    onRecordChanged: apply()
    onHeldChanged: { a.held = held; b.held = held; v.changed() }

    EngineVideoSlot {
        id: a
        anchors.fill: parent
        opacity: 0
        visible: opacity > 0 && file !== ""
        z: v.front === 0 ? 0 : 1
        onHadFrameChanged: if (hadFrame && v.back === a) v.backReady()
        onStretchDone: { v.changed(); Qt.callLater(v.apply) }
    }
    EngineVideoSlot {
        id: b
        anchors.fill: parent
        opacity: 0
        visible: opacity > 0 && file !== ""
        z: v.front === 1 ? 0 : 1
        onHadFrameChanged: if (hadFrame && v.back === b) v.backReady()
        onStretchDone: { v.changed(); Qt.callLater(v.apply) }
    }
    SequentialAnimation {
        id: fade
        NumberAnimation { id: fadeAnim; target: v.fading; property: "opacity"; duration: v.fadeMs; easing.type: Motion.easeHover }
        ScriptAction { script: v.fadeDone() }
    }
}
