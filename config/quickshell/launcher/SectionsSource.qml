import QtQuick
import Quickshell
import Quickshell.Io

// Source: native sub-menus ("sections") of the launcher: Sound output, Sound input, Power, Twitch.
// `items` = the root rows (kind "section"); Launcher.enterSection(name) calls enter(name) (starts loading) and
// then asks rows(name) for the list. Async sections emit updated() when their data arrives.
// Section rows are `transient` + `private` (never in usage.json / history.json). Mirrors the old menus:
//   sound-output / sound-input: (pactl list, current first and ticked,
//     select = set default + move all streams)
//     (twitch-qs-follows lines, select = twitch-qs-mpv watch/login). Twitch tokens are handled inside the
//     twitch-qs-* scripts only; this file never sees them.
//   screenshot / record: the former standalone menus. Rows start hypr/scripts/screenshot.sh <mode> /
//     screenrec.sh <mode> --fps N --format F --audio|--no-audio. The launcher closes first (Launcher.runItem sets
//     shown=false before run()), and the script starts after a short sleep so the layer is unmapped before slurp /
//     the recorder; record also has a "Stop recording" row while one runs (screenrec.sh status) and option rows
//     (frame rate, format, desktop audio) that stay open and save to $XDG_STATE_HOME/quickshell/screenrec.conf.
// Test hooks: $LAUNCHER_TWITCH_DIR replaces ~/code/crossatko/twitch-qs-mpv/bin; $QS_SHOT_SCRIPT / $QS_RECORD_SCRIPT
// replace the capture scripts.
QtObject {
    id: src

    signal updated()

    readonly property var sections: ({
        "sound-output": { title: "Sound output", glyph: "", sub: "Choose the default audio output",
                          aliases: ["speaker", "speakers", "headphones"], words: ["audio", "sink", "output", "volume"] },
        "sound-input":  { title: "Sound input", glyph: "", sub: "Choose the default microphone",
                          aliases: ["mic", "microphone"], words: ["audio", "source", "input"] },
        "power":        { title: "Power", glyph: "", sub: "Sleep, shut down, restart, log out, switch session",
                          aliases: ["shutdown", "reboot", "logout", "suspend"], words: ["poweroff", "restart", "log out", "sleep", "exit", "session"] },
        "twitch":       { title: "Twitch", glyph: "", sub: "Followed channels",
                          aliases: ["stream", "streams"], words: ["live", "channels", "watch"] },
        "screenshot":   { title: "Screenshot", glyph: "\uf030", sub: "Region, window or screen",
                          aliases: ["print", "grab", "snip", "capture"], words: ["screen", "region", "window", "monitor", "image"] },
        "record":       { title: "Record", glyph: "\uf03d", sub: "Screen recording: region, window or screen",
                          aliases: ["screenrec", "video", "screencast", "recording", "capture"], words: ["screen", "region", "window", "monitor", "fps", "audio", "stop"] }
    })

    readonly property var items: Object.keys(sections).map(k => ({
        id: "sec:" + k, name: sections[k].title, subtitle: sections[k].sub, keywords: sections[k].words, aliases: sections[k].aliases,
        kind: "section", source: "Menu", glyph: sections[k].glyph, section: k
    }))

    function title(name) { return sections[name] ? sections[name].title : "" }

    // ---- state ---------------------------------------------------------------------------------------------
    property var outRows: []
    property var inRows: []
    property bool outLoading: false
    property bool inLoading: false
    property string outError: ""
    property string inError: ""
    property var twitchRows: []
    property bool twitchLoading: false
    property string twitchError: ""

    function enter(name) {
        if (name === "record") { Quickshell.execDetached(["mkdir", "-p", src.prefsDir]); prefs.reload(); recording = false; statusProc.running = false; statusProc.running = true }
        if (name === "sound-output") { outRows = []; outError = ""; outLoading = true; outProc.running = false; outProc.running = true }
        else if (name === "sound-input") { inRows = []; inError = ""; inLoading = true; inProc.running = false; inProc.running = true }
        else if (name === "twitch") { twitchRows = []; twitchError = ""; twitchLoading = true; twitchProc.running = false; twitchProc.running = true }
    }

    function info(id, name, sub, glyph) {
        return { id: "sec:" + id, name: name, subtitle: sub, kind: "info", source: "", glyph: glyph, transient: true, private: true }
    }

    function rows(name) {
        if (name === "sound-output") return audioRows(outLoading, outError, outRows, "No output devices found")
        if (name === "sound-input") return audioRows(inLoading, inError, inRows, "No input devices found")
        if (name === "power") return powerRows
        if (name === "screenshot") return shotRows
        if (name === "record") return recordRows()
        if (name === "twitch") {
            if (twitchLoading) return [info("loading", "Loading followed channels...", "", "")]
            if (twitchError !== "") return [info("error", "Could not load Twitch", twitchError, "")]
            return twitchRows
        }
        return []
    }

    function audioRows(loading, error, list, empty) {
        if (loading) return [info("loading", "Loading devices...", "", "")]
        if (error !== "") return [info("error", "Could not list devices", error, "")]
        if (list.length === 0) return [info("empty", empty, "", "")]
        return list
    }

    // ---- sound (pactl) ---------------------------------------------------------------------------------------
    function shortName(v) {
        return v.replace(/ \(.*/, "").replace(/ Analog Stereo.*/, "").replace(/ Digital Stereo.*/, "").replace(/ Headphones \/.*/, "")
    }

    // `pactl list sinks|sources` text -> rows, current default first (like the awk in the old scripts); monitors dropped for sources
    function parseAudio(text, current, kind) {
        const cur = [], rest = []
        for (const blk of text.split(/\n\s*\n/)) {
            let name = "", desc = ""
            for (const line of blk.split("\n")) {
                let m = /^\s*Name: (.*)$/.exec(line); if (m) name = m[1]
                m = /^\s*Description: (.*)$/.exec(line); if (m) desc = m[1]
            }
            if (name === "" || (kind === "sound-in" && /\.monitor$/.test(name))) continue
            const isCur = name === current
            const row = {
                id: "sec:" + kind + ":" + name, name: shortName(desc === "" ? name : desc),
                subtitle: isCur ? "Current default" : "", kind: kind, source: isCur ? "Default" : "",
                glyph: isCur ? "" : (kind === "sound-in" ? "" : ""),
                transient: true, private: true, device: name
            };
            (isCur ? cur : rest).push(row)
        }
        return cur.concat(rest)
    }

    function failText(err, code) {
        const l = (err || "").trim().split("\n")[0]
        return l !== "" ? l : "exit code " + code
    }

    property var outProc: Process {
        command: ["sh", "-c", "cur=$(pactl get-default-sink 2>/dev/null); printf '%s\\n' \"$cur\"; pactl list sinks"]
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector { id: outOut }
        stderr: StdioCollector { id: outErr }
        onExited: code => {
            src.outLoading = false
            if (code !== 0) src.outError = src.failText(outErr.text, code)
            else {
                const t = outOut.text, i = t.indexOf("\n")
                src.outRows = src.parseAudio(t.slice(i + 1), t.slice(0, i), "sound-out")
            }
            src.updated()
        }
    }
    property var inProc: Process {
        command: ["sh", "-c", "cur=$(pactl get-default-source 2>/dev/null); printf '%s\\n' \"$cur\"; pactl list sources"]
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector { id: inOut }
        stderr: StdioCollector { id: inErr }
        onExited: code => {
            src.inLoading = false
            if (code !== 0) src.inError = src.failText(inErr.text, code)
            else {
                const t = inOut.text, i = t.indexOf("\n")
                src.inRows = src.parseAudio(t.slice(i + 1), t.slice(0, i), "sound-in")
            }
            src.updated()
        }
    }

    // ---- power -----------------------------------------------------
    function power(id, name, sub, glyph, command, confirm) {
        return { id: "sec:power:" + id, name: name, subtitle: sub, kind: "power", source: "", glyph: glyph,
                 transient: true, private: true, confirm: confirm, command: command }
    }
    readonly property var powerRows: [
        power("sleep", "Sleep", "Suspend the computer", "", "~/.config/hypr/scripts/suspend.sh", false),
        power("shutdown", "Shut down", "Power off", "", "hyprshutdown -t 'Shutting down...' --post-cmd 'shutdown now'", true),
        power("reboot", "Restart", "Reboot the computer", "", "hyprshutdown -t 'Restarting...' --post-cmd 'reboot'", true),
        power("exit", "Exit Hyprland", "End the session", "", "hyprshutdown", true),
        power("gamescope", "Switch to Gamescope", "Log out into the Gamescope session", "",
              "echo gamescope > ~/.local/state/next-session && hyprshutdown -t 'Switching to Gamescope...'", true),
        power("kde", "Switch to KDE", "Log out into the KDE session", "",
              "echo kde > ~/.local/state/next-session && hyprshutdown -t 'Switching to KDE...'", true)
    ]

    // ---- twitch (twitch-qs-follows lines: "Name: game [viewers]<TAB>login") -----------------------------------------
    readonly property string twitchDir: Quickshell.env("LAUNCHER_TWITCH_DIR") || (Quickshell.env("HOME") + "/code/crossatko/twitch-qs-mpv/bin")

    function parseTwitch(text) {
        const out = []
        for (const line of text.split("\n")) {
            const t = line.indexOf("\t")
            if (t < 0) continue
            const label = line.slice(0, t), login = line.slice(t + 1).trim()
            if (login === "__none__") { out.push(info("none", label, "Check the network and try again", "")); continue }
            if (login === "__login__") {
                out.push({ id: "sec:twitch:login", name: "Log in to Twitch", subtitle: label, kind: "twitch-login", source: "",
                           glyph: "", transient: true, private: true })
                continue
            }
            if (!/^[A-Za-z0-9_]{2,25}$/.test(login)) continue
            const c = label.indexOf(": ")
            const name = c > 0 ? label.slice(0, c) : label, rest = c > 0 ? label.slice(c + 2) : ""
            const offline = /\[offline\]/.test(rest)
            out.push({ id: "sec:twitch:" + login, name: name, subtitle: rest, kind: "twitch", source: offline ? "" : "Live",
                       glyph: "", iconColor: offline ? "muted" : "red", transient: true, private: true, login: login })
        }
        return out
    }

    property var twitchProc: Process {
        command: [src.twitchDir + "/twitch-qs-follows"]
        stdout: StdioCollector { id: twOut }
        stderr: StdioCollector { id: twErr }
        onExited: code => {
            src.twitchLoading = false
            const rows = code === 0 ? src.parseTwitch(twOut.text) : []
            if (code !== 0) src.twitchError = src.failText(twErr.text, code)
            else if (rows.length === 0) src.twitchError = "No followed channels returned"
            else src.twitchRows = rows
            src.updated()
        }
    }

    // ---- screenshot / record (the former standalone menus) -------------------------------------------
    readonly property string shotScript: Quickshell.env("QS_SHOT_SCRIPT") || (Quickshell.env("HOME") + "/.config/hypr/scripts/screenshot.sh")
    readonly property string recScript: Quickshell.env("QS_RECORD_SCRIPT") || (Quickshell.env("HOME") + "/.config/hypr/scripts/screenrec.sh")
    readonly property string prefsDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell"
    readonly property real launchDelay: 0.25     // seconds between the launcher closing and the capture starting (old menus: 200 ms)

    readonly property var captureModes: [
        { id: "region", name: "Region", sub: "Drag a rectangle", glyph: "\uf125" },
        { id: "window", name: "Window", sub: "Click a window",   glyph: "\uf2d0" },
        { id: "output", name: "Screen", sub: "Whole monitor",    glyph: "\uf108" }
    ]
    property int lastShot: 0                     // the sections reopen on the last used mode
    property int lastRec: 0
    property int fps: 60                         // saved choices (screenrec.conf, shared with screenrec.sh)
    property string format: "mp4"
    property bool audio: false
    property bool recording: false

    function modeRows(kind, prefix, verb) {
        return captureModes.map((m, i) => ({ id: "sec:" + prefix + ":" + m.id, name: m.name, subtitle: m.sub, kind: kind, source: "",
                                             glyph: m.glyph, transient: true, private: true, mode: m.id, modeIndex: i }))
    }
    readonly property var shotRows: modeRows("shot", "shot")
    function recordRows() {
        const out = []
        if (recording)
            out.push({ id: "sec:rec:stop", name: "Stop recording", subtitle: "A recording is running", kind: "rec-stop", source: "Recording",
                       glyph: "\uf04d", iconColor: "red", transient: true, private: true })
        const modes = modeRows("rec", "rec")
        for (const m of modes) out.push(m)
        out.push({ id: "sec:rec:opt:fps", name: "Frame rate", subtitle: "Enter switches between 30 and 60", kind: "rec-opt", opt: "fps",
                   source: fps + " fps", glyph: "\uf008", transient: true, private: true })
        out.push({ id: "sec:rec:opt:format", name: "Format", subtitle: "Enter switches between MP4 and WebM", kind: "rec-opt", opt: "format",
                   source: format === "mp4" ? "MP4" : "WebM", glyph: "\uf1c8", transient: true, private: true })
        out.push({ id: "sec:rec:opt:audio", name: "Record desktop audio", subtitle: "Enter turns it " + (audio ? "off" : "on"), kind: "rec-opt", opt: "audio",
                   source: audio ? "On" : "Off", glyph: audio ? "\uf028" : "\uf026", transient: true, private: true })
        return out
    }
    // row to highlight when a section opens: the last used mode (after the Stop row while recording)
    function startSel(name) {
        if (name === "screenshot") return lastShot
        if (name === "record") return lastRec + (recording ? 1 : 0)
        return 0
    }

    function setOption(opt) {
        if (opt === "fps") fps = fps === 60 ? 30 : 60
        else if (opt === "format") format = format === "mp4" ? "webm" : "mp4"
        else if (opt === "audio") audio = !audio
        saver.restart()
    }

    // run a capture script after the launcher is gone (Launcher.runItem has already hidden the layer)
    function later(argv) { Quickshell.execDetached(["sh", "-c", "sleep " + launchDelay + "; exec \"$@\"", "sh"].concat(argv)) }

    property var statusProc: Process {
        command: [src.recScript, "status"]
        onExited: code => { src.recording = code === 0; src.updated() }
    }
    property var saver: Timer {
        interval: 400
        onTriggered: prefs.setText("fps=" + src.fps + "\nformat=" + src.format + "\naudio=" + (src.audio ? 1 : 0) + "\n")
    }
    property var prefs: FileView {
        path: src.prefsDir + "/screenrec.conf"
        printErrors: false
        onLoaded: {
            for (const line of text().split("\n")) {
                const i = line.indexOf("=")
                if (i < 0) continue
                const k = line.slice(0, i).trim(), v = line.slice(i + 1).trim()
                if (k === "fps" && ["30", "60"].includes(v)) src.fps = parseInt(v)
                else if (k === "format" && ["mp4", "webm"].includes(v)) src.format = v
                else if (k === "audio" && (v === "0" || v === "1")) src.audio = v === "1"
            }
            src.updated()
        }
    }

    // ---- run -------------------------------------------------------------------------------------------------
    function run(item) {
        if (item.kind === "sound-out" || item.kind === "sound-in") {
            const out = item.kind === "sound-out"
            const setCmd = out ? "set-default-sink" : "set-default-source"
            const listCmd = out ? "sink-inputs" : "source-outputs"
            const moveCmd = out ? "move-sink-input" : "move-source-output"
            Quickshell.execDetached(["sh", "-c",
                "pactl " + setCmd + " \"$1\"; pactl list short " + listCmd + " | cut -f1 | while read -r i; do " +
                "[ -n \"$i\" ] && pactl " + moveCmd + " \"$i\" \"$1\"; done", "sh", item.device])
            return true
        }
        if (item.kind === "shot") { lastShot = item.modeIndex; later([shotScript, item.mode]); return true }
        if (item.kind === "rec") {
            lastRec = item.modeIndex
            later([recScript, item.mode, "--fps", String(fps), "--format", format, audio ? "--audio" : "--no-audio"])
            return true
        }
        if (item.kind === "rec-stop") { Quickshell.execDetached([recScript, "stop"]); return true }
        if (item.kind === "rec-opt") { setOption(item.opt); return true }
        if (item.kind === "power") { Quickshell.execDetached(["sh", "-c", item.command]); return true }
        if (item.kind === "twitch") {
            Quickshell.execDetached(["env", "TWITCH_QS_FONT=Paper Mono", src.twitchDir + "/twitch-qs-mpv", "watch", item.login])
            return true
        }
        if (item.kind === "twitch-login") {
            Quickshell.execDetached(["env", "TWITCH_QS_FONT=Paper Mono", src.twitchDir + "/twitch-qs-mpv", "login"])
            return true
        }
        return false
    }
}
