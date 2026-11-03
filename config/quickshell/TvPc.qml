pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "launcher/js/TvPc.js" as Js

// Play on PC: moves what the TV card (TvSession.card: a sent session or what the TV plays by itself) shows to this PC, at
// the TV's position, then pauses the TV (TvPrefs.pauseAfter) and ends a sent session. What is recoverable per TV app and
// the PC player per source: launcher/js/TvPc.js (resolve / settle / command, node tests). Lookups: a YouTube video the TV
// plays by itself (Cast gives title + channel + length, no id) = a yt-dlp search that must match exactly; a Jellyfin item
// (Wholphin) = `jellyfin-qs playing --json` (the server's session of the TV client). `phase`: "" | "finding" | "opening" |
// "sent" | "failed" (`error`); a click while busy cancels. Dry run (TvPrefs.dryRun) logs the command instead of running it.
//   qs ipc call tvpc status | press | cancel | last
// Test hooks: QS_TVPC_RUN (a program that gets the player's argv instead of running it), QS_TVPC_YTDLP (yt-dlp),
// LAUNCHER_TWITCH_DIR (twitch-qs-mpv's bin/, as TwitchSource).
Singleton {
    id: pc

    readonly property string runner: Quickshell.env("QS_TVPC_RUN") || ""
    readonly property string ytdlp: Quickshell.env("QS_TVPC_YTDLP") || "yt-dlp"
    readonly property string twitchPath: (Quickshell.env("LAUNCHER_TWITCH_DIR") || (Quickshell.env("HOME") + "/code/crossatko/twitch-qs-mpv/bin")) + "/twitch-qs-mpv"
    readonly property var jellyfin: ["sh", "-c", 'PATH="$PATH:$HOME/.local/bin"; exec jellyfin-qs "$@"', "sh"]   // as JellyfinSource
    readonly property int sentMs: 2500
    readonly property int failedMs: 8000
    readonly property int lookupMs: 15000

    property bool twitchApp: false                // twitch-qs-mpv is installed (probed once)
    readonly property var env: ({ twitchApp: twitchApp ? twitchPath : "", jellyfin: jellyfin })

    // the TV card's facts as TvPc.js reads them
    function factsOf(c) {
        if (!c) return null
        return { sent: !!c.sent, kind: c.kind || "", ref: c.ref || "", origin: c.origin || "", title: c.title || "", subtitle: c.subtitle || "",
                 tvTitle: c.tvTitle || "", tvArtist: c.tvArtist || "", appId: c.appId || "", app: c.app || "", position: typeof c.position === "number" ? c.position : -1,
                 positionAt: c.positionAt || 0, duration: typeof c.duration === "number" ? c.duration : -1, playing: !!c.playing }
    }
    property double tick: Date.now()              // the tooltip's position, ticking while a card shows in the popup
    Timer { interval: 1000; repeat: true; running: Popups.name === "media" && TvSession.card !== null; onTriggered: pc.tick = Date.now() }
    readonly property var target: Js.resolve(factsOf(TvSession.card), tick)
    readonly property bool usable: target !== null && target.state !== "none" && (target.state === "lookup" || Js.command(target, env) !== null)
    readonly property string hint: !target ? "" : target.state === "lookup"
        ? (target.lookup === "youtube" ? "Find this video and play it on this PC" : "Play this Jellyfin item on this PC") + (target.start > 0 ? " at " + Js.clock(target.start) : "")
        : target.state === "ready" && !Js.command(target, env) ? "No player for this on this PC" : Js.describe(target)

    property string phase: ""
    property string error: ""
    readonly property bool busy: phase === "finding" || phase === "opening"
    property int run: 0
    property var log: []                          // {at, dry, target, argv, result}
    function pushLog(e) { log = log.concat([e]).slice(-20) }

    Timer { id: clearT; onTriggered: if (!pc.busy) { pc.phase = ""; pc.error = "" } }
    function show(ph, ms) { phase = ph; clearT.interval = ms; clearT.restart() }
    function fail(token, msg) {
        if (token !== run) return
        if (entry) { entry.result = "failed: " + msg; entry = null; log = log.slice() }
        error = msg
        show("failed", failedMs)
    }
    function cancel() {
        if (!busy) return
        run++
        lookupWatchdog.stop()
        lookupProc = stopRun(lookupProc)
        playProc = stopRun(playProc)
        if (entry) { entry.result = "cancelled"; entry = null; log = log.slice() }
        phase = ""; error = ""
    }

    property var entry: null
    function press() {
        if (busy) { cancel(); return "cancelled" }
        const t = Js.resolve(factsOf(TvSession.card), Date.now())
        const token = ++run
        clearT.stop()
        error = ""
        entry = { at: new Date().toISOString(), dry: TvPrefs.dryRun, target: t, argv: null, result: "" }
        pushLog(entry)
        if (!t || t.state === "none") { fail(token, t ? t.reason : "Nothing plays on the TV"); return "unsupported" }
        if (t.state === "ready") { launch(token, t); return "started" }
        phase = "finding"
        if (t.lookup === "youtube") {
            const q = (t.want.title + " " + (t.want.artist || "")).trim()
            lookup(token, [ytdlp, "--flat-playlist", "--no-warnings", "--ignore-config", "-j", "ytsearch5:" + q], (code, out) => {
                if (code !== 0 && out.trim() === "") { fail(token, "YouTube search failed (is yt-dlp installed?)"); return }
                const rows = out.split("\n").filter(l => l.trim() !== "").map(l => { try { return JSON.parse(l) } catch (e) { return null } })
                pc.settleAndLaunch(token, t, Js.matchYoutube(rows, t.want))
            })
        } else {
            lookup(token, jellyfin.concat(["playing", "--json"]), (code, out) => {
                if (code !== 0) { fail(token, code === 2 ? "Jellyfin: not logged in (jellyfin-qs login)" : code === 3 ? "Jellyfin server unreachable" : "jellyfin-qs failed (exit " + code + ")"); return }
                let rows = []
                try { rows = JSON.parse(out) } catch (e) { rows = [] }
                pc.settleAndLaunch(token, t, Js.pickJellyfin(Array.isArray(rows) ? rows : [], t.want))
            })
        }
        return "started"
    }
    function settleAndLaunch(token, t, answer) {
        if (token !== run) return
        const r = Js.settle(t, answer)
        if (entry) entry.target = r
        if (r.state !== "ready") { fail(token, r.reason); return }
        launch(token, r)
    }
    function launch(token, t) {
        const cmd = Js.command(t, env)
        if (!cmd) { fail(token, "No player for this on this PC"); return }
        const argv = runner !== "" ? [runner].concat(cmd.argv) : cmd.argv
        if (entry) entry.argv = cmd.argv
        if (TvPrefs.dryRun) { if (entry) { entry.result = "dry run"; entry = null; log = log.slice() } show("sent", sentMs); return }
        phase = "opening"
        // jellyfin-qs answers at once (it starts mpv detached): its exit code says why it failed; the others are detached
        if (t.kind === "jellyfin") {
            playProc = stopRun(playProc)
            playProc = spawn(argv, (code, out, err) => {
                pc.playProc = null
                if (code === 0) pc.done(token)
                else pc.fail(token, (String(err).trim().split("\n").pop() || "jellyfin-qs play failed (exit " + code + ")").slice(0, 160))
            })
            return
        }
        Quickshell.execDetached(argv)
        done(token)
    }
    function done(token) {
        if (token !== run) return
        if (entry) { entry.result = "opened"; entry = null; log = log.slice() }
        if (TvPrefs.pauseAfter && !TvPrefs.dryRun) TvSession.control("pause")   // the TV keeps its place (never stop: BACK leaves the player)
        if (TvSession.active) TvSession.end("moved to PC")
        show("sent", sentMs)
    }
    // a process whose exit code and output are both wanted: cb(code, stdout, stderr) once it exited and its streams closed.
    // One object per run (a killed run's late signals can never count for the next); callers check their flow token.
    Component {
        id: runC
        Process {
            id: rp
            property var cb: null
            property int exitCode: -1
            property int parts: 0
            function part() { if (++parts < 3) return; const f = cb; cb = null; if (f) f(exitCode, out.text, err.text); rp.destroy() }
            function stop() { cb = null; if (running) running = false; else rp.destroy() }
            stdout: StdioCollector { id: out; onStreamFinished: rp.part() }
            stderr: StdioCollector { id: err; onStreamFinished: rp.part() }
            onExited: code => { exitCode = code; part() }
        }
    }
    property var lookupProc: null
    property var playProc: null
    function spawn(argv, cb) { const p = runC.createObject(pc, { command: argv, cb: cb }); p.running = true; return p }
    function stopRun(p) { if (p) p.stop(); return null }
    Timer { id: lookupWatchdog; interval: pc.lookupMs; property int token: 0; onTriggered: { pc.lookupProc = pc.stopRun(pc.lookupProc); pc.fail(token, "Lookup timed out") } }
    function lookup(token, argv, cb) {
        lookupProc = stopRun(lookupProc)
        lookupProc = spawn(argv, (code, out) => { lookupWatchdog.stop(); pc.lookupProc = null; cb(code, out) })
        lookupWatchdog.token = token
        lookupWatchdog.restart()
    }

    Process {
        command: ["test", "-x", pc.twitchPath]
        running: true
        onExited: code => pc.twitchApp = code === 0
    }

    IpcHandler {
        target: "tvpc"
        function status(): string {
            return JSON.stringify({ phase: pc.phase, error: pc.error, usable: pc.usable, hint: pc.hint, target: pc.target, twitchApp: pc.twitchApp })
        }
        function press(): string { return pc.press() }
        function cancel(): string { pc.cancel(); return "ok" }
        function last(): string { return JSON.stringify(pc.log.length > 0 ? pc.log[pc.log.length - 1] : null) }
    }
}
