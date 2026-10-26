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
        snapProc.command = ["sh", "-c", 'umask 077; d="$1"; g="$2"; h="$3"; snap="$4"; shift 4; rm -rf "$d"; mkdir -p "$d" || exit 1; '
            + 'python3 -I -S "$h" hold "$@" > "$d/held"; [ "$snap" = 1 ] || exit 1; '
            + 'for o in "$@"; do grim -t ppm -o "$o" "$d/$o-$g.ppm" & done; wait; for o in "$@"; do [ -s "$d/$o-$g.ppm" ] || exit 1; done',
            "_", snapDir, String(snapGen), Quickshell.shellDir + "/bin/lock-desktop-video", LockPrefs.snapshot ? "1" : "0"].concat(names)
        snapProc.running = true
        snapCap.restart()
    }
    function engageLock() {
        snapCap.stop()
        if (lockRequested && !sessionLock.locked) sessionLock.locked = true
    }
    Process {
        id: snapProc
        onExited: code => {
            if (root.snapLate) { Quickshell.execDetached(["sh", "-c", 'rm -f "$1"/*.ppm', "_", root.snapDir]); return }   // keep `held`
            root.snapsReady = code === 0
            root.engageLock()
        }
    }
    // the lock never waits for the snapshot longer than this; a late one is dropped (it may show the lock itself)
    Timer { id: snapCap; interval: 120; onTriggered: { root.snapsReady = false; root.snapLate = true; root.engageLock() } }
    property bool snapLate: false
    // after unlock: release the held desktop players (they finish their burst from the frame the reveal ended on), drop
    // the snapshots
    function dropSnaps() {
        snapsReady = false
        Quickshell.execDetached(["sh", "-c", 'd="$1"; [ -s "$d/held" ] && python3 -I -S "$2" release $(cat "$d/held"); rm -rf "$d"',
                                 "_", snapDir, Quickshell.shellDir + "/bin/lock-desktop-video"])
    }

    // correct password: play the reveal (each LockView) and unlock when it ends; instantly without snapshots
    function succeed() {
        authenticating = false
        if (!snapsReady || !LockPrefs.unlockRing || Theme.lockRevealMs <= 0) { unlock(); return }
        revealing = true
        revealEnd.restart()
    }
    Timer { id: revealEnd; interval: Theme.lockRevealMs + 50; onTriggered: root.unlock() }   // + a few frames: end on the full snapshot

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
        log("unlocked")
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
            if (secure) { root.pendingSessionLock = false; stabilize.stop(); poll.stop() }
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
                anchors.fill: parent
                wallpaper: surface.screen ? root.stillFor(surface.screen) : root.wallpaper   // qmllint disable missing-property
                // qmllint disable missing-property
                screenName: surface.screen ? surface.screen.name : ""
                // qmllint enable missing-property
                authenticating: root.authenticating
                failureMessage: root.failureMessage
                password: root.enteredPassword
                engaged: sessionLock.secure
                snapshot: root.snapsReady && screenName !== "" ? "file://" + root.snapDir + "/" + screenName + "-" + root.snapGen + ".ppm" : ""
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

    function status() {
        return JSON.stringify({ locked: currentlyLocked(), requested: lockRequested, pending: pendingSessionLock,
                                sessionLocked: sessionLock.locked, secure: sessionLock.secure, realScreens: realScreenCount(),
                                pam: pamConfigured, authenticating: authenticating, stranded: stranded, lastEvent: lastEvent })
    }
    function isSecure() { return sessionLock.secure }
}
