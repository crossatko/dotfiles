pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland

// Lock screen service (replaces hyprlock): an ext-session-lock (WlSessionLock) with one LockView per screen, and the
// password checked by PAM (service `quickshell-lock`, system/etc/pam.d/quickshell-lock, installed by `install.sh
// --system`). `qs ipc call lock lock | locked | secure | status` (shell.qml).
//   lock()    request the lock. It is taken once real outputs exist and have been stable for a moment (a lock taken
//             while outputs come and go, e.g. right after a resume, may leave one uncovered).
//   locked()  a lock is requested or held;  secure()  the compositor confirmed every output is covered (lock-wait
//             polls it before suspend).
// Crash safety: ext-session-lock outlives its client (Hyprland shows its red failsafe), so on start the shell asks
// bin/lock-stranded whether an orphaned lock exists and takes it over (needs misc:allow_session_lock_restore).
// Test hooks: QS_LOCK_PAM_DIR / QS_LOCK_PAM_SERVICE (another PAM directory / service name), QS_LOCK_WALLPAPER.
Item {
    id: root

    readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
    readonly property string pamService: Quickshell.env("QS_LOCK_PAM_SERVICE") || "quickshell-lock"
    readonly property string pamDir: Quickshell.env("QS_LOCK_PAM_DIR") || "/etc/pam.d"
    // each monitor's still: LockWallpapers (theme.py's per-monitor wallpapers, QS_LOCK_WALLPAPER / QS_WALLPAPERS_FILE)
    readonly property string wallpaper: LockWallpapers.primary
    function stillFor(screen) { return LockWallpapers.stillFor(screen) }
    // Pre-decoded stills: the lock's backdrop Image (LockView: same url and size) then comes out of the pixmap cache on
    // the first frame instead of decoding after the surface exists.
    Variants {
        model: Quickshell.screens
        Image {
            required property ShellScreen modelData
            visible: false
            asynchronous: true
            source: modelData && modelData.width > 0 ? "file://" + root.stillFor(modelData) : ""
            sourceSize: Qt.size(modelData.width + 2 * root.blurBleed, modelData.height + 2 * root.blurBleed)
            fillMode: Image.PreserveAspectCrop
        }
    }
    readonly property int blurBleed: LockPrefs.blurMax   // = LockView.bleed
    property double screensChangedAt: 0        // outputs came / went this recently: let them settle before locking

    property bool lockRequested: false
    property bool pendingSessionLock: false
    property bool authenticating: false
    property bool pamConfigured: false
    property string enteredPassword: ""
    property string pendingPassword: ""
    property string failureMessage: ""
    property int failedAttempts: 0
    property bool strandedResolved: false
    property bool stranded: false
    property bool skipSnap: false        // a stranded-lock takeover: the screen shows the failsafe, nothing to snapshot
    property string lastEvent: ""
    // Desktop snapshots for the unlock transition (LockView / LockReveal): grim of every output right before the lock
    // is taken, into $XDG_RUNTIME_DIR/qs-lock (tmpfs, 0700), deleted after unlock. Shown only while revealing, i.e.
    // after a successful password. A failed capture = the old instant unlock.
    readonly property string snapDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-lock"
    property bool snapsReady: false
    property bool revealing: false
    property int snapGen: 0              // new file names per lock (no stale image cache)

    // Decisions read the lock state afresh (a binding once reported "locked" after an unlock).
    function currentlyLocked() { return lockRequested || sessionLock.locked || sessionLock.secure }
    readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure

    function log(event) { lastEvent = event; console.log("lock " + event) }

    function realScreenCount() {
        let n = 0
        for (const s of Quickshell.screens) if (s && s.name && s.width > 0 && s.height > 0) n++
        return n
    }

    function resetAuth() {
        if (pam.active) pam.abort()
        enteredPassword = ""
        pendingPassword = ""
        failureMessage = ""
        failedAttempts = 0
        authenticating = false
    }

    function lock() {
        if (!pamConfigured) { log("lock-denied: no PAM service " + pamService); return false }
        if (currentlyLocked()) return true
        resetAuth()
        lockRequested = true
        pendingSessionLock = true
        log("lock-requested")
        // outputs quiet for a while (the normal case): lock at once; right after a hotplug / resume: wait for them
        if (Date.now() - screensChangedAt > 1500 && realScreenCount() > 0) { requestSessionLock(); return true }
        stabilize.restart()
        poll.start()
        return true
    }

    // Take the lock once there is a real screen and the outputs were quiet for stabilize.interval.
    function requestSessionLock() {
        if (!lockRequested || sessionLock.locked || sessionLock.secure || stabilize.running || snapProc.running) return
        if (realScreenCount() === 0) return   // poll keeps asking
        pendingSessionLock = false
        poll.stop()
        // snapshot first (capped by snapCap), then lock
        snapsReady = false
        snapLate = false
        if (skipSnap) { skipSnap = false; engageLock(); return }
        snapGen += 1
        const names = []
        for (const s of Quickshell.screens) if (s && s.name && s.width > 0) names.push(s.name)
        // first hold any desktop video player that is mid-burst (bin/lock-desktop-video; the connectors it paused go to
        // $d/held for the release at unlock), so the snapshot shows the frame the desktop will still be on at unlock
        // (Settings > Lock "Desktop snapshot" off: only the hold, nothing of the desktop is captured; exit 1 = no snapshots)
        // Desktop clock (snapHideS > 0): it stays on screen and in the snapshot (the lock surface fades it out,
        // LockClockPatch); only a clock that is covered (bin/lock-clock-cover, asked alongside the hold) is hidden first,
        // every clock when a video was held (mid-burst: the clock's copy moves on, and a busy compositor answers slowly):
        // "hide <connectors> | *" on stdout, then snapHideS for the compositor to show that.
        clockHideOn = []
        enginePatches = ({})
        // the clean rects for LockClockPatch, alongside the snapshot: the clock window must still be drawing (the
        // compositor stops its frames once the lock is up, then a grab never finishes)
        if (snapHideS > 0 && LockPrefs.snapshot && !engineMode) clockGrab()
        // Wallpaper engine (e = 1): `engine-ipc lockPrepare` instead of the hold: the engine pauses its clips and writes each
        // clock's clean rect (clean-<conn>-<gen>.png, a frame later; "clean <conn>" once it is there, waited for after
        // grim, ~60 ms at most), a covered clock is hidden by `lockCover`; no engine = nothing happens (exit 3 at once)
        snapProc.command = ["sh", "-c", 'umask 077; d="$1"; g="$2"; h="$3"; snap="$4"; w="$5"; c="$6"; r="$7"; e="$8"; x="$9"; shift 9; rm -rf "$d"; mkdir -p "$d" || exit 1; '
            + 'cp=; [ "$w" = 0 ] || [ "$snap" != 1 ] || { python3 -I -S "$c" "$r" > "$d/cover" & cp=$!; }; '
            + 'ec=; if [ "$e" = 1 ]; then : > "$d/held"; ec=$("$x" lockPrepare "$g" "$d" 2>/dev/null); else python3 -I -S "$h" hold "$@" > "$d/held"; fi; [ "$snap" = 1 ] || exit 1; '
            + 'if [ -n "$cp" ]; then if [ -s "$d/held" ]; then kill "$cp"; hide="*"; else wait "$cp"; hide=$(xargs < "$d/cover"); fi; '
            + '[ -z "$hide" ] || { echo "hide $hide"; [ "$e" != 1 ] || "$x" lockCover "$hide" > /dev/null 2>&1; sleep "$w"; }; fi; '
            + 'for o in "$@"; do grim -t ppm -o "$o" "$d/$o-$g.ppm" & done; wait; for o in "$@"; do [ -s "$d/$o-$g.ppm" ] || exit 1; done; '
            + 'case "$ec" in "ok "*) for o in ${ec#ok }; do i=0; while [ ! -s "$d/clean-$o-$g.png" ] && [ $i -lt 12 ]; do sleep 0.005; i=$((i + 1)); done; '
            + '[ -s "$d/clean-$o-$g.png" ] && echo "clean $o"; done;; esac; exit 0',
            "_", snapDir, String(snapGen), Quickshell.shellDir + "/bin/lock-desktop-video", LockPrefs.snapshot ? "1" : "0", String(snapHideS),
            Quickshell.shellDir + "/bin/lock-clock-cover", JSON.stringify(clockRects), engineMode ? "1" : "0", engineIpc].concat(names)
        snapProc.running = true
        snapCap.restart()
    }
    function engageLock() {
        snapCap.stop()
        if (lockRequested && !sessionLock.locked) sessionLock.locked = true
    }
    Process {
        id: snapProc
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("clean ")) { root.enginePatch(line.substring(6).trim()); return }
                if (!line.startsWith("hide ")) return
                const l = line.substring(5).split(" ").filter(c => c !== "")
                root.clockHideOn = l.indexOf("*") >= 0 ? root.clockScreens.slice() : l
            }
        }
        onExited: code => {
            if (root.snapLate) { Quickshell.execDetached(["sh", "-c", 'rm -f "$1"/*.ppm', "_", root.snapDir]); return }   // keep `held`
            root.snapsReady = code === 0
            root.engageLock()
        }
    }
    // the lock never waits for the snapshot longer than this; a late one is dropped (it may show the lock itself)
    // the late capture is stopped too: a hung grim (an output that draws no frames) kept snapProc running, and every
    // later lock() returned early in requestSessionLock: the session never locked again
    Timer { id: snapCap; interval: 120; onTriggered: { root.snapsReady = false; root.snapLate = true; root.engageLock(); snapProc.running = false } }
    property bool snapLate: false
    // after unlock: release the held desktop players (they finish their burst from the frame the reveal ended on), drop
    // the snapshots
    function dropSnaps() {
        snapsReady = false
        if (engineMode) Quickshell.execDetached(["sh", "-c", '"$2" lockRelease; rm -rf "$1"', "_", snapDir, engineIpc])
        else Quickshell.execDetached(["sh", "-c", 'd="$1"; [ -s "$d/held" ] && python3 -I -S "$2" release $(cat "$d/held"); rm -rf "$d"',
                                      "_", snapDir, Quickshell.shellDir + "/bin/lock-desktop-video"])
    }

    // ---- wallpaper engine (theme.toml wallpaper_backend "engine": engine.qml draws the wallpaper and the desktop clock in
    // its own process; Wallpaper.engine). Same lock behaviour over bin/engine-ipc (~12 ms a call, 150 ms cap, exit 3 at
    // once without an engine): lockPrepare before the snapshot (clips paused: the snapshot is the frame the desktop
    // stays on; the clean rects as PNGs), lockCover for a covered clock, lockHide once secure (the clock is never drawn
    // under the lock: no old clock in the engine's buffer at the unlock), lockRelease after the unlock (clips go on, the
    // clocks form). The clock rects come from the engine's $XDG_RUNTIME_DIR/wallpaper-engine/clock.json ({conn: [x, y,
    // w, h]} global px). shell.qml switches clockScreens / clockRects / clockPatches to these.
    readonly property bool engineMode: Wallpaper.engine
    readonly property string engineIpc: Quickshell.shellDir + "/bin/engine-ipc"
    property var engineRects: ({})
    property var enginePatches: ({})
    FileView {
        path: root.engineMode ? (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/wallpaper-engine/clock.json" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let j = null
            try { j = JSON.parse(text()) } catch (e) { j = null }
            root.engineRects = j && typeof j === "object" && !Array.isArray(j) ? j : {}
        }
        onLoadFailed: root.engineRects = {}
    }
    function enginePatch(conn) {
        const r = engineRects[conn], s = Quickshell.screens.find(x => x && x.name === conn)
        if (!Array.isArray(r) || r.length !== 4 || !s) return
        const m = Object.assign({}, enginePatches)
        m[conn] = { result: { url: "file://" + snapDir + "/clean-" + conn + "-" + snapGen + ".png" }, x: r[0] - s.x, y: r[1] - s.y, w: r[2], h: r[3] }
        enginePatches = m
    }

    // correct password: play the reveal (each LockView) and unlock when it ends; instantly without snapshots
    function succeed() {
        authenticating = false
        if (!snapsReady || !LockPrefs.unlockRing || Theme.lockRevealMs <= 0) { unlock(); return }
        // a desktop clock in the snapshot without its clean rect would end the ring on a clock that then vanishes
        if (snapHideS > 0 && clockScreens.some(c => clockHideOn.indexOf(c) < 0 && !clockPatchFor(c))) { unlock(); return }
        revealing = true
        revealEnd.restart()
    }
    Timer { id: revealEnd; interval: Theme.lockRevealMs + 50; onTriggered: root.unlock() }   // + a few frames: end on the full snapshot

    // the desktop is back (DeskClock forms its clocks again); a signal, not `locked`: that binding once kept "locked"
    signal unlocked()
    // seconds the desktop snapshot waits after a desktop clock was hidden for it (covered clocks only, see
    // requestSessionLock), so it is gone from the screen grim captures (two frames at 60 Hz); 0 = no desktop clock
    // (shell.qml sets it, and wires the clock: clockGrab -> DeskClock.grabClean, its patches / shownOn back here)
    property real snapHideS: 0
    signal clockGrab()
    property var clockPatches: ({})     // connector -> DeskClock.patches entry
    property var clockScreens: []       // connectors that show a desktop clock
    property var clockRects: ({})       // connector -> [x, y, w, h] the clock paints (global px; DeskClock.inkRects)
    property var clockHideOn: []        // connectors whose clock hides before the snapshot
    property bool clockHidden: false    // the lock is up: every desktop clock hides (under the lock surface)
    function clockPatchFor(conn) {
        return snapsReady && conn !== "" && clockHideOn.indexOf(conn) < 0 ? (clockPatches[conn] || null) : null
    }
    function unlock() {
        lockRequested = false
        pendingSessionLock = false
        stabilize.stop()
        poll.stop()
        resetAuth()
        revealEnd.stop()
        sessionLock.locked = false
        revealing = false
        dropSnaps()
        clockHidden = false
        clockHideOn = []
        enginePatches = ({})
        log("unlocked")
        unlocked()
    }

    function submit(password) {
        if (!lockRequested || authenticating || password.length === 0) return
        pendingPassword = password
        failureMessage = ""
        authenticating = true
        if (!pam.start()) { fail(); return }
        Qt.callLater(respondToPrompt)
    }
    function respondToPrompt() {
        if (authenticating && pam.active && pam.responseRequired) pam.respond(pendingPassword)
    }
    function fail() {
        if (!lockRequested || !authenticating) return   // onError and onCompleted can both report one attempt
        authenticating = false
        enteredPassword = ""
        pendingPassword = ""
        failedAttempts += 1
        failureMessage = "Wrong password (" + failedAttempts + ")"
    }

    // ---- stranded lock (the previous shell died holding the lock) ----
    function checkStranded() {
        if (strandedResolved || strandedProc.running) return
        if (currentlyLocked()) { strandedResolved = true; return }
        strandedProc.running = true
    }
    function recoverStranded() {
        if (!stranded || currentlyLocked() || !pamConfigured) return
        stranded = false
        log("lock-stranded: recovering")
        skipSnap = true
        lock()
    }
    Process {
        id: strandedProc
        // $PPID = this shell (a crash re-execs in place, so the pid is the one to skip)
        command: ["bash", "-c", "exec \"$1/bin/lock-stranded\" \"$PPID\"", "_", Quickshell.shellDir]
        onExited: code => {
            if (code === 2) return          // outputs not ready / another locker alive: ask again
            root.strandedResolved = true
            root.stranded = code === 0 && !root.currentlyLocked()
            root.recoverStranded()
        }
    }
    // outputs are often still absent at start: ask until the answer means something
    Timer {
        id: strandedRetry
        interval: 500
        repeat: true
        property int remaining: 20
        running: !root.strandedResolved && remaining > 0 && root.pamConfigured
        onTriggered: { remaining -= 1; root.checkStranded() }
    }

    FileView {
        path: root.pamDir + "/" + root.pamService
        watchChanges: true
        printErrors: false
        onLoaded: root.pamConfigured = true
        onLoadFailed: root.pamConfigured = false
        onFileChanged: reload()
    }
    onPamConfiguredChanged: if (pamConfigured) { strandedResolved = false; strandedRetry.remaining = 20; checkStranded() }

    Timer { id: stabilize; interval: 500; onTriggered: root.requestSessionLock() }
    Timer { id: poll; interval: 100; repeat: true; onTriggered: root.requestSessionLock() }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            root.screensChangedAt = Date.now()
            if (root.lockRequested && !sessionLock.locked && !sessionLock.secure) stabilize.restart()
            strandedRetry.remaining = 20
            root.checkStranded()
        }
    }

    PamContext {
        id: pam
        config: root.pamService
        configDirectory: root.pamDir
        user: root.userName
        onResponseRequiredChanged: root.respondToPrompt()
        onPamMessage: root.respondToPrompt()
        onCompleted: result => {
            if (!root.lockRequested) return
            if (result === PamResult.Success) root.succeed()
            else root.fail()
            root.authenticating = false
            root.pendingPassword = ""
        }
        onError: root.fail()
    }

    WlSessionLock {
        id: sessionLock
        locked: false
        onSecureStateChanged: {
            root.log("secure=" + secure)
            if (secure) {
                root.pendingSessionLock = false; root.clockHidden = true; stabilize.stop(); poll.stop()
                if (root.engineMode) Quickshell.execDetached([root.engineIpc, "lockHide"])
            }
        }
        // the compositor ended the lock under us (it can, e.g. a restore by another client)
        onLockStateChanged: {
            root.log("session-locked=" + locked)
            if (!locked && root.lockRequested) root.unlock()
        }

        WlSessionLockSurface {
            id: surface
            color: Theme.bg
            LockView {
                id: lockView
                anchors.fill: parent
                Component.onCompleted: root.views.push(lockView)
                Component.onDestruction: root.views = root.views.filter(v => v !== lockView)
                wallpaper: surface.screen ? root.stillFor(surface.screen) : root.wallpaper   // qmllint disable missing-property
                // qmllint disable missing-property
                screenName: surface.screen ? surface.screen.name : ""
                // qmllint enable missing-property
                authenticating: root.authenticating
                failureMessage: root.failureMessage
                password: root.enteredPassword
                engaged: sessionLock.secure
                snapshot: root.snapsReady && screenName !== "" ? "file://" + root.snapDir + "/" + screenName + "-" + root.snapGen + ".ppm" : ""
                clockPatch: root.clockPatchFor(screenName)
                revealing: root.revealing
                onPasswordEdited: p => root.enteredPassword = p
                onSubmit: p => root.submit(p)
            }
        }
    }

    // compile the lock view once at start (a throwaway instance outside any window): the first lock then does not spend
    // ~50 ms building its types while the surfaces wait
    Component { id: warmView; LockView {} }
    Timer { interval: 2000; running: true; onTriggered: { const o = warmView.createObject(null); if (o) o.destroy() } }

    Component.onCompleted: checkStranded()

    // the lock surfaces' views (status: per-screen backdrop state while locked)
    property var views: []
    function status() {
        // per screen: the still it would show and, while locked, what its surface really shows (still / video / none)
        const base = p => p ? String(p).replace(/^.*\//, "") : ""
        const screens = views.length > 0 ? views.map(v => v.wallState())
            : Quickshell.screens.filter(s => s && s.name).map(s => ({ screen: s.name, still: base(stillFor(s)) }))
        return JSON.stringify({ locked: currentlyLocked(), requested: lockRequested, pending: pendingSessionLock,
                                sessionLocked: sessionLock.locked, secure: sessionLock.secure, realScreens: realScreenCount(),
                                pam: pamConfigured, authenticating: authenticating, stranded: stranded, lastEvent: lastEvent,
                                screens: screens })
    }
    function isSecure() { return sessionLock.secure }
}
