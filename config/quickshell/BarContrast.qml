pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Wallpaper brightness under the bar, for the bar's adaptive contrast (BarInk.qml decides, Bar.qml consumes).
//
// The bar draws no backdrop in flush mode (Settings > Bar), so its text sits on the wallpaper. For each bar the wallpaper
// strip behind it is sampled ONCE per (wallpaper, monitor size, bar height, edge) by bin/bar-luma (ImageMagick; cover crop
// like hyprpaper) into 64 columns of {mean, darkest tenth, brightest tenth} linear luminance; a video wallpaper
// (wallpapers.json {video, still}) is the still plus a handful of clip frames averaged (ffmpeg). Results are cached by key and
// re-requested only when the key changes: a wallpaper change (wallpapers.json / palette.json), another monitor size / scale,
// a bar height change. Nothing runs per frame; at rest this singleton is idle.
//   keyFor(screen, atTop, barPx)  cache key (also the request spec), request(key)  queue a sample if not cached
//   cols[key]                     [[mean, lo, hi] x 64] once sampled, null while pending / when the image cannot be read
//   segment(cols, f0, f1)         {mean, lo, hi} over the columns between screen-width fractions f0..f1
// Test hooks: QS_BAR_LUMA (the helper), `qs ipc call barcontrast refresh|status`.
Singleton {
    id: root

    readonly property string tool: Quickshell.env("QS_BAR_LUMA") || (Quickshell.shellDir + "/bin/bar-luma")
    property var cols: ({})              // key -> columns (replaced as a whole so bindings update); absent = not asked / pending
    property var failed: ({})            // key -> true: the helper could not read it (theme ink stays)
    property var pending: []             // keys waiting for the helper
    property string job: ""              // key being sampled
    property var bars: ({})              // screen name -> Bar, for `status`

    // still + video of a monitor's wallpaper: theme.py's wallpapers.json (LockWallpapers) or the primary wallpaper
    function stillOf(screen) { return LockWallpapers.stillFor(screen) }
    function videoOf(screen) {
        if (!screen || LockWallpapers.override !== "") return ""
        const e = LockWallpapers.monitors[Appearance.monitorKey(screen)]
        const v = e && typeof e.video === "string" ? e.video : ""
        return v.replace(/^~/, Theme.home)
    }
    // key = "still|video|screenW|screenH|barPx|edge"; "" when there is nothing to sample
    function keyFor(screen, atTop, barPx) {
        if (!screen || !(screen.width > 0) || !(screen.height > 0) || !(barPx > 0)) return ""
        const still = stillOf(screen)
        return still === "" ? "" : [still, videoOf(screen), Math.round(screen.width), Math.round(screen.height), Math.round(barPx), atTop ? "top" : "bottom"].join("|")
    }
    function request(key) {
        if (key === "" || cols[key] !== undefined || failed[key] === true || pending.indexOf(key) >= 0 || job === key) return
        pending = pending.concat([key])
        next.restart()
    }
    function refresh() {                 // forget everything (wallpaper file edited in place), bars ask again
        cols = ({}); failed = ({}); pending = []
        redo.restart()
    }

    // mean / darkest / brightest over the columns that cover screen-width fractions f0..f1 (a bar section's extent)
    function segment(c, f0, f1) {
        if (!c || c.length === 0) return null
        const n = c.length
        const a = Math.max(0, Math.min(n - 1, Math.floor(f0 * n)))
        const b = Math.max(a, Math.min(n - 1, Math.ceil(f1 * n) - 1))
        let m = 0, lo = 0, hi = 0
        for (let i = a; i <= b; i++) { m += c[i][0]; lo += c[i][1]; hi += c[i][2] }
        const k = b - a + 1
        return { mean: m / k, lo: lo / k, hi: hi / k }
    }

    Timer { id: next; interval: 0; onTriggered: root.start() }
    Timer { id: redo; interval: 0; onTriggered: root.bumped++ }
    property int bumped: 0               // bars watch this to re-request after refresh()
    function start() {
        if (job !== "" || pending.length === 0) return
        job = pending[0]
        pending = pending.slice(1)
        const p = job.split("|")
        runner.command = [tool, p[0], p[2], p[3], p[4], p[5], p[1]]
        runner.running = true
    }

    Process {
        id: runner
        stdout: StdioCollector {
            onStreamFinished: {
                const key = root.job
                let c = null
                try { c = JSON.parse(text).cols } catch (e) { c = null }
                if (Array.isArray(c) && c.length > 0) root.cols = Object.assign({}, root.cols, { [key]: c })
                else root.failed = Object.assign({}, root.failed, { [key]: true })
                root.job = ""
                next.restart()
            }
        }
    }

    IpcHandler {
        target: "barcontrast"
        function refresh(): string { root.refresh(); return "ok" }
        // one line per bar: screen, segments (left centre right) as "luma ink" with ink = dark|light text, mode, state
        function status(): string {
            const out = []
            for (const n of Object.keys(root.bars)) {
                const b = root.bars[n]
                if (!b) continue
                const f = i => i.seg ? "mean " + i.seg.mean.toFixed(3) + " lo " + i.seg.lo.toFixed(3) + " hi " + i.seg.hi.toFixed(3) + " -> " + (i.darkText ? "dark" : "light") + " text" + (i.active ? "" : " (inactive)") : "no data"
                out.push(n + " key=" + b.lumaKey + " [" + b.inkMode + " sens " + b.inkSens + " fill " + b.inkFill + " flat " + b.inkFlat + "] L: " + f(b.inkLeft) + " | C: " + f(b.inkCenter) + " | R: " + f(b.inkRight))
            }
            out.push("job=" + root.job + " pending=" + root.pending.length + " failed=" + Object.keys(root.failed).length + " cached=" + Object.keys(root.cols).length)
            return out.join("\n")
        }
    }
}
