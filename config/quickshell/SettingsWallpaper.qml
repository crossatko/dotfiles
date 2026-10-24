pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Settings -> Wallpaper & theme. Top to bottom:
//  - title row (`headerItem`): the theme source's file name + the current palette swatches (stays put while scrolling);
//  - with 2+ monitors: "Monitors" cards (WallpaperMonitorCard) pick the monitor being edited, and a box under them
//    says what that means: the primary monitor's wallpaper sets the colour theme, any other one only gets its own
//    wallpaper ("Follow primary" = `theme.py clear`, "Make primary" = `theme.py primary`);
//  - "Wallpaper for <monitor>" with two tabs, Images (wallpaper_dirs) and Videos (video_dirs), and the thumbnail
//    grid (WallpaperTile) of that library. The Videos tab adds the Playback row (Play once / Loop): the mode of the
//    video the monitor plays (switching re-applies it) and of the next video clicked.
// A click (or arrows + Enter) runs `theme.py apply <file> [--mode once|loop] [--monitor <key>]` detached; for the
// primary that is the full re-theme, for another monitor hyprpaper / the video player only. theme.py owns the state
// (wallpapers.json, AGENTS.md "Per-monitor wallpapers" / "Video wallpapers"); this page only reads it.
// Tabs: Tab / Shift+Tab. The page opens on the tab matching what the edited monitor shows; a tab picked by hand and
// the edited monitor are kept for the session (Settings' `memory` page hook).
// Monitor links: a MonitorLinkButton between neighbouring cards (MonitorCardRow) links them; a linked group always gets the
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
    property string applying: ""               // path handed to theme.py, cleared once the monitor shows it
    property string applyingMode: ""           // video mode handed to theme.py ("" for an image)
    property string newMode: "once"            // mode for a video clicked while the monitor plays none
    property var thumbs: ({})                  // video path -> cached still (jpg), filled in async
    property bool thumbsDone: false            // thumbnailing finished: a video without one is unreadable (skipped)
    function unreadable(p) { return isVideo(p) && thumbsDone && !thumbs[p] }
    function isVideo(p) { return /\.(mp4|webm|mkv)$/i.test(p) }
    function baseName(p) { return String(p).split("/").pop() }
    function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
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
    // connected screens with a usable key (same key as Appearance / managed.lua use)
    readonly property var monitors: Quickshell.screens.filter(s => Appearance.monitorKey(s) !== "")
    // stored primary if it is connected, else the screen at 0,0 (theme.py's rule), else the first one
    readonly property string primaryKey: {
        const ms = monitors
        if (ms.length === 0) return ""
        if (wpPrimary !== "" && ms.some(s => Appearance.monitorKey(s) === wpPrimary)) return wpPrimary
        return Appearance.monitorKey(ms.find(s => s.x === 0 && s.y === 0) || ms[0])
    }
    property string pickedKey: ""              // monitor card chosen by the user, "" = the primary
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
    readonly property string groupTitle: group.map(k => titleOf(screenOf(k))).join(" + ")
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
    readonly property string targetTitle: titleOf(screenOf(target))
    readonly property string primaryTitle: titleOf(screenOf(primaryKey))
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
    function timedFor(key) {      // the entry carries a play time (no `play` = full length)
        const e = entryFor(key)
        return !!e && typeof e === "object" && e.play !== undefined && isFinite(Number(e.play))
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
    readonly property real statePlay: numFor(target, "play")
    readonly property real stateWind: numFor(target, "wind")
    readonly property bool stateFull: !timedFor(target)
    property real uiPlay: 0
    property real uiWind: 0
    property bool uiFull: true               // Play for at its maximum = the whole usable length, no wind down (the default)
    property bool timingDirty: false
    // Play for and Wind down share the clip: play + wind * windAvg <= D. D = whole usable seconds of the playing video
    // (theme.py `video thumbs`, cached), windAvg = the curve's mean speed (theme.py WIND_AVG; the wind consumes wind * windAvg s).
    property var usable: ({})                // video path -> whole usable seconds, filled in async with the thumbs
    property real windAvg: 0.5
    // Replay ease-in: seconds every workspace-switch burst takes to speed up from rest (0 = none; a burst is ease-in + wind-down,
    // at least 1 s). Stored in the entry as `ease` once the slider was touched; until then the theme.toml `replay_ease_in` default.
    readonly property real easeMax: 1
    property real easeDefault: 0.4
    readonly property bool stateEaseSet: easeFor(target) >= 0
    readonly property real stateEase: stateEaseSet ? easeFor(target) : easeDefault
    property real uiEase: 0.4
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
            uiPlay = memory.play; uiWind = memory.wind; uiFull = memory.full !== false
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
    function pick(key) {
        pickedKey = key
        if (memory) memory.target = key
    }
    onMemoryChanged: if (memory) {
        if (memory.tabs) chosen = memory.tabs
        if (memory.target) pickedKey = memory.target
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
    Timer { interval: 300; repeat: true; running: page.applying !== "" || page.busyState; onTriggered: stateView.reload() }
    property bool busyState: false
    Timer { id: busyTimer; interval: 3000; onTriggered: page.busyState = false }

    readonly property int gap: 12
    readonly property int cols: Math.max(2, Math.floor((width + gap) / 300))
    readonly property real cellW: Math.floor((width - (cols - 1) * gap) / cols)
    readonly property real cellH: Math.round(cellW * 9 / 16)

    // detached: closing Settings mid-apply must not kill theme.py
    function apply(path, mode) {
        if (!path || applying !== "" || unreadable(path)) return
        const vid = isVideo(path)
        const m = vid ? (mode || playMode) : ""
        if (vid ? (path === shownVideo && m === shownMode) : (shownVideo === "" && path === shown)) return   // already there
        applying = path
        applyingMode = m
        applyTimeout.restart()
        Quickshell.execDetached(applyCmd(path, m))
    }
    function applyCmd(path, m) {
        const cmd = ["python3", "-I", Theme.themeDir + "/theme.py", "apply", path]
        if (isVideo(path)) {
            cmd.push("--mode", m)
            if (m === "once" && !uiFull) cmd.push("--play", String(uiPlay), "--wind", String(uiWind))
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
                anchors { left: parent.left; right: swatchRow.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideMiddle
                font.pixelSize: Theme.fontCaption
                color: pal.hovered !== "" ? Theme.fg : Theme.muted
                // a primary video's still is a cache file: name the video instead
                text: pal.hovered !== "" ? pal.hovered
                    : page.wpPrimaryVideo ? page.baseName(page.wpPrimaryVideo.video)
                    : page.stillVideo(page.currentPath) ? page.baseName(page.stillVideo(page.currentPath).video) : page.baseName(page.currentPath)
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

    // ---- monitors (only with 2+ screens: one screen needs no target) ----
    SectionHead {
        visible: page.multi
        title: "Monitors"
        detail: "pick the one to edit"
    }
    MonitorCardRow {
        id: monRow
        visible: page.multi
        Layout.fillWidth: true
        count: page.monitors.length
        minCardW: 200                                    // 3 across at the 920 px minimum
        cardH: 62
        linkedAt: i => page.linkedKeys(page.keyAt(i), page.keyAt(i + 1))
        linkTip: i => (page.linkedKeys(page.keyAt(i), page.keyAt(i + 1)) ? "Unlink " : "Link ") + page.titleOf(page.monitors[i]) + " and " + page.titleOf(page.monitors[i + 1])
        onLinkToggled: i => page.toggleLink(i)
        Repeater {
            model: page.monitors
            WallpaperMonitorCard {
                required property var modelData
                required property int index
                readonly property string key: Appearance.monitorKey(modelData)
                x: monRow.xOf(index); y: monRow.yOf(index)
                width: monRow.cardW
                notches: monRow.notchesOf(index)
                title: page.titleOf(modelData)
                connector: modelData.name
                detail: page.detailFor(key)
                thumb: page.shownFor(key)
                video: page.videoFor(key) !== ""
                picked: key === page.target
                grouped: key !== page.target && page.group.indexOf(key) >= 0
                primary: key === page.primaryKey
                onClicked: page.pick(key)
            }
        }
    }
    // what editing this monitor means, and the monitor-level actions
    Rectangle {
        visible: page.multi
        Layout.fillWidth: true
        implicitHeight: Math.max(roleRow.implicitHeight, 30) + 20
        radius: Theme.radiusPage
        color: Theme.alpha(Theme.fg, 0.04)
        border.width: 1
        border.color: Theme.alpha(Theme.overlay, 0.45)
        RowLayout {
            id: roleRow
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 10 }
            spacing: 10
            Icon {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 1
                text: page.targetIsPrimary ? "" : ""
                font.pixelSize: 13
                color: page.targetIsPrimary ? Theme.accent : Theme.fgDim
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                textFormat: Text.StyledText
                font.pixelSize: Theme.fontSmall
                color: Theme.fgDim
                text: page.busyState ? "Updating monitors…" : (page.targetIsPrimary
                    ? "<b>" + page.esc(page.targetTitle) + "</b> is the primary monitor: its wallpaper also sets the colour theme of every app. Monitors without their own wallpaper show it too."
                    : page.ownFor(page.target)
                    ? "<b>" + page.esc(page.targetTitle) + "</b> has its own wallpaper. Only the primary, <b>" + page.esc(page.primaryTitle) + "</b>, sets the colour theme."
                    : "<b>" + page.esc(page.targetTitle) + "</b> shows the primary's wallpaper. Pick one below to give it its own; the colour theme stays with <b>" + page.esc(page.primaryTitle) + "</b>."
                    ) + (page.linkedGroup ? " Linked with <b>" + page.esc(page.group.slice(1).map(k => page.titleOf(page.screenOf(k))).join(" + ")) + "</b>: whatever you pick here is applied to all of them." : "")
            }
            Btn {
                visible: !page.targetIsPrimary && page.group.some(k => page.ownFor(k))
                text: "Follow primary"
                outerRadius: Theme.radiusPage; inset: 9
                onClicked: page.monitorCmd("clear", page.target)
            }
            Btn {
                visible: !page.targetIsPrimary
                text: "Make primary"
                outerRadius: Theme.radiusPage; inset: 9
                onClicked: page.monitorCmd("primary", page.target)
            }
        }
    }

    // ---- library: Images / Videos tabs over one grid ----
    SectionHead {
        Layout.topMargin: page.multi ? 6 : 0
        title: page.multi ? "Wallpaper for " + page.groupTitle : "Wallpaper"
        detail: page.scanned ? "" : "scanning…"
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
                text: page.playMode === "loop" ? "\uf363" : "\uf04b"
                font.pixelSize: 13
                color: page.shownVideo !== "" ? Theme.accent : Theme.fgDim
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    font.pixelSize: Theme.fontSmall
                    text: "Playback" + (page.multi ? " on <b>" + page.esc(page.groupTitle) + "</b>" : "")
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontCaption
                    color: Theme.muted
                    readonly property string name: page.baseName(page.shownVideo)
                    text: page.switchingMode ? "Restarting " + name + (page.applyingMode === "loop" ? " in a loop…" : " to play once…")
                        : page.shownVideo !== "" && !page.targetIsPrimary && !page.ownFor(page.target)
                        ? "Plays the primary's video, " + name + (page.playMode === "loop" ? " (loop)" : " (once)") + ". Switching gives this monitor its own copy in that mode."
                        : page.shownVideo !== ""
                        ? name + (page.playMode === "loop" ? " is looping." : " plays once and holds its last frame.") + " Switching restarts it"
                          + (page.targetIsPrimary ? " and re-themes" : "") + "; videos you pick play the same way."
                        : "Videos you click " + (page.playMode === "loop" ? "loop." : "play once, then hold their last frame.")
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
                text: !page.optimize ? (page.softwareDecode && page.shownVideo !== "" ? "Off: this video has no hardware decoding here, so the original plays in software (high CPU)."
                                                                                       : "Off: videos play from the original file.")
                    : page.optJob.state === "encoding" ? "Optimizing " + page.optJob.label + " … " + page.optJob.pct + " %"
                    : "One copy per monitor at its resolution and a fitting frame rate: less GPU."
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
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontCaption
                color: Theme.muted
                text: page.optSpeed === "fast" ? "Encodes on every core at normal priority: done soonest, the desktop may stutter meanwhile."
                    : page.optSpeed === "balanced" ? "Uses about 60 % of the machine at low priority: quicker, the desktop stays responsive."
                    : "Encodes slowly on idle CPU time only, so the desktop stays smooth. Same result in every mode."
            }
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
                onMoved: v => { const p = Math.round(v * page.maxPlay); page.setTiming(p, page.uiWind, p >= page.maxPlay) }
            }
            Label {
                text: page.uiFull ? "Full length" : page.fmtSec(page.uiPlay)
                Layout.preferredWidth: 118; horizontalAlignment: Text.AlignRight
                color: page.uiFull ? Theme.fgDim : Theme.fg; font.pixelSize: Theme.fontSmall
            }
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
                onMoved: v => page.setEase(v * page.easeMax)
            }
            Label {
                text: page.fmtEase(page.uiEase)
                Layout.preferredWidth: 118; horizontalAlignment: Text.AlignRight
                color: page.uiEase > 0 ? Theme.fg : Theme.fgDim; font.pixelSize: Theme.fontSmall
            }
        }
        Label {
            visible: page.playMode === "once" && page.loopText !== ""
            Layout.fillWidth: true
            leftPadding: 96
            text: page.loopText
            color: Theme.fgDim; font.pixelSize: Theme.fontSmall
            elide: Text.ElideRight
        }
        }
    }

    Label {
        visible: page.scanned && page.list.length === 0
        Layout.fillWidth: true
        Layout.topMargin: 6
        wrapMode: Text.WordWrap
        color: Theme.fgDim
        text: page.tab === "videos"
            ? "No videos found in " + page.videoDirs.join(", ") + ". Add mp4, webm or mkv files there (video_dirs in ~/.config/theme/theme.toml)."
            : "No images found in " + page.dirs.join(", ") + " (wallpaper_dirs in ~/.config/theme/theme.toml)."
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
                current: video ? modelData === page.shownVideo : (page.shownVideo === "" && modelData === page.shown)
                cursor: index === page.sel
                busy: modelData === page.applying
                unreadable: page.unreadable(modelData)
                badge: video && current ? "▶ " + (page.shownMode === "loop" ? "LOOP" : "ONCE") : ""
                onClicked: { page.sel = index; page.apply(modelData) }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        Layout.topMargin: 4
        wrapMode: Text.WordWrap
        color: Theme.muted
        font.pixelSize: Theme.fontCaption
        readonly property string effect: !page.targetIsPrimary
            ? "only this monitor changes"
            : "the theme is re-extracted from it and every app restyles"
        text: page.tab === "videos"
            ? "Click a video (or arrows + Enter) to play it behind the desktop" + (page.targetIsPrimary ? "; the theme follows a still of it (last frame for Play once, middle frame for Loop)" : "; only this monitor changes")
              + ". Folders: video_dirs in ~/.config/theme/theme.toml. Tab switches to Images."
            : "Click an image (or arrows + Enter) to apply it; " + effect + ". Folders: wallpaper_dirs in ~/.config/theme/theme.toml. Tab switches to Videos."
    }
}
