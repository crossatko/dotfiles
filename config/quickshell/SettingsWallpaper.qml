pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Settings -> Wallpaper & theme. Top to bottom:
//  - title row (`headerItem`): the theme source's file name + the current palette swatches (stays put while scrolling);
//  - with 2+ monitors: the MonitorSection (primary first; the shared Settings pick, Monitors.selected) picks the monitor
//    being edited; the palette glyph marks the palette source (the monitor whose wallpaper sets the colour theme), the
//    link buttons between chips link neighbours, and the row ends in the monitor-level actions: "Follow primary"
//    (`theme.py clear`, a monitor with its own wallpaper) and "Use for palette" (`theme.py primary`);
//  - "Wallpaper" with two tabs, Images (wallpaper_dirs) and Videos (video_dirs), and the thumbnail grid (WallpaperTile)
//    of that library. The Videos tab adds the Playback row (Play once / Loop): the mode of the video the monitor plays
//    (switching re-applies it) and of the next video clicked.
// A click (or arrows + Enter) runs `theme.py apply <file> [--mode once|loop] [--monitor <key>]` detached; it shows the
// wallpaper at once (hyprpaper live set / the player) and leaves the rest to its background worker: for the primary the
// re-theme, for another monitor the still only. The clicked tile is marked at once; clicks never wait (the latest wins,
// theme.py supersedes the older worker); the palette glyph in the title row pulses while the worker runs
// ($XDG_RUNTIME_DIR/theme-apply/status.json). theme.py owns the state (wallpapers.json, AGENTS.md "Wallpapers (per
// monitor, videos, links)"); this page only reads it.
// Tabs: Tab / Shift+Tab. The page opens on the tab matching what the edited monitor shows; a tab picked by hand is kept
// for the session (Settings' `memory` page hook).
// Monitor links: a MonitorLink between neighbouring chips links them; a linked group always gets the
// same wallpaper: every apply / mode / timing / "Follow primary" goes out as ONE theme.py call naming every monitor of the
// group (`--monitor k` repeated; the links live in wallpapers.json `links`, written by `theme.py link|unlink`).
// Test hook: `qs ipc call wallpaperpage tab images|videos`, `... monitor <key>` (only while the page is open).
ColumnLayout {
    id: page
    spacing: 12

    readonly property bool wantsFocus: true    // Settings.qml gives this page the keyboard focus
    property Flickable flick: null             // set by Settings.qml; keeps the keyboard selection in view
    property var memory: null                  // set by Settings.qml: session state {tabs, target, mode}

    readonly property var dirs: Theme.wallpaperDirs
    readonly property var videoDirs: Theme.videoDirs
    property var files: []
    readonly property var images: files.filter(f => !isVideo(f))
    readonly property var videos: files.filter(f => isVideo(f))
    property bool scanned: false
    property int sel: -1                       // keyboard selection (index into `list`), -1 = none yet
    property string applying: ""               // path of the latest click, cleared once the monitor shows it (shown as current until then)
    property string applyingMode: ""           // video mode handed to theme.py ("" for an image)
    property string newMode: "once"            // mode for a video clicked while the monitor plays none
    property var thumbs: ({})                  // video path -> cached still (jpg), filled in async
    property bool thumbsDone: false            // thumbnailing finished: a video without one is unreadable (skipped)
    function unreadable(p) { return isVideo(p) && thumbsDone && !thumbs[p] }
    function isVideo(p) { return /\.(mp4|webm|mkv)$/i.test(p) }
    function baseName(p) { return String(p).split("/").pop() }
    readonly property string currentPath: Theme.wallpaper.replace(/^~/, Theme.home)   // the primary's (a video's still)

    // ---- per-monitor state (theme.py's wallpapers.json: { primary, monitors: { key: image|video }, primary_video }) ----
    readonly property string stateFile: {
        const env = Quickshell.env("QS_WALLPAPERS_FILE")
        if (env) return String(env)
        const xdg = Quickshell.env("XDG_STATE_HOME")
        return (xdg ? String(xdg) : Quickshell.env("HOME") + "/.local/state") + "/theme/wallpapers.json"
    }
    property var wpMonitors: ({})
    property var wpLinks: []                   // [[keyA, keyB], ...] edges; chained edges form a group
    property bool optimize: true               // "Optimize for monitor" (theme.py video optimize on|off), default on
    property bool optBusy: false
    property string optSpeed: "background"     // how the copies are encoded (theme.py video optimize-speed background|balanced|fast); same output either way
    function setOptSpeed(v) {
        optSpeed = v   // no apply, no player restart: a running encode is only re-prioritized
        Quickshell.execDetached(["python3", "-I", Theme.themeDir + "/theme.py", "video", "optimize-speed", v])
    }
    property var optJob: ({})                  // {state: encoding|idle, label, pct} written by the background encoder
    readonly property string optFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/theme-video/optimize.json"
    function setOptimize(on) {
        optBusy = true
        optBusyTimer.restart()
        optimize = on
        Quickshell.execDetached(["python3", "-I", Theme.themeDir + "/theme.py", "video", "optimize", on ? "on" : "off"])
    }
    // a runner that was killed cannot write "idle": while the file says encoding, check that its pid is still alive
    Timer { id: pidCheck; interval: 3000; repeat: true; running: page.optJob.state === "encoding" && page.optJob.pid > 0
        onTriggered: { pidProc.command = ["test", "-d", "/proc/" + page.optJob.pid]; pidProc.running = true } }
    Process { id: pidProc; onExited: code => { if (code !== 0) page.optJob = ({}) } }
    Timer { id: optBusyTimer; interval: 4000; onTriggered: page.optBusy = false }
    FileView {
        id: optView
        path: page.optFile
        printErrors: false
        onLoaded: { try { page.optJob = JSON.parse(text()) } catch (e) { page.optJob = ({}) } }
        onLoadFailed: page.optJob = ({})
    }
    // the file is created by the first encode (watching a missing file sees no creation): poll while the Videos tab shows
    Timer { interval: 1000; repeat: true; running: page.visible && page.tab === "videos"; triggeredOnStart: true; onTriggered: optView.reload() }
    property var wpPrimaryVideo: null          // {video, mode, still} when the primary holds a video
    property string wpPrimary: ""
    // connected screens with a usable key (same key as Appearance / managed.lua use), primary first
    readonly property var monitors: Monitors.ordered.filter(s => s.width > 0 && Appearance.monitorKey(s) !== "")
    // the palette source ("primary" in wallpapers.json): the stored one if it is connected, else the shell's primary
    // monitor (theme.py primary_key / shell_primary_key: the same rule)
    readonly property string primaryKey: {
        const ms = monitors
        if (ms.length === 0) return ""
        if (wpPrimary !== "" && ms.some(s => Appearance.monitorKey(s) === wpPrimary)) return wpPrimary
        return ms.some(s => Appearance.monitorKey(s) === Monitors.primaryKey) ? Monitors.primaryKey : Appearance.monitorKey(ms[0])
    }
    // the monitor being edited: the shared Settings pick (MonitorSection / Monitors.selected), else the palette source
    readonly property string pickedKey: Monitors.selected ? Appearance.monitorKey(Monitors.selected) : ""
    readonly property string target: monitors.some(s => Appearance.monitorKey(s) === pickedKey) ? pickedKey : primaryKey
    readonly property bool multi: monitors.length > 1
    readonly property bool targetIsPrimary: target === primaryKey
    // ---- monitor links ----
    function keyAt(i) { return i >= 0 && i < monitors.length ? Appearance.monitorKey(monitors[i]) : "" }
    function groupKeys(key) {      // key first, then everything linked to it (directly or through a chain), connected or not
        const g = [key]
        for (let i = 0; i < g.length; i++)
            for (const p of wpLinks) {
                if (!Array.isArray(p) || p.length !== 2) continue
                if (p[0] === g[i] && g.indexOf(p[1]) < 0) g.push(p[1])
                else if (p[1] === g[i] && g.indexOf(p[0]) < 0) g.push(p[0])
            }
        return g
    }
    function linkedKeys(a, b) { return wpLinks.some(p => Array.isArray(p) && ((p[0] === a && p[1] === b) || (p[0] === b && p[1] === a))) }
    // the group of the monitor being edited, as connected monitors only (an unplugged member is applied to too, but not shown)
    readonly property var group: groupKeys(target).filter(k => k === target || monitors.some(s => Appearance.monitorKey(s) === k))
    readonly property bool linkedGroup: group.length > 1
    function toggleLink(i) {
        const a = keyAt(i), b = keyAt(i + 1)
        if (a === "" || b === "") return
        busyState = true
        busyTimer.restart()
        // linking: the group takes the edited monitor's wallpaper (when it is not part of either side, the left card's)
        Quickshell.execDetached(linkedKeys(a, b) ? ["python3", "-I", Theme.themeDir + "/theme.py", "unlink", a, b]
            : ["python3", "-I", Theme.themeDir + "/theme.py", "link", a, b, "--from", groupKeys(a).concat(groupKeys(b)).indexOf(target) >= 0 ? target : a])
    }
    function screenOf(key) { return monitors.find(s => Appearance.monitorKey(s) === key) || null }
    function titleOf(s) { return s ? (s.model || s.name) : "" }
    // a non-primary monitor with its own entry; without one it shows whatever the primary shows
    function ownFor(key) { return key !== primaryKey && wpMonitors[key] !== undefined && wpMonitors[key] !== null }
    function entryFor(key) {      // image path or video object
        if (ownFor(key)) return wpMonitors[key]
        return wpPrimaryVideo ? wpPrimaryVideo : (stillVideo(currentPath) || currentPath)
    }
    // A wallpaper that is a cached video still ("<stem>-once2|loop-<hash>[-t<ms>].png" in theme/video/) with no primary_video
    // in the state file (older state, or a hand-edited theme.toml): map it back to the video in video_dirs, so the
    // cards and the header name the video and its mode instead of the cache file.
    function stillVideo(path) {
        if (typeof path !== "string" || path.indexOf("/theme/video/") < 0) return null
        const m = /^(.*)-(once2|once|loop)-[0-9a-f]{12}(?:-t\d+)?\.png$/.exec(baseName(path))
        if (!m) return null
        const v = videos.find(f => baseName(f).replace(/\.[^.]+$/, "").slice(0, 40) === m[1])
        return v ? { video: v, mode: m[2] === "loop" ? "loop" : "once", still: path } : null
    }
    function videoFor(key) {
        const e = entryFor(key)
        return e && typeof e === "object" ? String(e.video).replace(/^~/, Theme.home) : ""
    }
    function modeFor(key) {
        const e = entryFor(key)
        return e && typeof e === "object" ? (e.mode === "loop" ? "loop" : "once") : ""
    }
    function numFor(key, field) {   // seconds of the play-once timing of the clip on that monitor (0 = none)
        const e = entryFor(key)
        const v = e && typeof e === "object" ? Number(e[field]) : 0
        return isFinite(v) && v > 0 ? v : 0
    }
    function timingFor(key) {     // the entry stores its timing (no `play` = the defaults, theme.py timing_default)
        const e = entryFor(key)
        return !!e && typeof e === "object" && e.play !== undefined
    }
    function fullFor(key) {       // stored full length (`play: "full"`)
        return timingFor(key) && !isFinite(Number(entryFor(key).play))
    }
    function easeFor(key) {      // replay ease-in seconds of that monitor's entry, -1 = none stored (theme.toml default)
        const e = entryFor(key)
        const v = e && typeof e === "object" && e.ease !== undefined ? Number(e.ease) : -1
        return isFinite(v) && v >= 0 ? v : -1
    }
    function shownFor(key) {      // the image on that monitor (a video's still)
        const e = entryFor(key)
        if (e && typeof e === "object") return String(e.still).replace(/^~/, Theme.home)
        return e ? String(e).replace(/^~/, Theme.home) : currentPath
    }
    function detailFor(key) {
        if (key !== primaryKey && !ownFor(key)) return "same as primary"
        const v = videoFor(key)
        return v !== "" ? baseName(v) + " · " + (modeFor(key) === "loop" ? "loop" : "once") : baseName(shownFor(key))
    }
    readonly property string shown: shownFor(target)   // the image on the monitor being edited
    readonly property string shownVideo: videoFor(target)
    readonly property string shownMode: modeFor(target)
    // Play for / Wind down (play-once only): what the sliders show. Follows the playing clip's entry; while a drag is
    // being applied (retimeTimer / busyState) the dragged value wins so the sliders never jump back.
    readonly property real statePlay: timingFor(target) ? numFor(target, "play") : playDefault
    readonly property real stateWind: timingFor(target) ? numFor(target, "wind") : windDefault
    readonly property bool stateFull: fullFor(target)
    // nothing stored = theme.toml replay_play_default / replay_wind_default (theme.py `video thumbs` reports them)
    property real playDefault: 0
    property real windDefault: 5
    property real uiPlay: 0
    property real uiWind: 5
    property bool uiFull: false              // Play for at its maximum = the whole usable length, no wind down
    property bool timingDirty: false
    // Play for and Wind down share the clip: play + wind * windAvg <= D. D = whole usable seconds of the playing video
    // (theme.py `video thumbs`, cached), windAvg = the curve's mean speed (theme.py WIND_AVG; the wind consumes wind * windAvg s).
    property var usable: ({})                // video path -> whole usable seconds, filled in async with the thumbs
    property real windAvg: 0.5
    // Replay ease-in: seconds every workspace-switch burst takes to speed up from rest (0 = none; a burst is ease-in + wind-down,
    // at least 1 s). Stored in the entry as `ease` once the slider was touched; until then the theme.toml `replay_ease_in` default.
    readonly property real easeMax: 1
    property real easeDefault: 0
    readonly property bool stateEaseSet: easeFor(target) >= 0
    readonly property real stateEase: stateEaseSet ? easeFor(target) : easeDefault
    property real uiEase: 0
    property bool uiEaseSet: false
    readonly property real maxPlay: shownVideo !== "" && usable[shownVideo] > 0 ? usable[shownVideo] : 60   // no video yet: theme.py clamps on apply
    function windMaxFor(p) { return Math.max(0, Math.min(120, (maxPlay - p) / windAvg)) }
    readonly property real maxWind: uiFull ? 0 : windMaxFor(uiPlay)
    // one `theme.py video thumbs` line: "<video>\t<jpg>\t<usable whole seconds>\t<wind curve mean speed>"
    function ingestMeta(line) {
        const f = line.split("\t")
        if (f.length < 2) return
        if (f[1] !== "") { const m = Object.assign({}, thumbs); m[f[0]] = f[1]; thumbs = m }
        if (Number(f[2]) > 0) { const u = Object.assign({}, usable); u[f[0]] = Number(f[2]); usable = u }
        if (Number(f[3]) > 0) windAvg = Number(f[3])
        if (f.length > 4 && f[4] !== "" && isFinite(Number(f[4]))) easeDefault = Number(f[4])
        if (f.length > 6 && f[5] !== "" && isFinite(Number(f[5])) && f[6] !== "" && isFinite(Number(f[6]))) {
            playDefault = Number(f[5]); windDefault = Number(f[6])
        }
    }
    // the playing clip may not be in the scanned folders (picked elsewhere): ask for its usable length directly
    // how the replay works on the edited monitor (theme.py `video loopinfo`: seconds per switch, steps per loop / back to the start with a fade, from the cached analyses; the step count follows that monitor's bake cost): read-only line
    property string loopText: ""
    function refreshLoop() {
        if (shownVideo === "" || shownMode !== "once") { loopText = ""; return }
        loopProc.command = ["python3", "-I", Theme.themeDir + "/theme.py", "video", "loopinfo", shownVideo, stateFull ? "full" : String(statePlay), String(stateWind), String(uiEaseSet ? uiEase : stateEase), target]
        loopProc.running = true
    }
    Timer { id: loopTimer; interval: 500; onTriggered: page.refreshLoop() }
    // can this machine decode the shown video in hardware? (theme.py `video hwdec`): with Optimize off a "no" plays in software
    property bool softwareDecode: false
    function refreshHwdec() {
        if (shownVideo === "") { softwareDecode = false; return }
        hwProc.command = ["python3", "-I", Theme.themeDir + "/theme.py", "video", "hwdec", shownVideo]
        hwProc.running = true
    }
    Process {
        id: hwProc
        stdout: SplitParser { onRead: line => { page.softwareDecode = line.indexOf("no ") === 0 } }
    }
    Process {
        id: loopProc
        stdout: SplitParser {
            onRead: line => { page.loopText = line }   // theme.py's own wording: "each switch advances ~1.8 s (12 steps per loop)" ...
        }
    }
    function loadUsable() {
        if (shownVideo === "" || usable[shownVideo]) return
        metaProc.command = ["python3", "-I", Theme.themeDir + "/theme.py", "video", "thumb", shownVideo]
        metaProc.running = true
    }
    Process {
        id: metaProc
        stdout: SplitParser { onRead: line => page.ingestMeta(line) }
    }
    function syncTiming() {
        if (timingDirty) return
        if (shownVideo !== "") { uiPlay = statePlay; uiWind = stateWind; uiFull = stateFull; uiEase = stateEase; uiEaseSet = stateEaseSet }
        else if (memory && memory.play !== undefined) {
            uiPlay = memory.play; uiWind = memory.wind; uiFull = memory.full === true
            if (memory.ease !== undefined) { uiEase = memory.ease; uiEaseSet = memory.easeSet === true }
        }
    }
    onStatePlayChanged: { syncTiming(); loopTimer.restart() }
    onStateWindChanged: { syncTiming(); loopTimer.restart() }
    onStateFullChanged: { syncTiming(); loopTimer.restart() }
    onStateEaseChanged: syncTiming()
    onStateEaseSetChanged: syncTiming()
    function fmtEase(v) { return v <= 0 ? "Off" : v.toFixed(1) + " s" }
    function setEase(v) {   // 0.1 s steps, never longer than the clip
        uiEase = Math.round(Math.max(0, Math.min(easeMax, maxPlay, v)) * 10) / 10
        uiEaseSet = true
        timingDirty = true
        if (memory) { memory.ease = uiEase; memory.easeSet = true }
        if (shownVideo !== "" && shownMode === "once" && !sliderHeld) retimeTimer.restart()
    }
    function fmtSec(s) { return (Math.round(s * 2) / 2) + " s" }
    function setTiming(p, w, full) {
        uiFull = full
        uiPlay = full ? maxPlay : Math.round(Math.max(0, Math.min(maxPlay, p)))
        uiWind = full ? 0 : Math.round(Math.max(0, Math.min(windMaxFor(uiPlay), w)) * 2) / 2   // clamped visibly when Play grew
        timingDirty = true
        if (memory) { memory.play = uiPlay; memory.wind = uiWind; memory.full = uiFull }
        // restarts the clip and the bake: while a slider is held nothing is applied, the release applies at once;
        // other changes (keys, wheel) settle for a moment
        if (shownVideo !== "" && shownMode === "once" && !sliderHeld) retimeTimer.restart()
    }
    readonly property bool sliderHeld: playSlider.down || windSlider.down || easeSlider.down
    function flushTiming() {   // slider released: apply now (theme.py cancels a stale bake and starts the new one)
        if (!retimeTimer.running && !timingDirty) return
        retimeTimer.stop()
        retimeTimer.triggered()
    }
    Timer {
        id: retimeTimer
        interval: 250
        onTriggered: {
            page.timingDirty = false
            if (page.shownVideo === "" || page.shownMode !== "once") return
            if (page.uiFull === page.stateFull && (page.uiFull || (page.uiPlay === page.statePlay && page.uiWind === page.stateWind))
                && (!page.uiEaseSet || page.uiEase === page.stateEase)) return
            page.busyState = true
            busyTimer.restart()
            page.timingDirty = true   // keep the dragged value until the state file shows it
            retimeDone.restart()
            Quickshell.execDetached(page.applyCmd(page.shownVideo, "once"))
        }
    }
    Timer { id: retimeDone; interval: 4000; onTriggered: { page.timingDirty = false; page.syncTiming() } }
    readonly property string playMode: shownVideo !== "" ? shownMode : newMode   // what the Playback row shows
    readonly property bool switchingMode: applying !== "" && applying === shownVideo && applyingMode !== shownMode

    // ---- tabs: "images" | "videos". Default = what the edited monitor shows; a hand-picked tab wins for the session ----
    property var chosen: ({})                  // monitor key -> tab picked by hand
    readonly property string tab: chosen[target] !== undefined ? chosen[target] : (shownVideo !== "" ? "videos" : "images")
    readonly property var list: tab === "videos" ? videos : images
    function setTab(t) {
        if (t !== "images" && t !== "videos") return
        const c = Object.assign({}, chosen)
        c[target] = t
        chosen = c
        if (memory) memory.tabs = c
    }
    function pick(key) { const s = screenOf(key); if (s) Monitors.select(s) }
    onMemoryChanged: if (memory) {
        if (memory.tabs) chosen = memory.tabs
        if (memory.mode) newMode = memory.mode
        syncTiming()
    }
    onTabChanged: sel = -1
    onTargetChanged: { sel = -1; timingDirty = false; syncTiming(); loopTimer.restart() }

    function checkApplied() {
        if (applying === "") return
        if (applyingMode === "" ? (shownVideo === "" && shown === applying) : (shownVideo === applying && shownMode === applyingMode)) applying = ""
    }
    onShownChanged: checkApplied()
    onShownVideoChanged: { checkApplied(); timingDirty = false; loadUsable(); syncTiming(); loopTimer.restart(); refreshHwdec() }
    onShownModeChanged: checkApplied()

    FileView {
        id: stateView
        path: page.stateFile
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let d = {}
            try { d = JSON.parse(text()) } catch (e) { d = {} }
            page.wpMonitors = d && typeof d.monitors === "object" && d.monitors ? d.monitors : {}
            page.wpPrimary = d && typeof d.primary === "string" ? d.primary : ""
            page.wpLinks = d && Array.isArray(d.links) ? d.links : []
            page.wpPrimaryVideo = d && d.primary_video && typeof d.primary_video === "object" ? d.primary_video : null
            page.optimize = !(d && d.optimize === false)
            page.optSpeed = d && (d.optimize_speed === "fast" || d.optimize_speed === "balanced") ? d.optimize_speed : "background"
        }
        onLoadFailed: { page.wpMonitors = {}; page.wpPrimary = ""; page.wpPrimaryVideo = null; page.wpLinks = [] }
    }
    // the file may not exist yet (watching a missing file sees no creation): poll while theme.py works
    Timer { interval: 300; repeat: true; running: page.applying !== "" || page.busyState || page.working; onTriggered: { stateView.reload(); workView.reload() } }
    // theme.py's background worker (palette, still, reloads): {gen, state: working|done|failed, pid}; a dead pid = not working
    property var work: ({})
    property bool workDead: false
    readonly property bool working: work.state === "working" && !workDead
    onWorkChanged: { workDead = false; if (work.state === "failed") applying = "" }   // failed: the old palette stays, the state shows what is on
    FileView {
        id: workView
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/theme-apply/status.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { page.work = JSON.parse(text()) } catch (e) { page.work = ({}) } }
        onLoadFailed: page.work = ({})
    }
    // the file appears with the first apply of this login (a watch on a missing file sees no creation): poll while shown
    Timer { interval: 1000; repeat: true; running: page.visible && !page.working; onTriggered: workView.reload() }
    Timer { interval: 2000; repeat: true; running: page.working && page.work.pid > 0
        onTriggered: { workPid.command = ["test", "-d", "/proc/" + page.work.pid]; workPid.running = true } }
    Process { id: workPid; onExited: code => { if (code !== 0) page.workDead = true } }
    property bool busyState: false
    Timer { id: busyTimer; interval: 3000; onTriggered: page.busyState = false }

    readonly property int gap: 12
    readonly property int cols: Math.max(2, Math.floor((width + gap) / 300))
    readonly property real cellW: Math.floor((width - (cols - 1) * gap) / cols)
    readonly property real cellH: Math.round(cellW * 9 / 16)

    // detached: closing Settings mid-apply must not kill theme.py
    function apply(path, mode) {
        if (!path || unreadable(path)) return
        const vid = isVideo(path)
        const m = vid ? (mode || playMode) : ""
        if (applying !== "" ? (path === applying && m === applyingMode)   // the latest click wins; the same again is a no-op
            : vid ? (path === shownVideo && m === shownMode) : (shownVideo === "" && path === shown)) return   // already there
        applying = path
        applyingMode = m
        applyTimeout.restart()
        Quickshell.execDetached(applyCmd(path, m))
    }
    function applyCmd(path, m) {
        const cmd = ["python3", "-I", Theme.themeDir + "/theme.py", "apply", path]
        if (isVideo(path)) {
            cmd.push("--mode", m)
            if (m === "once") cmd.push("--play", uiFull ? "full" : String(uiPlay), "--wind", String(uiFull ? 0 : uiWind))
            if (m === "once" && uiEaseSet) cmd.push("--ease", String(uiEase))
        }
        if (linkedGroup) group.forEach(k => cmd.push("--monitor", k))   // linked: the whole group in one call (the primary among them = full re-theme)
        else if (!targetIsPrimary) cmd.push("--monitor", target)   // not the theme source: hyprpaper / player only
        return cmd
    }
    // Playback row: the mode of the next video clicked; a video already playing on the monitor is re-applied in it
    function setMode(m) {
        newMode = m
        if (memory) memory.mode = m
        if (shownVideo !== "" && m !== shownMode) apply(shownVideo, m)
    }
    // "primary <key>" (theme source moves, full apply if that monitor's image differs) / "clear <key>" (follow the primary)
    function monitorCmd(sub, key) {
        busyState = true
        busyTimer.restart()
        // "Follow primary" goes for the whole linked group (the primary itself has nothing to follow)
        const keys = sub === "clear" ? group.filter(k => k !== primaryKey) : [key]
        Quickshell.execDetached(["python3", "-I", Theme.themeDir + "/theme.py", sub].concat(keys))
    }
    Timer { id: applyTimeout; interval: 30000; onTriggered: page.applying = "" }   // apply failed / same image

    function reveal(i) {
        if (!flick || i < 0) return
        const top = grid.y + Math.floor(i / cols) * (cellH + gap)
        const bottom = top + cellH
        const maxY = Math.max(0, flick.contentHeight - flick.height)
        if (top < flick.contentY) flick.contentY = Math.max(0, top - 8)
        else if (bottom > flick.contentY + flick.height) flick.contentY = Math.min(maxY, bottom - flick.height + 8)
    }

    Keys.onPressed: e => {
        if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
            setTab(tab === "videos" ? "images" : "videos")
            e.accepted = true
            return
        }
        const n = list.length
        if (n === 0) { e.accepted = false; return }
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
            if (sel >= 0) apply(list[sel])
            e.accepted = true
            return
        }
        let i = sel >= 0 ? sel : Math.max(0, list.indexOf(tab === "videos" ? shownVideo : shown))
        if (sel < 0 && [Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down].includes(e.key)) {
            // first arrow press just shows the cursor on the current wallpaper
        } else if (e.key === Qt.Key_Left) i -= 1
        else if (e.key === Qt.Key_Right) i += 1
        else if (e.key === Qt.Key_Up) i -= cols
        else if (e.key === Qt.Key_Down) i += cols
        else if (e.key === Qt.Key_Home) i = 0
        else if (e.key === Qt.Key_End) i = n - 1
        else { e.accepted = false; return }   // Escape etc. go up to Settings
        sel = Math.max(0, Math.min(n - 1, i))
        reveal(sel)
        e.accepted = true
    }

    IpcHandler {
        target: "wallpaperpage"
        function tab(name: string): void { page.setTab(name) }
        function monitor(key: string): void { page.pick(key) }
    }

    Process {
        id: scan
        // images from wallpaper_dirs, then videos from video_dirs (missing folders are fine)
        // folders are positional args ($1 = number of image folders), never spliced into the script
        command: ["sh", "-c",
            "n=$1; shift\n"
            + "{ i=0; for d; do i=$((i+1)); [ $i -le $n ] && find -L \"$d\" -maxdepth 2 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\); done | sort\n"
            + "  i=0; for d; do i=$((i+1)); [ $i -gt $n ] && find -L \"$d\" -maxdepth 2 -type f \\( -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' \\); done | sort; } 2>/dev/null",
            "sh", String(page.dirs.length)].concat(page.dirs, page.videoDirs)
        stdout: StdioCollector {
            onStreamFinished: {
                page.files = text.split("\n").filter(l => l.length > 0)
                page.scanned = true
                page.thumbsDone = false
                Quickshell.execDetached(["python3", "-I", Theme.themeDir + "/theme.py", "analyze"])   // palette cache of new files (lowest priority)
                const vids = page.files.filter(f => page.isVideo(f))
                if (vids.length > 0) { thumbProc.command = ["python3", "-I", Theme.themeDir + "/theme.py", "video", "thumbs"].concat(vids); thumbProc.running = true }
                else page.thumbsDone = true
            }
        }
    }
    // video stills for the grid: theme.py prints "<video>\t<jpg>" per file as each is made (cached, ffmpeg off the UI thread)
    Process {
        id: thumbProc
        onExited: page.thumbsDone = true
        stdout: SplitParser {
            onRead: line => {
                page.ingestMeta(line)
            }
        }
    }
    Component.onCompleted: scan.running = true   // rescanned every time Settings opens on this page

    // ---- title row: theme source + current palette (stays visible while the grid scrolls) ----
    // one line, centered on the row: [theme source file name, or "name  #hex" of the hovered swatch] [swatches]
    readonly property Component headerItem: paletteHeader
    Component {
        id: paletteHeader
        Item {
            id: pal
            property string hovered: ""        // "name  #rrggbb" of the swatch under the mouse
            readonly property var swatches: [
                { n: "bg", c: Theme.bg }, { n: "surface2", c: Theme.surface2 }, { n: "muted", c: Theme.muted },
                { n: "fg", c: Theme.fg }, { n: "accent", c: Theme.accent }, { n: "red", c: Theme.red },
                { n: "green", c: Theme.green }, { n: "yellow", c: Theme.yellow }, { n: "blue", c: Theme.blue },
                { n: "magenta", c: Theme.magenta }, { n: "cyan", c: Theme.cyan }
            ]
            readonly property int gap: 3
            readonly property int captionMin: 110    // room kept for the caption before swatches shrink
            readonly property int sw: Math.max(14, Math.min(28, Math.floor((width - captionMin - 12 - (swatches.length - 1) * gap) / swatches.length)))
            implicitHeight: 30

            Label {
                id: caption
                anchors { left: parent.left; right: swatchRow.left; rightMargin: page.working ? 12 + workIcon.width + 6 : 12; verticalCenter: parent.verticalCenter }
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideMiddle
                font.pixelSize: Theme.fontCaption
                color: pal.hovered !== "" ? Theme.fg : Theme.muted
                // a primary video's still is a cache file: name the video instead
                text: pal.hovered !== "" ? pal.hovered
                    : page.wpPrimaryVideo ? page.baseName(page.wpPrimaryVideo.video)
                    : page.stillVideo(page.currentPath) ? page.baseName(page.stillVideo(page.currentPath).video) : page.baseName(page.currentPath)
            }
            Icon {   // the background worker (palette, still, app reloads) is running
                id: workIcon
                anchors { right: swatchRow.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                visible: page.working
                text: Icons.palette
                font.pixelSize: Theme.iconMd
                color: Theme.accent
                SequentialAnimation on opacity {
                    running: workIcon.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: Theme.busyPulseMs; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: Theme.busyPulseMs; easing.type: Easing.InOutSine }
                    onRunningChanged: if (!running) workIcon.opacity = 1
                }
            }
            Row {
                id: swatchRow
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: pal.gap
                Repeater {
                    model: pal.swatches
                    Rectangle {
                        id: swatch
                        required property var modelData
                        width: pal.sw; height: 20; radius: Math.min(4, Theme.radiusPage)   // small squares, barely rounded
                        color: modelData.c
                        border.width: 1; border.color: Theme.alpha(Theme.fg, swatchArea.containsMouse ? 0.8 : 0.25)
                        MouseArea {
                            id: swatchArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onContainsMouseChanged: pal.hovered = containsMouse ? swatch.modelData.n + "  " + String(swatch.modelData.c)
                                : pal.hovered.startsWith(swatch.modelData.n + "  ") ? "" : pal.hovered
                        }
                    }
                }
            }
        }
    }


    // ---- monitors (only with 2+ screens): which one is edited, links, palette source; actions at the row's end ----
    MonitorSection {
        objectName: "wallpaper-monitors"
        screens: page.monitors
        current: page.screenOf(page.target) ? page.screenOf(page.target).name : ""
        linkable: true
        linkedAt: i => page.linkedKeys(page.keyAt(i), page.keyAt(i + 1))
        linkTip: i => (page.linkedKeys(page.keyAt(i), page.keyAt(i + 1)) ? "Unlink " : "Link ") + page.titleOf(page.monitors[i]) + " and " + page.titleOf(page.monitors[i + 1])
        onLinkToggled: i => page.toggleLink(i)
        groupedFor: s => page.group.indexOf(Appearance.monitorKey(s)) >= 0
        thumbFor: s => page.shownFor(Appearance.monitorKey(s))
        markFor: s => Appearance.monitorKey(s) === page.primaryKey ? Icons.palette : ""
        markTipFor: s => Appearance.monitorKey(s) === page.primaryKey ? "Palette source" : ""
        Icon {
            visible: page.busyState
            text: Icons.spinner
            font.pixelSize: Theme.iconMd
            color: Theme.muted
            RotationAnimator on rotation { running: page.busyState; from: 0; to: 360; duration: 1000; loops: Animation.Infinite }
        }
        MonitorAction {
            objectName: "btn-wp-follow"
            visible: !page.targetIsPrimary && page.group.some(k => page.ownFor(k))
            glyph: Icons.undo
            tip: "Follow primary"
            onClicked: page.monitorCmd("clear", page.target)
        }
        MonitorAction {
            objectName: "btn-wp-palette"
            visible: !page.targetIsPrimary
            glyph: Icons.palette
            tip: "Use for palette"
            onClicked: page.monitorCmd("primary", page.target)
        }
    }

    // ---- library: Images / Videos tabs over one grid ----
    SectionHead {
        Layout.topMargin: page.multi ? 6 : 0
        title: "Wallpaper"
        detail: page.scanned ? "" : "scanning…"
        InfoTip { text: "Arrows + Enter apply; Tab switches tabs." }
        Segmented {
            values: ["images", "videos"]
            labels: ["Images  " + page.images.length, "Videos  " + page.videos.length]
            objectNames: ["tab-images", "tab-videos"]
            current: page.tab
            outerRadius: Theme.radiusPage; inset: 9
            segHeight: 26
            segWidth: 96
            onPicked: v => page.setTab(v)
        }
    }

    // Videos tab: RIFE (optional bundle) missing -> install hint
    MissingPackage {
        visible: page.tab === "videos" && OptionalPackages.isMissing("video-wallpaper")
        bundle: "video-wallpaper"
        padX: 12
        btnRadius: Theme.radiusPage
        radius: Theme.radiusPage
    }

    // Videos tab: how videos play on this monitor (the playing one and the next one clicked)
    Rectangle {
        visible: page.tab === "videos" && page.videos.length > 0
        Layout.fillWidth: true
        implicitHeight: boxCol.implicitHeight + 20
        radius: Theme.radiusPage
        color: Theme.alpha(Theme.fg, 0.04)
        border.width: 1
        border.color: Theme.alpha(Theme.overlay, 0.45)
        ColumnLayout {
            id: boxCol
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 10 }
            spacing: 10
        RowLayout {
            id: playRow
            Layout.fillWidth: true
            spacing: 10
            Icon {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 1
                text: page.playMode === "loop" ? Icons.repeat : Icons.play
                font.pixelSize: Theme.iconMd
                color: page.shownVideo !== "" ? Theme.accent : Theme.fgDim    // accent = a video is playing on this monitor
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Label {
                        Layout.fillWidth: false
                        elide: Text.ElideRight
                        font.pixelSize: Theme.fontSmall
                        text: "Playback"
                    }
                    InfoTip {
                        readonly property string name: page.baseName(page.shownVideo)
                        text: page.shownVideo !== "" && !page.targetIsPrimary && !page.ownFor(page.target)
                            ? "Plays the primary's video, " + name + " (" + page.playMode + "). Switching gives this monitor its own copy."
                            : page.shownVideo !== ""
                            ? name + (page.playMode === "loop" ? " loops." : " plays once and holds its last frame.") + " Switching restarts it" + (page.targetIsPrimary ? " and re-themes" : "") + "."
                            : "Videos you click " + (page.playMode === "loop" ? "loop." : "play once, then hold their last frame.")
                    }
                    Item { Layout.fillWidth: true }
                }
                Label {
                    visible: page.switchingMode
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontCaption
                    color: Theme.muted
                    readonly property string name: page.baseName(page.shownVideo)
                    text: "Restarting " + name + "…"
                }
            }
            Segmented {
                values: ["once", "loop"]
                labels: ["Play once", "Loop"]
                objectNames: ["mode-once", "mode-loop"]
                current: page.switchingMode ? page.applyingMode : page.playMode
                outerRadius: Theme.radiusPage; inset: 10
                segHeight: 26
                segWidth: 84
                onPicked: v => page.setMode(v)
            }
        }
        AdvancedFold {
            objectName: "fold-video"
            label: "Customise playback…"
            detail: page.optimize && page.optJob.state === "encoding" ? "encoding " + page.optJob.pct + " %" : ""
            SettingRow {
                title: "Optimize"
                titleWidth: 84
                Toggle {
                    objectName: "toggle-optimize"
                    checked: page.optimize
                    busy: page.optBusy || (page.optimize && page.optJob.state === "encoding")
                    onToggled: on => page.setOptimize(on)
                }
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontCaption
                    color: page.optimize && page.optJob.state === "encoding" ? Theme.accent : Theme.muted
                    text: page.optimize && page.optJob.state === "encoding" ? "encoding " + page.optJob.pct + " %" : ""
                }
                InfoTip {
                    icon: !page.optimize && page.softwareDecode && page.shownVideo !== "" ? Icons.warning : Icons.info
                    color: icon === Icons.warning ? Theme.yellow : Theme.muted
                    text: !page.optimize ? (page.softwareDecode && page.shownVideo !== "" ? "Off: no hardware decoding for this video, so it plays in software (high CPU)."
                                                                                           : "Off: videos play from the original file.")
                        : page.optJob.state === "encoding" ? "Encoding " + page.optJob.label
                        : "One copy per monitor at its resolution and frame rate: less GPU."
                }
            }
            SettingRow {
                visible: page.optimize
                title: "Speed"
                titleWidth: 84
                Segmented {
                    values: ["background", "balanced", "fast"]
                    labels: ["Background", "Balanced", "Fast"]
                    objectNames: ["optspeed-background", "optspeed-balanced", "optspeed-fast"]
                    current: page.optSpeed
                    outerRadius: Theme.radiusPage; inset: 10
                    segHeight: 26
                    segWidth: 96
                    onPicked: v => page.setOptSpeed(v)
                }
                InfoTip {
                    text: page.optSpeed === "fast" ? "All cores, normal priority: done soonest, the desktop may stutter."
                        : page.optSpeed === "balanced" ? "About 60 % of the machine at low priority."
                        : "Idle CPU time only: the desktop stays smooth."
                }
                Item { Layout.fillWidth: true }
            }
            // play-once timing: full speed for N s, then ease to a stop over M s and hold that frame (mpv/winddown.lua)
            SettingRow {
                visible: page.playMode === "once"
                title: "Play for"
                titleWidth: 84
                Slider {
                    wheel: false
                    id: playSlider
                    objectName: "slider-play"
                    onDownChanged: if (!down) page.flushTiming()
                    Layout.fillWidth: true
                    value: page.uiFull ? 1 : page.uiPlay / page.maxPlay
                    notches: [page.playDefault / page.maxPlay, 1]      // the default, full length
                    onMoved: v => { const p = Math.round(v * page.maxPlay); page.setTiming(p, page.uiWind, p >= page.maxPlay) }
                }
                Label {
                    text: page.uiFull ? "Full length" : page.fmtSec(page.uiPlay)
                    Layout.preferredWidth: 118; horizontalAlignment: Text.AlignRight
                    color: page.uiFull ? Theme.fgDim : Theme.fg; font.pixelSize: Theme.fontSmall
                }
                InfoTip { text: page.loopText }
            }
            SettingRow {
                visible: page.playMode === "once"
                title: "Wind down"
                titleWidth: 84
                Slider {
                    wheel: false
                    id: windSlider
                    objectName: "slider-wind"
                    onDownChanged: if (!down) page.flushTiming()
                    Layout.fillWidth: true
                    dim: page.uiFull
                    value: page.maxWind > 0 ? page.uiWind / page.maxWind : 0
                    notches: page.maxWind > 0 ? [page.windDefault / page.maxWind] : []
                    onMoved: v => { if (!page.uiFull) page.setTiming(page.uiPlay, v * page.maxWind, false) }
                }
                Label {
                    text: page.uiFull ? "lower Play for" : (page.uiWind > 0 ? page.fmtSec(page.uiWind) : "none") + " / max " + page.fmtSec(page.maxWind)
                    Layout.preferredWidth: 118; horizontalAlignment: Text.AlignRight
                    color: !page.uiFull && page.uiWind > 0 ? Theme.fg : Theme.fgDim; font.pixelSize: Theme.fontSmall
                }
            }
            SettingRow {
                visible: page.playMode === "once"
                title: "Ease-in"
                titleWidth: 84
                Slider {
                    wheel: false
                    id: easeSlider
                    objectName: "slider-ease"
                    onDownChanged: if (!down) page.flushTiming()
                    Layout.fillWidth: true
                    value: page.uiEase / page.easeMax
                    notches: [page.easeDefault / page.easeMax]
                    onMoved: v => page.setEase(v * page.easeMax)
                }
                Label {
                    text: page.fmtEase(page.uiEase)
                    Layout.preferredWidth: 118; horizontalAlignment: Text.AlignRight
                    color: page.uiEase > 0 ? Theme.fg : Theme.fgDim; font.pixelSize: Theme.fontSmall
                }
            }
        }
        }
    }

    // nothing in the library folders
    EmptyState {
        big: true
        visible: page.scanned && page.list.length === 0
        icon: page.tab === "videos" ? Icons.video : Icons.image
        text: page.tab === "videos" ? "No videos" : "No images"
        hint: (page.tab === "videos" ? page.videoDirs : page.dirs).join("\n")
    }

    Grid {
        id: grid
        Layout.fillWidth: true
        columns: page.cols
        spacing: page.gap

        Repeater {
            model: page.list
            WallpaperTile {
                required property string modelData
                required property int index
                readonly property bool video: page.isVideo(modelData)
                width: page.cellW
                height: page.cellH
                name: page.baseName(modelData)
                source: video ? (page.thumbs[modelData] || "") : modelData
                current: page.applying !== "" ? modelData === page.applying   // the click shows at once
                    : video ? modelData === page.shownVideo : (page.shownVideo === "" && modelData === page.shown)
                cursor: index === page.sel
                unreadable: page.unreadable(modelData)
                badge: video && current ? (page.shownMode === "loop" ? "LOOP" : "ONCE") : ""
                onClicked: { page.sel = index; page.apply(modelData) }
            }
        }
    }
}
