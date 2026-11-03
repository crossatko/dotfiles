pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Engine of Settings > Look & feel > Blur (BlurSection.qml): which decoration:blur:variant is active and the options of
// every stock Hyprland v0.57 blur variant (kawase, frost, ripple, drops, water, fluid_jar, prism, heat_shimmer, acrylic,
// aurora, haze) plus the shared blur options. The fork's solid_glass is a variant here too, but its options stay in
// GlassTuneCtl / GlassAdvanced.
//   qs ipc call blurtune variant <name> | set <key> <value> | get <key> | reset <variant|shared|key> | dump
// The table `opts` is the whole description (ConfigValues.cpp of v0.57 is the source of truth): a variant is one table
// entry in `variants` plus its option rows in `opts` (`v` = the variants an option belongs to, [] = every variant).
// Everything the running Hyprland lacks is hidden: the batch `getoption` probe (load) fills `present`; an option or
// variant that is missing there is never shown nor sent (older fork builds know fewer variants, stock lacks solid_glass).
// Live: `hyprctl eval 'hl.config{...}'` (throttled, same instance guard as GlassTuneCtl, whose `reachable` / `sig` this
// uses). Persistence: GlassTuneCtl.blur = glass.json's "blur" object, {"variant": "acrylic", "acrylic:refraction": 30,
// "size": 6, ...} (keys = the option path under decoration:blur: with ":", bools 0 / 1, colours AARRGGBB), applied at config
// load by hypr/hyprland/managed.lua (M.apply_blur, which mirrors the names and ranges here). Only what the user touched is
// stored; a reset stores the upstream default as a change (as GlassTuneCtl does), except for a colour: its reset removes
// the key, so the theme colour (managed.lua / blurweather.lua COLOURS) applies again, and only a stored colour counts as
// changed. `variant` is the SAVED variant (glass.json, else the live one when nothing is saved): Weather blur
// (WeatherBlur.qml) is a layer on top that changes only the live variant (`liveVariant`, `weatherOverride`).
// After every live change managed.lua recolours the group bar (global `blur_variant_changed`: blur on / off and the
// variant decide its glass fills) and, after a variant change or a colour reset, fills in the theme colours;
// `Theme.checkGlass()` re-reads the glass test (Theme.glass = solid_glass only).
Singleton {
    id: ctl

    // ---- variants ----
    // value = decoration:blur:variant enum; probe = an option only that variant's build has ("" = always there)
    readonly property var variants: [
        { id: "kawase",       value: 0,  label: "Kawase",       probe: "",                       note: "Plain dual Kawase blur, the Hyprland default." },
        { id: "frost",        value: 1,  label: "Frost",        probe: "glass:refraction",       note: "Frosted glass: a refracting pattern over the blur." },
        { id: "ripple",       value: 2,  label: "Ripple",       probe: "ripple:strength",        note: "Clicks send refracting ripples through the blur." },
        { id: "drops",        value: 3,  label: "Drops",        probe: "drops:speed",            note: "Animated water drops. Costs GPU while animated." },
        { id: "water",        value: 4,  label: "Water",        probe: "water:strength",         note: "The pointer disturbs the blur like water." },
        { id: "fluid_jar",    value: 5,  label: "Fluid jar",    probe: "fluid_jar:color",        note: "A tinted fluid sloshes behind the window." },
        { id: "prism",        value: 6,  label: "Prism",        probe: "glass:refraction",       note: "Triangular prism refraction." },
        { id: "heat_shimmer", value: 7,  label: "Heat shimmer", probe: "heat_shimmer:speed",     note: "A rising heat haze. Animated." },
        { id: "acrylic",      value: 8,  label: "Acrylic",      probe: "acrylic:refraction",     note: "Fluent acrylic: curved lens edge, tint and noise." },
        { id: "aurora",       value: 9,  label: "Aurora",       probe: "aurora:speed",           note: "Slow aurora curtains in two colours." },
        { id: "haze",         value: 10, label: "Haze",         probe: "haze:intensity",         note: "Pearlescent, colour-shifting sheen." },
        { id: "solid_glass",  value: 11, label: "Solid glass",  probe: "solid_glass:refraction", note: "The fork's liquid glass. Tuned under Glass > Customise." }
    ]
    function variantById(id) { return variants.find(v => v.id === id) }
    function variantByValue(n) { return variants.find(v => v.value === n) }
    // variants this Hyprland has (probed); kawase is always there
    readonly property var available: variants.filter(v => v.probe === "" ? true : present[v.probe] === true)

    // ---- options ----
    // kind float | int | bool | color; curve: slider response exponent (>1 gives the low end more room)
    readonly property var opts: {
        const out = []
        const f = (key, v, label, min, max, def, extra) => out.push(Object.assign({ key: key, v: v, kind: "float", group: "", label: label, min: min, max: max, def: def, dec: 2 }, extra || {}))
        const b = (key, group, label, def) => out.push({ key: key, v: [], kind: "bool", group: group, label: label, min: 0, max: 1, def: def ? 1 : 0, dec: 0 })
        const c = (key, v, label, def) => out.push({ key: key, v: v, kind: "color", group: "", label: label, min: 0, max: 4294967295, def: def, dec: 0 })
        const glass = ["frost", "prism", "drops", "heat_shimmer", "aurora"]
        // shared by every variant (all of them run on the dual Kawase pass)
        b("enabled", "Blur", "Blur", true)
        f("size", [], "Size", 0, 100, 8, { group: "Blur", kind: "int", dec: 0, unit: "px" })
        f("passes", [], "Passes", 0, 10, 1, { group: "Blur", kind: "int", dec: 0 })
        f("noise", [], "Noise", 0, 1, 0.0117, { group: "Colour", dec: 3 })
        f("contrast", [], "Contrast", 0, 2, 0.8916, { group: "Colour", dec: 3 })
        f("brightness", [], "Brightness", 0, 2, 1, { group: "Colour" })
        f("vibrancy", [], "Vibrancy", 0, 1, 0.1696, { group: "Colour", dec: 3 })
        f("vibrancy_darkness", [], "Vibrancy in darks", 0, 1, 0, { group: "Colour" })
        b("ignore_opacity", "Behaviour", "Ignore window opacity", true)
        b("new_optimizations", "Behaviour", "Optimisations", true)
        b("xray", "Behaviour", "X-ray (floating ignore tiled)", false)
        b("proportional", "Behaviour", "Strength follows opacity", false)
        b("special", "Behaviour", "Blur special workspace", false)
        b("popups", "Popups", "Blur popups", false)
        f("popups_ignorealpha", [], "Popups ignore alpha", 0, 1, 0.2, { group: "Popups" })
        b("input_methods", "Popups", "Blur input methods", false)
        f("input_methods_ignorealpha", [], "Input methods ignore alpha", 0, 1, 0.2, { group: "Popups" })
        // glass relief shared by frost, prism, drops, heat_shimmer and aurora
        f("glass:refraction", glass, "Refraction", 0, 20, 20, { dec: 1, unit: "px" })
        f("glass:size", ["frost", "prism"], "Pattern size", 4, 512, 40, { dec: 0, unit: "px", curve: 2 })
        f("glass:roughness", glass, "Roughness", 0, 1, 1)
        // acrylic
        f("acrylic:refraction", ["acrylic"], "Refraction", 0, 48, 24, { dec: 1, unit: "px" })
        f("acrylic:bulb", ["acrylic"], "Bulb", 4, 256, 48, { dec: 0, unit: "px", curve: 2 })
        f("acrylic:clarity", ["acrylic"], "Clarity", 0, 1, 0.82)
        f("acrylic:aberration", ["acrylic"], "Aberration", 0, 0.25, 0.025, { dec: 3 })
        c("acrylic:tint", ["acrylic"], "Tint", 0x14EEF5FF)
        // animated ones
        f("drops:speed", ["drops"], "Speed", 0, 10, 3, { dec: 1 })
        f("heat_shimmer:speed", ["heat_shimmer"], "Speed", 0, 10, 1, { dec: 1 })
        f("aurora:speed", ["aurora"], "Speed", 0, 10, 1, { dec: 1 })
        f("aurora:intensity", ["aurora"], "Intensity", 0, 1, 0.35)
        c("aurora:color1", ["aurora"], "Curtain 1", 0x29F0A0FF)
        c("aurora:color2", ["aurora"], "Curtain 2", 0x7A4DFFFF)
        f("haze:intensity", ["haze"], "Intensity", 0, 1, 0.35)
        f("haze:iridescence", ["haze"], "Iridescence", 0, 1, 0.7)
        f("ripple:strength", ["ripple"], "Strength", 0, 32, 30, { dec: 1, unit: "px" })
        f("ripple:radius", ["ripple"], "Radius", 1, 1000, 400, { dec: 0, unit: "px", curve: 2 })
        f("ripple:width", ["ripple"], "Wave width", 1, 200, 32, { dec: 0, unit: "px" })
        f("ripple:duration", ["ripple"], "Duration", 0.05, 5, 0.45, { unit: " s" })
        f("water:strength", ["water"], "Strength", 0, 32, 32, { dec: 1, unit: "px" })
        f("water:radius", ["water"], "Pointer radius", 1, 1000, 20, { dec: 0, unit: "px", curve: 2 })
        f("water:speed", ["water"], "Wave speed", 0, 10, 0.76)
        f("water:damping", ["water"], "Damping", 0, 1, 0.95)
        f("water:duration", ["water"], "Duration", 0.5, 60, 12, { dec: 1, unit: " s", curve: 2 })
        c("fluid_jar:color", ["fluid_jar"], "Fluid colour", 0xCC3399FF)
        f("fluid_jar:speed", ["fluid_jar"], "Speed", 0, 10, 3.7, { dec: 1 })
        f("fluid_jar:fill_amount", ["fluid_jar"], "Fill", 0, 1, 0.5)
        f("fluid_jar:mass", ["fluid_jar"], "Mass", 0.1, 10, 1.4, { curve: 2 })
        f("fluid_jar:precision", ["fluid_jar"], "Precision", 0.5, 8, 2, { dec: 1 })
        f("fluid_jar:turbulence", ["fluid_jar"], "Turbulence", 0, 5, 1.2)
        f("fluid_jar:distortion", ["fluid_jar"], "Distortion", 0, 10, 8, { dec: 1 })
        return out
    }
    readonly property var sharedGroups: ["Blur", "Colour", "Behaviour", "Popups"]
    function spec(key) { return opts.find(o => o.key === key) }
    // the options of one variant that this Hyprland has, in table order; shared = the ones every variant has
    function variantOpts(id) { return opts.filter(o => o.v.indexOf(id) >= 0 && present[o.key] === true) }
    function sharedOpts(group) { return opts.filter(o => o.v.length === 0 && o.group === group && present[o.key] === true) }
    readonly property var sharedAny: opts.filter(o => o.v.length === 0 && present[o.key] === true)

    function clamp(key, x) {
        const o = spec(key)
        const n = Math.max(o.min, Math.min(o.max, x))
        if (o.kind === "bool" || o.kind === "int" || o.kind === "color") return Math.round(n)
        const p = Math.pow(10, o.dec + 1)      // one digit more than shown: slider drags stay smooth
        return Math.round(n * p) / p
    }
    function defOf(key) { return spec(key).def }
    // a colour's live value is usually the theme's (not the upstream default): it is changed only while glass.json holds it
    function isChanged(key) {
        if (spec(key).kind === "color") return overrides[key] !== undefined
        return Math.abs((values[key] ?? defOf(key)) - defOf(key)) > 1e-6
    }
    function changedCount(list) { return list.filter(o => isChanged(o.key)).length }

    // ---- state ----
    property var present: ({})           // option key -> true when getoption knows it (filled by the probe)
    property var values: defaults()      // live values
    property string liveVariant: ""      // id of the variant Hyprland runs ("" until read; can be the weather's)
    // the variant this page shows and edits: the saved one, else (nothing saved) the live one
    readonly property string variant: variantSaved && savedVariant !== "" ? savedVariant : liveVariant
    // Weather blur runs another variant than the saved one right now (shown as a note, never edited here)
    // (nothing saved: `variant` is the live one, so the base is unknown and the note shows whenever Weather blur is usable)
    readonly property bool weatherOverride: WeatherBlur.usable && liveVariant !== "" && (!variantSaved || liveVariant !== variant)
    property bool known: false           // the probe answered
    function defaults() {
        const v = {}
        for (const o of opts) v[o.key] = o.def
        return v
    }
    // pending (not yet sent) keys, and the saved object (GlassTuneCtl.blur)
    property var dirty: ({})
    property bool variantDirty: false
    readonly property var saved: GlassTuneCtl.blur
    readonly property bool ready: GlassTuneCtl.reachable && known
    property string status: ""

    function persist() {
        const o = {}
        if (savedVariant !== "" && variantSaved) o.variant = savedVariant     // never the live one: the weather may have set it
        for (const k of Object.keys(overrides)) o[k] = overrides[k]
        GlassTuneCtl.setBlur(o)
    }
    property var overrides: ({})
    property bool variantSaved: false
    property string savedVariant: ""     // the variant glass.json holds (the live `variant` can be the weather's)

    function set(key, x) {
        if (!ready || !spec(key) || present[key] !== true || typeof x !== "number" || isNaN(x)) return false
        const c = clamp(key, x)
        const v = Object.assign({}, values)
        v[key] = c
        values = v
        const o = Object.assign({}, overrides)
        o[key] = c
        overrides = o
        if (unsetColours.indexOf(key) >= 0) unsetColours = unsetColours.filter(k => k !== key)   // set after a reset in one flush window
        dirty[key] = true
        throttle.start()
        persist()
        return true
    }
    // a colour goes back to "not set by the user" (the theme colour); everything else to the upstream default
    property var unsetColours: []        // colour keys reset since the last flush (managed.lua re-themes them)
    function reset(key) {
        const o = spec(key)
        if (!o || o.kind !== "color") return set(key, defOf(key))
        if (!ready || present[key] !== true) return false
        const ov = Object.assign({}, overrides)
        delete ov[key]
        overrides = ov
        delete dirty[key]
        if (unsetColours.indexOf(key) < 0) unsetColours = unsetColours.concat([key])
        throttle.start()
        persist()
        return true
    }
    // "shared" = every shared option, otherwise a variant id
    function resetGroup(which) {
        const list = which === "shared" ? sharedAny : variantOpts(which)
        for (const o of list) reset(o.key)
    }
    function setVariant(id) {
        const vr = variantById(id)
        if (!ready || !vr || available.indexOf(vr) < 0) return false
        savedVariant = id
        variantSaved = true
        variantDirty = present["variant"] === true    // Hyprland 0.56 has no decoration:blur:variant: the choice is only saved
        throttle.start()
        persist()
        return true
    }

    // ---- probe ----
    function probeKeys() { return opts.map(o => o.key).concat(variants.filter(v => v.probe !== "" && !opts.some(o => o.key === v.probe)).map(v => v.probe)) }
    function load() {
        if (!GlassTuneCtl.reachable) return
        loadProc.command = ["hyprctl", "-j", "--batch", ["decoration:blur:variant"].concat(probeKeys().map(k => "decoration:blur:" + k)).map(k => "getoption " + k).join(" ; ")]
        loadProc.running = true
    }
    Process {
        id: loadProc
        environment: ({ HYPRLAND_INSTANCE_SIGNATURE: GlassTuneCtl.sig })
        stdout: StdioCollector {
            onStreamFinished: {
                const v = Object.assign({}, ctl.values)
                const pr = {}
                let vid = ""
                const re = /"option":\s*"decoration:blur:([a-z_0-9:]+)",\s*"(float|int|bool)":\s*(-?[\w.]+)/g
                let m
                while ((m = re.exec(text)) !== null) {
                    pr[m[1]] = true
                    let x = m[3] === "true" ? 1 : m[3] === "false" ? 0 : Number(m[3])
                    if (m[1] === "variant") { const vr = ctl.variantByValue(x); vid = vr ? vr.id : ""; continue }
                    if (!ctl.spec(m[1])) continue
                    if (x < 0) x += 4294967296      // colours come back as unsigned, be safe
                    v[m[1]] = x
                }
                // an option the user changed and has not yet been confirmed stays as edited
                for (const k of Object.keys(ctl.overrides)) if (pr[k]) v[k] = ctl.overrides[k]
                ctl.present = pr
                ctl.values = v
                if (vid !== "") ctl.liveVariant = vid
                ctl.known = true
            }
        }
    }

    // ---- apply (throttled, one Process, coalesced) ----
    function fmt(o, x) {
        if (o.kind === "bool") return x >= 0.5 ? "true" : "false"
        if (o.kind === "color") return "0x" + ("00000000" + (x >>> 0).toString(16).toUpperCase()).slice(-8)
        return String(Number(x.toFixed(4)))
    }
    // {a: {b: 1}, c: 2} -> "{a={b=1},c=2}" from the dirty keys
    function luaTable(keys) {
        const tree = {}
        for (const k of keys) {
            const parts = k.split(":")
            let node = tree
            for (let i = 0; i < parts.length - 1; i++) { node[parts[i]] = node[parts[i]] || {}; node = node[parts[i]] }
            node[parts[parts.length - 1]] = fmt(spec(k), values[k])
        }
        const enc = n => "{" + Object.keys(n).map(k => k + "=" + (typeof n[k] === "object" ? enc(n[k]) : n[k])).join(",") + "}"
        return enc(tree)
    }
    Timer { id: throttle; interval: 40; onTriggered: ctl.flush() }
    property bool queued: false
    property bool afterVariant: false
    property bool readBack: false        // after a variant change / colour reset: read the theme colours back
    function flush() {
        if (!ready) return
        if (applyProc.running) { queued = true; return }
        const ks = Object.keys(dirty)
        const vd = variantDirty
        const un = unsetColours
        if (ks.length === 0 && !vd && un.length === 0) return
        dirty = ({})
        variantDirty = false
        unsetColours = []
        let body = ks.length ? luaTable(ks).slice(1, -1) : ""
        if (vd) body = (body ? body + "," : "") + 'variant="' + variant + '"'
        afterVariant = vd
        readBack = readBack || vd || un.length > 0
        // always: the group bar follows blur on / off and the variant; theme colours only after a variant change / reset
        const after = "{variant=" + vd + (un.length ? ",unset={" + un.map(k => '"' + k + '"').join(",") + "}" : "") + "}"
        applyProc.command = ["hyprctl", "eval", (body ? "hl.config({decoration={blur={" + body + "}}}) " : "")
            + "if blur_variant_changed then blur_variant_changed(" + after + ") end"]
        applyProc.running = true
    }
    Process {
        id: applyProc
        environment: ({ HYPRLAND_INSTANCE_SIGNATURE: GlassTuneCtl.sig })
        stdout: StdioCollector { onStreamFinished: ctl.status = text.trim() === "ok" || text.trim() === "" ? "" : "hyprctl: " + text.trim() }
        onExited: {
            if (ctl.afterVariant) { ctl.afterVariant = false; Theme.checkGlass() }
            if (ctl.queued) { ctl.queued = false; ctl.flush() }
            else if (ctl.readBack) { ctl.readBack = false; ctl.load() }
        }
    }

    // ---- saved state ----
    function loadSaved() {
        const s = saved || {}
        const o = {}
        for (const k of Object.keys(s)) if (spec(k) && typeof s[k] === "number" && isFinite(s[k])) o[k] = clamp(k, s[k])
        overrides = o
        const vr = typeof s.variant === "string" ? variantById(s.variant) : undefined
        variantSaved = vr !== undefined
        if (vr) savedVariant = vr.id
    }
    onSavedChanged: if (!throttle.running && !applyProc.running) loadSaved()

    Connections {
        target: GlassTuneCtl
        function onReachableChanged() { if (GlassTuneCtl.reachable) ctl.load() }
    }
    // a config reload re-applies glass.json (managed.lua): read it back, or re-send what is still pending
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "configreloaded" || !GlassTuneCtl.reachable) return
            if (throttle.running || applyProc.running) {
                for (const k of Object.keys(ctl.overrides)) ctl.dirty[k] = true
                throttle.restart()
            } else ctl.load()
        }
    }
    // the weather blur applied a state: the live variant / options may differ now
    Connections {
        target: WeatherBlur
        function onApplied() { if (GlassTuneCtl.reachable && !throttle.running && !applyProc.running) ctl.load() }
    }
    Component.onCompleted: { loadSaved(); if (GlassTuneCtl.reachable) load() }

    IpcHandler {
        target: "blurtune"
        function variant(name: string): string { return ctl.setVariant(name) ? "ok" : "bad variant" }
        function set(key: string, value: string): string { return ctl.set(key, Number(value)) ? "ok" : "bad key/value" }
        function get(key: string): string { return ctl.spec(key) ? ctl.fmt(ctl.spec(key), ctl.values[key]) : key === "variant" ? ctl.variant : "bad key" }
        function reset(which: string): string {
            if (ctl.spec(which)) return ctl.reset(which) ? "ok" : "bad key"
            if (which === "shared" || ctl.variantById(which)) { ctl.resetGroup(which); return "ok" }
            return "bad target"
        }
        function dump(): string {
            return "variant=" + ctl.variant + " live=" + ctl.liveVariant + " available=" + ctl.available.map(v => v.id).join(",") + "\n"
                + ctl.opts.filter(o => ctl.present[o.key] === true).map(o => o.key + "=" + ctl.fmt(o, ctl.values[o.key])).join("\n")
        }
    }
}
