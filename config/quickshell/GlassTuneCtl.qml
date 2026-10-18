pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Engine of Settings -> Glass (SettingsGlass.qml is the page): the solid_glass options.
// Applies decoration:blur:solid_glass:* to ONE Hyprland instance with `hyprctl eval 'hl.config{...}'` (keyword
// is not available in the Lua config), reads the real values back with `getoption`, and copies the result as a
// Lua snippet.
//   qs ipc call glasstune set <key> <value> | get <key> | reset <key|all> | copy changed|all | reload | dump
//
// Persistence: the values the user changed are saved (debounced) in glass.json next to appearance.json
// (${XDG_STATE_HOME:-~/.local/state}/quickshell/glass.json, QS_GLASS_FILE overrides the path). Hyprland reads it
// at config load in hypr/hyprland/managed.lua, after settings.lua, so it wins over the hand-written
// solid_glass block (which stays the default for keys never touched here). Only keys that were changed are in the
// file; "reset" saves the built-in default of that key as a change, it does not remove the key.
//
// Instance guard: every hyprctl call gets HYPRLAND_INSTANCE_SIGNATURE explicitly from this process' environment.
// With `nestedOnly` (the dev copy) it refuses to run unless that signature is set, belongs to a compositor this
// shell is a client of (wl_socket == WAYLAND_DISPLAY) and is NOT the live session (wl_socket "wayland-1").
// The real config sets nestedOnly: false and talks to its own (current) instance.
Singleton {
    id: ctl

    property bool nestedOnly: false
    readonly property string liveSocket: "wayland-1"
    // where the Lua snippet goes: the live session's clipboard on purpose (paste into an editor); "" = own display
    readonly property string copyDisplay: nestedOnly ? "wayland-1" : ""

    // ---- options (ConfigValues.cpp is the source of truth) ----
    // curve: slider response exponent (>1 gives the low end more room)
    readonly property var opts: [
        { key: "refraction",         group: "Lens",     label: "Refraction",      min: 0,   max: 48,  def: 28,   dec: 1, unit: "px" },
        { key: "bulb",               group: "Lens",     label: "Bulb",            min: 4,   max: 256, def: 48,   dec: 1, unit: "px", curve: 2 },
        { key: "depth",              group: "Lens",     label: "Depth",           min: 0,   max: 3,   def: 1,    dec: 2 },
        { key: "edge_curve",         group: "Lens",     label: "Edge curve",      min: 0.2, max: 5,   def: 1,    dec: 2 },
        { key: "aberration",         group: "Lens",     label: "Aberration",      min: 0,   max: 0.25, def: 0.05, dec: 3 },
        { key: "light_angle",        group: "Light",    label: "Light angle",     min: 0,   max: 360, def: 135,  dec: 0, unit: "°" },
        { key: "specular_intensity", group: "Light",    label: "Specular",        min: 0,   max: 3,   def: 1,    dec: 2 },
        { key: "specular_power",     group: "Light",    label: "Specular power",  min: 1,   max: 200, def: 48,   dec: 0, curve: 2 },
        { key: "sheen",              group: "Light",    label: "Sheen",           min: 0,   max: 1,   def: 0.14, dec: 2 },
        { key: "clarity",            group: "Material", label: "Clarity",         min: 0,   max: 1,   def: 1,    dec: 2 },
        { key: "frost",              group: "Material", label: "Frost",           min: 0,   max: 16,  def: 3,    dec: 1, unit: "px" },
        { key: "darkening",          group: "Material", label: "Darkening",       min: 0,   max: 1,   def: 0.35, dec: 2 },
        { key: "saturation",         group: "Material", label: "Saturation",      min: 0,   max: 3,   def: 1.25, dec: 2 }
    ]
    readonly property int tintDef: 0x14EEF5FF          // 0xAARRGGBB, alpha = absorption
    readonly property var keys: opts.map(o => o.key).concat(["tint"])

    // current values; replaced as a whole so bindings update
    property var values: defaults()
    function defaults() {
        const v = {}
        for (const o of opts) v[o.key] = o.def
        v.tint = tintDef
        return v
    }
    function spec(key) { return opts.find(o => o.key === key) }
    function clamp(key, x) {
        const o = spec(key)
        if (key === "tint") return Math.max(0, Math.min(0xFFFFFFFF, Math.round(x)))
        const n = Math.max(o.min, Math.min(o.max, x))
        const p = Math.pow(10, o.dec + 1)      // one digit more than shown: slider drags stay smooth
        return Math.round(n * p) / p
    }
    function defOf(key) { return key === "tint" ? tintDef : spec(key).def }
    function isChanged(key) { return Math.abs(values[key] - defOf(key)) > 1e-6 }
    readonly property var changedKeys: keys.filter(k => Math.abs(values[k] - defOf(k)) > 1e-6)

    // pending: keys not yet sent
    property var dirty: ({})
    // keys changed by the user (value saved in glass.json); all of them are applied by managed.lua at config load
    property var overrides: ({})
    property string status: ""          // last result line, for the page
    function set(key, x) {
        if (!ready || keys.indexOf(key) < 0 || typeof x !== "number" || isNaN(x)) return false
        const c = clamp(key, x)
        const v = Object.assign({}, values)
        v[key] = c
        values = v
        const o = Object.assign({}, overrides)
        o[key] = c
        overrides = o
        dirty[key] = true
        throttle.start()
        saver.restart()
        return true
    }
    function reset(key) {
        if (key === "all") { for (const k of keys) set(k, defOf(k)); return true }
        return set(key, defOf(key))
    }

    // ---- instance guard ----
    readonly property string sig: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    // "checking" | "ok" | "error"
    property string guard: "checking"
    property string guardError: ""
    readonly property bool ready: guard === "ok"
    // the running Hyprland has no decoration:blur:solid_glass:* options (stock build)
    property bool unsupported: false
    function fail(msg) { guard = "error"; guardError = msg; status = "" }
    function checkGuard() {
        guard = "checking"
        if (sig === "") { fail("HYPRLAND_INSTANCE_SIGNATURE is not set: refusing to touch any compositor"); return }
        instProc.running = true
    }
    Process {
        id: instProc
        command: ["hyprctl", "instances", "-j"]
        environment: ({ HYPRLAND_INSTANCE_SIGNATURE: ctl.sig })
        stdout: StdioCollector {
            onStreamFinished: {
                let list = []
                try { list = JSON.parse(text) } catch (e) { ctl.fail("hyprctl instances failed"); return }
                const me = list.find(i => i.instance === ctl.sig)
                const wl = Quickshell.env("WAYLAND_DISPLAY") || ""
                if (!me) ctl.fail("instance " + ctl.sig.slice(-12) + " is not running")
                else if (ctl.nestedOnly && me.wl_socket === ctl.liveSocket) ctl.fail("refusing: " + ctl.sig.slice(-12) + " is the LIVE Hyprland (" + me.wl_socket + ")")
                else if (ctl.nestedOnly && me.wl_socket !== wl) ctl.fail("refusing: instance socket " + me.wl_socket + " is not this shell's display (" + wl + ")")
                else { ctl.guard = "ok"; ctl.load() }
            }
        }
    }

    // ---- read back ----
    function load() {
        if (!ready) return
        loadProc.command = ["hyprctl", "-j", "--batch", keys.map(k => "getoption decoration:blur:solid_glass:" + k).join(" ; ")]
        loadProc.running = true
    }
    Process {
        id: loadProc
        environment: ({ HYPRLAND_INSTANCE_SIGNATURE: ctl.sig })
        stdout: StdioCollector {
            onStreamFinished: {
                const v = Object.assign({}, ctl.values)
                const re = /"option":\s*"decoration:blur:solid_glass:([a-z_]+)",\s*"(?:float|int)":\s*(-?[\d.]+)/g
                let m, n = 0
                while ((m = re.exec(text)) !== null) {
                    if (ctl.keys.indexOf(m[1]) < 0) continue
                    let x = Number(m[2])
                    if (m[1] === "tint" && x < 0) x += 4294967296
                    v[m[1]] = x
                    n++
                }
                if (n === 0) {
                    ctl.unsupported = true
                    ctl.fail("this Hyprland has no solid_glass blur (decoration:blur:solid_glass:* missing)")
                    return
                }
                ctl.values = v
                ctl.status = ""
            }
        }
    }

    // ---- apply (throttled, one Process, coalesced) ----
    function fmt(key, x) {
        if (key === "tint") return "0x" + ("00000000" + (x >>> 0).toString(16).toUpperCase()).slice(-8)
        return String(Number(x.toFixed(4)))
    }
    function snippet(onlyChanged) {
        const ks = (onlyChanged ? changedKeys : keys)
        if (ks.length === 0) return "-- all solid_glass options at their defaults"
        const order = keys.filter(k => ks.indexOf(k) >= 0)
        return "hl.config({\n  decoration = {\n    blur = {\n      solid_glass = {\n"
            + order.map(k => "        " + k + " = " + fmt(k, values[k]) + ",\n").join("")
            + "      },\n    },\n  },\n})"
    }
    Timer { id: throttle; interval: 40; onTriggered: ctl.flush() }
    property bool queued: false
    function flush() {
        if (!ready) return
        if (applyProc.running) { queued = true; return }
        const ks = Object.keys(dirty)
        if (ks.length === 0) return
        dirty = ({})
        const body = ks.map(k => k + "=" + fmt(k, values[k])).join(",")
        applyProc.command = ["hyprctl", "eval", "hl.config({decoration={blur={solid_glass={" + body + "}}}})"]
        applyProc.running = true
    }
    Process {
        id: applyProc
        environment: ({ HYPRLAND_INSTANCE_SIGNATURE: ctl.sig })
        stdout: StdioCollector { onStreamFinished: if (text.trim() !== "ok" && text.trim() !== "") ctl.status = "hyprctl: " + text.trim() }
        onExited: if (ctl.queued) { ctl.queued = false; ctl.flush() }
    }

    // ---- clipboard ----
    function copy(onlyChanged) {
        const text = snippet(onlyChanged)
        copyProc.command = ["wl-copy", text]
        copyProc.running = true
        status = "copied " + (onlyChanged ? "changed" : "all") + " to the clipboard" + (copyDisplay ? " (" + copyDisplay + ")" : "")
    }
    Process {
        id: copyProc
        environment: (ctl.copyDisplay ? { WAYLAND_DISPLAY: ctl.copyDisplay } : ({}))
    }

    // ---- persistence ----
    readonly property string stateFile: {
        const env = Quickshell.env("QS_GLASS_FILE")
        return env ? String(env) : Appearance.dir + "/glass.json"
    }
    Timer { id: saver; interval: 500; onTriggered: ctl.save() }
    function save() {
        const o = { version: 1 }
        for (const k of keys) if (overrides[k] !== undefined) o[k] = overrides[k]
        const dir = stateFile.substring(0, stateFile.lastIndexOf("/")) || "/"
        Quickshell.execDetached(["mkdir", "-p", dir])
        store.setText(JSON.stringify(o) + "\n")
    }
    FileView { id: store; path: ctl.stateFile; printErrors: false; blockLoading: true }
    // the saved overrides (what managed.lua applies), read once; the page shows live values from getoption
    function loadSaved() {
        const o = {}
        try {
            const p = JSON.parse(store.text())
            for (const k of keys) if (typeof p[k] === "number" && isFinite(p[k])) o[k] = clamp(k, p[k])
        } catch (e) {}
        overrides = o
    }

    // A config reload (also the one Settings -> Appearance triggers) re-applies glass.json: read the values
    // back, or, while a change is still pending, send the pending state again so the reload cannot undo it.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "configreloaded" || !ctl.ready) return
            if (saver.running || throttle.running || applyProc.running) {
                for (const k of Object.keys(ctl.overrides)) ctl.dirty[k] = true
                throttle.restart()
            } else ctl.load()
        }
    }

    Component.onCompleted: { loadSaved(); checkGuard() }

    IpcHandler {
        target: "glasstune"
        function set(key: string, value: string): string { return ctl.set(key, Number(value)) ? "ok" : "bad key/value" }
        function get(key: string): string { return ctl.values[key] === undefined ? "bad key" : ctl.fmt(key, ctl.values[key]) }
        function reset(key: string): string { return ctl.reset(key) ? "ok" : "bad key" }
        function copy(which: string): void { ctl.copy(which !== "all") }
        function reload(): void { ctl.checkGuard() }
        function dump(): string { return "guard=" + ctl.guard + (ctl.guardError ? " (" + ctl.guardError + ")" : "") + "\n" + ctl.snippet(false) }
    }
}
