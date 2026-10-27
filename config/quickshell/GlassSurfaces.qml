pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Engine of Settings > Glass > Surfaces (GlassSurfacesSection.qml is the UI): one glass profile per surface type, each
// key either inherited from the global solid_glass value (Settings > Glass) or overridden. No profile = today's look.
// Needs the Hyprland fork with per-surface glass (Theme.glassPerSurface); elsewhere `available` is false and nothing
// is sent (the section explains why). Stored by GlassTuneCtl (`surfaces`, glass.json "surfaces", both modes).
// Compositor side (hypr/hyprland/managed.lua, M.apply_surfaces): the shell sends the whole profile table with
// `hyprctl eval "glass_surfaces_apply({...})"` (throttled, same instance guard as GlassTuneCtl); Lua composes one
// `glass = "key:value ..."` string per surface into a named layer rule (layers), group:groupbar:solid_glass (group bar)
// or decoration:blur:solid_glass:border (window borders; only drawn with a border size > 0). A config reload re-applies
// glass.json. Adding a surface: an entry in `surfaces` here and in managed.lua M.SURFACE_LAYERS / M.SURFACE_IDS.
//   qs ipc call glasssurfaces set <id> <key> <value> | unset <id> <key> | reset <id|all> | preset <name> | border <on|off> | dump
Singleton {
    id: gs

    readonly property var tune: GlassTuneCtl
    // id, label, what it covers; `option`: needs that Theme probe (not a layer rule)
    readonly property var surfaces: [
        { id: "bar",      label: "Bar",              detail: "the bar (layer qs-bar)" },
        { id: "popup",    label: "Popups & panels",  detail: "bar popups and panels (qs-popup)" },
        { id: "launcher", label: "Launcher",         detail: "the launcher card (qs-launcher)" },
        { id: "osd",      label: "OSD",              detail: "volume / brightness pill (qs-osd)" },
        { id: "toast",    label: "Notifications",    detail: "notification toasts (qs-toast)" },
        { id: "groupbar", label: "Group bar",        detail: "the window group pills", option: "groupbar" },
        { id: "border",   label: "Window borders",   detail: "glass ring under window borders", option: "border" }
    ]
    readonly property var ids: surfaces.map(s => s.id)
    // the keys a profile may override (managed.lua M.SURFACE_KEYS, same order); ranges from GlassTuneCtl.opts
    readonly property var keys: ["depth", "refraction", "aberration", "specular_intensity", "frost", "clarity", "darkening"]
    readonly property var labels: ({ depth: "Depth (bend)", refraction: "Refraction", aberration: "Aberration",
                                     specular_intensity: "Specular", frost: "Frost", clarity: "Clarity", darkening: "Darkening" })
    // one-click starting points the user adjusts afterwards (window borders are left as they are)
    readonly property var presets: ({
        differentiated: {
            bar:      { depth: 0.35, refraction: 10, aberration: 0.01 },
            popup:    { depth: 1.2,  refraction: 36 },
            launcher: { depth: 1.3,  refraction: 40, aberration: 0.06 },
            osd:      { depth: 2,    refraction: 44, aberration: 0.08, specular_intensity: 1.2 },
            toast:    { depth: 0.6,  refraction: 16, aberration: 0.02, frost: 2 },
            groupbar: { depth: 0.5,  refraction: 6 }
        }
    })

    readonly property var profiles: tune.surfaces
    // which preset the saved profiles equal (window borders aside): "uniform" (none), a `presets` name, else "custom"
    readonly property string current: {
        void profiles
        if (ids.every(id => id === "border" || count(id) === 0)) return "uniform"
        for (const name of Object.keys(presets)) if (matches(presets[name])) return name
        return "custom"
    }
    function matches(pre) {
        for (const id of ids) {
            if (id === "border") continue
            const want = pre[id] || {}
            for (const k of keys) {
                const has = isOverridden(id, k), w = want[k]
                if (has !== (w !== undefined)) return false
                if (has && Math.abs(profiles[id][k] - w) > 1e-6) return false
            }
        }
        return true
    }
    // the compositor understands per-surface glass and this shell may talk to it
    readonly property bool available: Theme.glass && Theme.glassPerSurface && tune.ready
    function surfaceOk(s) { return !s.option || (s.option === "groupbar" ? Theme.glassGroupbarOpt : Theme.glassBorderOpt) }
    readonly property string unavailableReason: !Theme.glassPerSurface || !Theme.glass
        ? "Needs the Hyprland fork build with per-surface glass (decoration:blur:solid_glass:per_surface); this compositor has none, so the global values apply everywhere."
        : !tune.ready ? (tune.guardError || "Checking the compositor instance...") : ""

    function opt(key) { return tune.spec(key) }
    function isOverridden(id, key) { const p = profiles[id]; return !!p && typeof p[key] === "number" }
    function value(id, key) { return isOverridden(id, key) ? profiles[id][key] : tune.values[key] }
    function count(id) { return keys.filter(k => isOverridden(id, k)).length }
    readonly property int totalCount: ids.reduce((n, id) => n + count(id), 0) + (borderOn ? 1 : 0)
    readonly property bool borderOn: !!profiles.border && profiles.border.enabled === true

    function copy() { return JSON.parse(JSON.stringify(profiles)) }
    function commit(all) {
        for (const id of Object.keys(all)) {
            const p = all[id]
            if (Object.keys(p).filter(k => k !== "enabled" || p.enabled).length === 0) delete all[id]
        }
        tune.setSurfaces(all)
        throttle.start()
    }
    function set(id, key, v) {
        if (!available || ids.indexOf(id) < 0 || keys.indexOf(key) < 0 || typeof v !== "number" || isNaN(v)) return false
        const all = copy()
        all[id] = all[id] || {}
        all[id][key] = tune.clamp(key, v)
        commit(all)
        return true
    }
    function unset(id, key) {
        if (!available || !isOverridden(id, key)) return false
        const all = copy()
        delete all[id][key]
        commit(all)
        return true
    }
    // back to the global values (window borders stay on / off)
    function reset(id) {
        if (!available) return false
        const all = copy()
        if (id === "all") {
            for (const k of Object.keys(all)) if (k !== "border") delete all[k]
            if (all.border) all.border = { enabled: all.border.enabled === true }
        } else if (ids.indexOf(id) >= 0) {
            if (id === "border" && all.border) all.border = { enabled: all.border.enabled === true }
            else delete all[id]
        } else return false
        commit(all)
        return true
    }
    function setBorder(on) {
        if (!available) return false
        const all = copy()
        all.border = Object.assign(all.border || {}, { enabled: on === true })
        commit(all)
        return true
    }
    function applyPreset(name) {
        const pre = presets[name]
        if (!available || !pre) return false
        const all = JSON.parse(JSON.stringify(pre))
        if (profiles.border) all.border = JSON.parse(JSON.stringify(profiles.border))
        commit(all)
        return true
    }

    // the profiles as a Lua table literal: known ids / keys and numbers only (nothing user-typed reaches the eval)
    function luaTable() {
        const parts = []
        for (const id of ids) {
            const p = profiles[id]
            if (!p) continue
            const f = keys.filter(k => typeof p[k] === "number" && isFinite(p[k])).map(k => k + "=" + tune.fmt(k, tune.clamp(k, p[k])))
            if (id === "border" && p.enabled === true) f.push("enabled=true")
            parts.push(id + "={" + f.join(",") + "}")
        }
        return "{" + parts.join(",") + "}"
    }

    // ---- apply (throttled, one Process, coalesced; GlassTuneCtl's instance guard) ----
    property string status: ""
    Timer { id: throttle; interval: 60; onTriggered: gs.flush() }
    property bool queued: false
    function flush() {
        if (!available) return
        if (applyProc.running) { queued = true; return }
        applyProc.command = ["hyprctl", "eval", "if glass_surfaces_apply then return glass_surfaces_apply(" + luaTable() + ") end"]
        applyProc.running = true
    }
    Process {
        id: applyProc
        environment: ({ HYPRLAND_INSTANCE_SIGNATURE: gs.tune.sig })
        stdout: StdioCollector { onStreamFinished: { const t = text.trim(); gs.status = (t === "" || t === "ok" || t.startsWith("true")) ? "" : "hyprctl: " + t } }
        onExited: if (gs.queued) { gs.queued = false; gs.flush() }
    }
    // a config reload re-applies glass.json; a change not saved yet is sent again so the reload cannot undo it
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" && (gs.tune.savePending || throttle.running || applyProc.running)) throttle.restart()
        }
    }

    IpcHandler {
        target: "glasssurfaces"
        function set(id: string, key: string, value: string): string { return gs.set(id, key, Number(value)) ? "ok" : "refused" }
        function unset(id: string, key: string): string { return gs.unset(id, key) ? "ok" : "refused" }
        function reset(id: string): string { return gs.reset(id) ? "ok" : "refused" }
        function preset(name: string): string { return gs.applyPreset(name) ? "ok" : "refused" }
        function border(on: string): string { return gs.setBorder(on === "on" || on === "true") ? "ok" : "refused" }
        function dump(): string { return "available=" + gs.available + " " + gs.luaTable() + (gs.status ? "\n" + gs.status : "") }
    }
}
