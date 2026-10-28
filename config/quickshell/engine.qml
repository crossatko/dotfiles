pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The WALLPAPER ENGINE: a second, rarely restarted Quickshell instance (`quickshell -p ~/.config/quickshell/engine.qml`,
// started and kept alive by hypr/scripts/start-wallpaper-engine.sh) that owns the desktop wallpaper (images AND videos)
// and the desktop clock when theme.toml `wallpaper_backend = "engine"` (Wallpaper.engine); otherwise it shows nothing.
// It shares this directory's components (WallpaperView, DeskClockView, singletons) with the main shell but does NOT
// reload when files change (settings.watchFiles false): editing the shell's QML never restarts the video. Reload on
// purpose: `qs ipc ... call engine reload`, or restart it (`theme.py wallpaper-engine restart`).
// Per monitor one EngineWindow (background layer, qs-wallpaper): image / still (out/wallpaper.json) + video (the player
// records theme.py writes to $XDG_RUNTIME_DIR/theme-video/engine/players.json instead of starting mpvpaper) + clock.
// Pauses (no decode) while: the session is locked (Lock.qml: lockPrepare .. lockRelease), a fullscreen window covers
// the monitor, the monitor is DPMS-off, or `pause` was called. Play-once clips replay a burst on every real workspace
// change of their monitor (special workspaces ignored; ignored while a burst plays), as hypr/scripts/video-replay.lua
// does for mpvpaper. State that survives a restart: the burst index (theme-video/<conn>.station, shared with the lock)
// and each clip's position ($XDG_STATE_HOME/quickshell/wallpaper-engine.json at changes / every 10 s while a loop plays,
// and $XDG_RUNTIME_DIR/wallpaper-engine/positions.json every second: a crash restart resumes within ~1 s).
// IPC (target "engine"; bin/engine-ipc finds the instance): status | reload | poke | pause | resume | replay <conn> |
//   form | lockPrepare <gen> <dir> | lockCover "<conn> ..." | lockHide | lockRelease   (see the handler below).
// Test hooks: QS_ENGINE_ALWAYS=1 draws whatever the backend says, QS_ENGINE_PLAYERS = the records file,
// QS_ENGINE_BENCH=<connector> = a throwaway instance for bin/engine-bench: that monitor only, OVERLAY layer, no clock,
// writes nothing (no positions, no clock rects).
ShellRoot {
    id: root
    settings.watchFiles: false

    readonly property string runDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string playersPath: Quickshell.env("QS_ENGINE_PLAYERS") || root.runDir + "/theme-video/engine/players.json"
    readonly property string engineDir: root.runDir + "/wallpaper-engine"
    readonly property string statePath: Appearance.dir + "/wallpaper-engine.json"
    readonly property string bench: Quickshell.env("QS_ENGINE_BENCH") || ""
    readonly property bool active: Wallpaper.engine || Quickshell.env("QS_ENGINE_ALWAYS") === "1" || root.bench !== ""

    property var players: ({})            // connector -> record
    property var saved: ({})              // connector -> { file, pos } (last run)
    property bool paused: false           // IPC pause
    property bool lockHeld: false         // lockPrepare .. lockRelease
    property bool clockHidden: false      // lockHide .. lockRelease
    property var covered: ({})            // connector -> true: clock hidden before the lock snapshot
    property string lockDir: ""
    property bool started: false

    // ---- the Hyprland instance this process talks to (Quickshell.Hyprland reads HYPRLAND_INSTANCE_SIGNATURE once, at
    // start). The supervisor passes the running instance's; if that instance goes away (a session restart while an
    // old engine lives on), the engine exits and the supervisor starts it again against the current one.
    readonly property string signature: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    property bool instanceAlive: true
    property int hyprEvents: 0
    property double lastEventAt: 0
    Connections {
        target: Hyprland
        function onRawEvent() { root.hyprEvents += 1; root.lastEventAt = Date.now() }
    }
    FileView {
        id: instanceLock
        path: root.signature !== "" ? root.runDir + "/hypr/" + root.signature + "/hyprland.lock" : ""
        printErrors: false
        onLoaded: {
            const pid = text().split("\n")[0].trim()
            if (pid !== "") procCheck.path = "/proc/" + pid + "/comm"
        }
        onLoadFailed: root.instanceGone("no lock file")
    }
    FileView {
        id: procCheck
        printErrors: false
        onLoaded: if (!/hyprland/i.test(text())) root.instanceGone("pid is not Hyprland")
        onLoadFailed: root.instanceGone("Hyprland pid gone")
    }
    Timer { interval: 30000; repeat: true; running: root.signature !== "" && root.bench === ""; onTriggered: { instanceLock.reload(); if (procCheck.path !== "") procCheck.reload() } }
    function instanceGone(why) {
        if (!root.instanceAlive) return
        root.instanceAlive = false
        console.warn("engine: Hyprland instance " + root.signature + " is gone (" + why + "): exiting, the supervisor restarts against the current one")
        root.save()
        Qt.quit()
    }
    readonly property var windows: wins.instances

    function parsePlayers(text) {
        let j = null
        try { j = JSON.parse(text) } catch (e) { j = null }
        const p = j && typeof j.players === "object" && j.players ? j.players : {}
        const out = {}
        for (const k of Object.keys(p)) {
            const r = p[k]
            if (r && typeof r.file === "string" && r.file !== "" && (r.mode === "loop" || r.mode === "once")) out[k] = r
        }
        if (JSON.stringify(out) !== JSON.stringify(root.players)) root.players = out
    }
    FileView {
        id: playersFile
        path: root.playersPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        // (not before the saved positions are read: a clip planned without them starts from 0)
        onLoaded: if (root.started) root.parsePlayers(text())
        onLoadFailed: if (root.started) root.parsePlayers("")
    }
    FileView {
        id: stateFile
        path: root.statePath
        blockLoading: true
        printErrors: false
    }
    // the same, every second while a loop plays, in the runtime dir (tmpfs): a crash restart resumes within ~1 s
    FileView {
        id: posFile
        path: root.engineDir + "/positions.json"
        blockLoading: true
        printErrors: false
    }
    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", root.engineDir, Appearance.dir])
        // each monitor's active workspace known from the start (else the first switch only initialises it: no burst)
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
        // the runtime copy when there is one (this login, fresher), else the state file (last session)
        for (const f of [posFile, stateFile]) {
            try {
                const s = JSON.parse(f.text())
                if (s && typeof s.players === "object" && s.players) { root.saved = s.players; break }
            } catch (e) { /* missing / unreadable: next */ }
        }
        root.started = true
        root.parsePlayers(playersFile.text())
    }

    // ---- positions for the next start ----
    function snapshot() {
        const out = {}
        for (const w of root.windows) {
            const s = w && w.video ? w.video.shown : null
            if (s && s.file !== "") out[w.conn] = { file: s.file, pos: Math.round(s.player.position) }
        }
        return out
    }
    // state (disk): at changes (burst start / end, pause, clip swap) and every 10 s while a loop plays; runtime: every 1 s
    function save(disk) {
        if (root.bench !== "") return
        const t = JSON.stringify({ version: 1, players: root.snapshot() }) + "\n"
        if (t !== saver.lastPos) { saver.lastPos = t; posFile.setText(t) }
        if (disk !== false && t !== saver.last) { saver.last = t; stateFile.setText(t) }
    }
    Timer { id: saver; interval: 500; property string last: ""; property string lastPos: ""; onTriggered: root.save(true) }
    Timer {   // a looping clip; nothing while all are held / still
        interval: 1000
        repeat: true
        property int n: 0
        running: root.windows.some(w => w && w.video.shown.loop && !w.held)
        onTriggered: { n = (n + 1) % 10; root.save(n === 0) }
    }

    // ---- DPMS: no event; re-read the monitors every 3 s while a clip would play ----
    Timer {
        interval: 3000
        repeat: true
        running: root.active && !root.lockHeld && Object.keys(root.players).length > 0
        onTriggered: Hyprland.refreshMonitors()
    }

    // ---- the clock rects for the lock (Lock.qml reads them: the cover test and the clean rects) ----
    function clockRects() {
        const m = {}
        for (const w of root.windows) if (w && w.inkRect.length === 4 && w.inkRect[2] > 0) m[w.conn] = w.inkRect
        return m
    }
    readonly property string rectsText: JSON.stringify(root.active ? root.clockRects() : {})
    onRectsTextChanged: rectsSave.restart()
    Timer { id: rectsSave; interval: 300; onTriggered: if (root.bench === "") rectsFile.setText(root.rectsText + "\n") }
    FileView { id: rectsFile; path: root.engineDir + "/clock.json"; printErrors: false }

    Variants {
        id: wins
        model: !root.active ? [] : root.bench !== "" ? Quickshell.screens.filter(s => s.name === root.bench) : Quickshell.screens
        EngineWindow {
            id: w
            record: root.players[w.conn] ?? null
            saved: root.saved[w.conn] ?? null
            readonly property var ws: w.monitor ? w.monitor.activeWorkspace : null
            readonly property bool fullscreen: !!w.ws && w.ws.hasFullscreen
            // DPMS off: from the monitor's last `hyprctl monitors` record (refreshed every 3 s above)
            readonly property bool dpmsOff: !!w.monitor && !!w.monitor.lastIpcObject && w.monitor.lastIpcObject.dpmsStatus === false
            held: root.paused || root.lockHeld || w.fullscreen || w.dpmsOff
            clockHidden: root.clockHidden
            bench: root.bench !== ""
            clockCovered: root.covered[w.conn] === true
            // every real workspace change on this monitor replays a play-once clip (special workspaces never count).
            // Compared by NAME: Quickshell leaves the id at -1 for workspaces it first saw through a window (live: every
            // workspace with windows that was not active at the engine's start), so an id test ignored most switches.
            property string lastWs: ""
            property int wsChanges: 0             // status: real changes seen / bursts they started
            property int wsBursts: 0
            property double lastWsAt: 0
            property int unlockBursts: 0
            onWsChanged: {
                const name = w.ws ? String(w.ws.name ?? "") : ""
                if (name === "" || name.startsWith("special")) return
                if (w.lastWs !== "" && name !== w.lastWs) {
                    w.wsChanges += 1
                    w.lastWsAt = Date.now()
                    if (w.video.replay()) w.wsBursts += 1
                }
                w.lastWs = name
            }
            Connections {
                target: w.video
                function onChanged() { saver.restart() }
            }
        }
    }

    // ---- lock (Lock.qml, through bin/engine-ipc) ----
    // lockPrepare: pause every clip where it is (the snapshot shows the frame the desktop will still be on at unlock;
    // nothing decodes while locked) and write each shown clock's clean rect to <dir>/clean-<conn>-<gen>.png (next frame).
    // Returns "ok <connectors grabbed>". lockCover: hide those clocks now (covered: before the snapshot). lockHide: the lock
    // is up: hide every clock (never drawn under the lock). lockRelease: the unlock is done: clips continue, clocks form.
    function lockPrepare(gen, dir) {
        root.lockHeld = true
        root.lockDir = dir
        const conns = []
        for (const w of root.windows) {
            if (!w || !w.clockShown) continue
            conns.push(w.conn)
            w.grabClean(dir + "/clean-" + w.conn + "-" + gen + ".png", ok => { if (!ok) console.warn("engine: no clean rect for " + w.conn) })
        }
        lockWatch.restart()
        return "ok " + conns.join(" ")
    }
    function lockRelease() {
        lockWatch.stop()
        const wasHeld = root.lockHeld
        // a clock that was hidden (lock up / covered) forms again, its first digit at once (the unlock ring was the pause)
        for (const w of root.windows) if (w && w.clock && (root.clockHidden || root.covered[w.conn] === true)) w.clock.form(0)
        root.lockHeld = false
        root.covered = ({})
        root.lockDir = ""
        root.clockHidden = false
        // the unlock wakes the wallpaper like a workspace switch: one burst per play-once monitor, right after the ring
        // (this call comes when it has revealed the desktop). A burst that was paused by the lock continues from the
        // snapshot's frame instead (replay ignores a running burst: the same debounce as workspace switches).
        if (wasHeld) Qt.callLater(() => { for (const w of root.windows) if (w && w.video.replay()) w.unlockBursts += 1 })
    }
    // a lock that never got its release (the shell died while locked): Lock.qml deletes <dir> at the unlock
    Timer {
        id: lockWatch
        interval: 2000
        repeat: true
        onTriggered: { heldFile.reload() }
    }
    FileView {
        id: heldFile
        path: root.lockDir !== "" ? root.lockDir + "/held" : ""
        printErrors: false
        onLoadFailed: if (root.lockHeld && lockWatch.running) { console.warn("engine: lock released without lockRelease"); root.lockRelease() }
    }

    IpcHandler {
        target: "engine"
        function status(): string {
            const base = p => p ? String(p).replace(/^.*\//, "") : ""
            return JSON.stringify({
                active: root.active, backend: Wallpaper.backend, paused: root.paused, lockHeld: root.lockHeld, clockHidden: root.clockHidden,
                screens: root.windows.filter(w => !!w).map(w => {
                    const s = w.video.shown
                    return { screen: w.conn, still: base(w.view.shownSlot.path), ready: w.view.ready, held: w.held, fullscreen: w.fullscreen,
                             dpmsOff: w.dpmsOff, video: base(s.file), mode: s.rec ? s.rec.mode : "",
                             pos: Math.round(s.player.position), playing: s.playing, idx: s.idx, showing: w.video.showing, busy: w.video.busy,
                             loading: base(w.video.back.file), clock: w.clockShown, ink: w.inkRect,
                             workspace: w.lastWs, wsChanges: w.wsChanges, wsBursts: w.wsBursts, unlockBursts: w.unlockBursts,
                             lastWsAgoMs: w.lastWsAt > 0 ? Date.now() - w.lastWsAt : -1 }
                }),
                hyprland: { signature: root.signature, instanceAlive: root.instanceAlive, events: root.hyprEvents,
                            lastEventAgoMs: root.lastEventAt > 0 ? Date.now() - root.lastEventAt : -1 }
            })
        }
        function reload(): void { root.save(); Quickshell.reload(true) }
        function poke(): void { playersFile.reload() }
        function pause(): void { root.paused = true }
        function resume(): void { root.paused = false }
        function replay(conn: string): string {
            const w = root.windows.find(x => x && x.conn === conn)
            return w && w.video.replay() ? "ok" : "ignored"
        }
        function form(): void { for (const w of root.windows) if (w && w.clock) w.clock.form(0) }
        // test hook: <prefix>-<conn>-glass.png / -paper.png (EngineWindow.debugGrab)
        function debugGrab(prefix: string): string { return root.windows.filter(w => w && w.debugGrab(prefix + "-" + w.conn)).map(w => w.conn).join(" ") }
        function lockPrepare(gen: string, dir: string): string { return root.lockPrepare(gen, dir) }
        function lockCover(conns: string): void {
            const m = {}
            for (const c of conns.split(" ")) if (c !== "") m[c] = true
            root.covered = m
        }
        function lockHide(): void { root.clockHidden = true; root.save() }
        function lockRelease(): void { root.lockRelease() }
    }
}
