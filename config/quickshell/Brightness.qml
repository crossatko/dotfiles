pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Screen brightness, one backend for the control center sliders and the brightness keys / OSD.
//   external monitors: DDC/CI via ddcutil (set through ~/.config/hypr/scripts/ddc-set-brightness.sh, which retries)
//   built-in panel:    brightnessctl, only where it is installed
// bin/brightness-detect lists the controllable displays; it is re-run on every refresh() (the control center
// calls it each time it opens) because the I2C bus numbers can shift at runtime, and because other writers
// (steam-tv-dim.lua, hypridle) change the brightness behind our back -- re-reading on open picks that up.
// DDC is slow (~0.2-1 s per call), so every display has one worker Process: calls are serialised per display,
// never block the UI, and while one is in flight only the newest requested value is kept (coalescing = throttle).
// Values are percent (0..100); set() never goes below minPercent so a slider can't black a screen out.
// QS_BRIGHTNESS_DETECT overrides the detect script (tests).
Singleton {
    id: br

    readonly property int minPercent: 1
    readonly property string setScript: Quickshell.env("HOME") + "/.config/hypr/scripts/ddc-set-brightness.sh"
    readonly property string detectScript: Quickshell.env("QS_BRIGHTNESS_DETECT") || (Quickshell.shellDir + "/bin/brightness-detect")

    property var values: ({})            // connector -> percent: last read, or last requested
    property var names: []               // connectors that answered a read (unsupported ones never get in)
    property var workers: ({})           // connector -> worker Process
    property bool detecting: false
    property var queuedSteps: []         // key presses that arrived before the first detection finished

    // what the UI shows: displays Quickshell has a screen for (or a built-in panel), top-to-bottom, left-to-right
    readonly property var displays: {
        const scr = Quickshell.screens
        const pos = n => scr.find(s => s.name === n)
        return names.filter(n => pos(n) || (workers[n] && workers[n].kind === "bl"))
                    .sort((a, b) => { const A = pos(a), B = pos(b); return !A || !B ? 0 : (A.y - B.y) || (A.x - B.x) })
    }
    readonly property bool available: displays.length > 0

    signal stepped(string name, int percent)     // the keys changed a display (the OSD shows it)

    function percentOf(name) { return values[name] !== undefined ? values[name] : 0 }

    // the display the keys act on: the focused monitor if we control it, else the first one
    function focused() {
        const m = Popups.focusedName()
        return displays.indexOf(m) >= 0 ? m : displays.indexOf(Monitors.primaryName) >= 0 ? Monitors.primaryName : (displays.length ? displays[0] : "")
    }

    function refresh() {
        if (detecting) return
        detecting = true
        detect.running = true
    }

    function set(name, percent) {
        const w = workers[name]
        if (!w) return
        const p = Math.max(minPercent, Math.min(100, Math.round(percent)))
        _store(name, p)
        w.want = p
        _pump(w)
    }

    // relative change for the keys; reads first when our value may be stale (something else may have set it)
    function step(delta) {
        const m = Popups.focusedName()
        const name = displays.length ? focused() : (workers[m] ? m : Object.keys(workers)[0])
        const w = name ? workers[name] : null
        if (!w) { queuedSteps = queuedSteps.concat([delta]); refresh(); return }
        const apply = () => { set(name, percentOf(name) + delta); stepped(name, percentOf(name)) }
        if (!w.ok || (w.want < 0 && w.op !== "set" && Date.now() - w.readAt > 15000)) {
            w.after = w.after.concat([apply])
            w.wantRead = true
            _pump(w)
        } else apply()
    }

    function _store(name, p) {
        const v = Object.assign({}, values); v[name] = p; values = v
    }
    function _setNames(list) {
        if (list.join(" ") !== names.join(" ")) names = list
    }

    function _pump(w) {
        if (w.running) return
        if (w.want >= 0) {
            const p = w.want
            w.want = -1
            w.op = "set"
            const raw = String(Math.round(p / 100 * w.max))
            w.command = w.kind === "ddc"
                ? ["sh", "-c", 'bash "$0" "$1" "$2" && echo OK', setScript, w.dev, raw]
                : ["sh", "-c", 'brightnessctl -q -d "$0" set "$1" && echo OK', w.dev, raw]
            w.running = true
        } else if (w.wantRead) {
            w.wantRead = false
            w.op = "read"
            w.command = w.kind === "ddc"
                ? ["sh", "-c", 'ddcutil --bus "$0" getvcp 10 --brief 2>/dev/null', w.dev]
                : ["sh", "-c", 'brightnessctl -m -d "$0" 2>/dev/null', w.dev]
            w.running = true
        }
    }

    function _done(w, text) {
        const op = w.op
        w.op = ""
        if (op === "read") {
            let cur = NaN, max = NaN
            if (w.kind === "ddc") {
                const m = /VCP\s+10\s+C\s+(\d+)\s+(\d+)/.exec(text)
                if (m) { cur = +m[1]; max = +m[2] }
            } else {
                const f = text.trim().split("\n")[0].split(",")     // device,class,current,percent,max
                if (f.length >= 5) { cur = +f[2]; max = +f[4] }
            }
            if (!isNaN(cur) && max > 0) {
                w.max = max
                w.ok = true
                w.readAt = Date.now()
                if (w.want < 0) _store(w.disp, Math.round(cur / max * 100))   // a newer slider value wins
                if (names.indexOf(w.disp) < 0) _setNames(names.concat([w.disp]).sort())
            } else if (!w.ok) {
                // no DDC brightness here (or the monitor refused): leave it out, quietly
                _setNames(names.filter(n => n !== w.disp))
            }
            const cbs = w.after
            w.after = []
            if (w.ok) cbs.forEach(f => f())
        } else if (op === "set" && text.indexOf("OK") < 0) {
            refresh()                       // the bus may have moved; the next detection re-points the worker
        }
        _pump(w)
    }

    function _detected(text) {
        detecting = false
        const seen = {}
        const ws = Object.assign({}, workers)
        text.split("\n").forEach(line => {
            const f = line.trim().split(/\s+/)
            if (f.length < 3 || (f[0] !== "ddc" && f[0] !== "bl")) return
            const name = f[2]
            seen[name] = true
            let w = ws[name]
            if (!w) {
                w = workerComp.createObject(br, { disp: name, kind: f[0], dev: f[1] })
                ws[name] = w
            } else {
                w.kind = f[0]
                w.dev = f[1]
            }
            if (w.want < 0 && w.op !== "set") w.wantRead = true
        })
        for (const n in ws) {
            if (!seen[n] && !ws[n].running) { ws[n].destroy(); delete ws[n] }
        }
        workers = ws
        _setNames(names.filter(n => seen[n]))
        for (const n in ws) _pump(ws[n])
        if (queuedSteps.length) {
            const q = queuedSteps
            queuedSteps = []
            if (Object.keys(ws).length) q.forEach(d => step(d))     // retried once workers exist; dropped otherwise
        }
    }

    Process {
        id: detect
        command: ["sh", "-c", '"$0" 2>/dev/null', br.detectScript]
        stdout: StdioCollector { onStreamFinished: br._detected(text) }
    }

    Component {
        id: workerComp
        Process {
            id: w
            property string disp
            property string kind               // "ddc" | "bl"
            property string dev                // I2C bus number or backlight device
            property int max: 100
            property bool ok: false            // answered a read at least once
            property double readAt: 0
            property int want: -1              // percent waiting to be written (only the newest is kept)
            property bool wantRead: false
            property string op: ""             // what is running: "set" | "read"
            property var after: []             // callbacks for when the next read lands
            stdout: StdioCollector { onStreamFinished: br._done(w, text) }
        }
    }
}
