pragma Singleton
import QtQuick
import Quickshell

// The named value sets behind every primary choice in Settings (Look & feel, Bar, Lock screen, Desktop clock) and
// the one rule that keeps them honest: a preset is only a NAME for a set of values in the existing stores
// (GlassTuneCtl / glass.json, Motion / animations.json, Appearance / appearance.json, BarConfig / bars.json,
// LockPrefs / lock.json, DeskClockPrefs / deskclock.json). Nothing is migrated: `<area>Current` says which preset the
// saved values equal (within a tolerance), else "custom", and the page then shows a Custom tag / card and keeps the
// values exactly as they are until the user picks a preset. `apply<Area>(id)` writes the set through the store's own
// setters (live apply + save as always). The detailed controls under Customise… edit the same keys, so a tweak there
// turns the choice into Custom and a preset click puts it back.
// Adding a preset: one entry in the table; a new area needs its table, a `<area>Current` binding and an apply().
Singleton {
    id: ps

    function near(a, b, tol) { return Math.abs(a - b) <= tol }

    // ---- Glass style (GlassTuneCtl: the solid_glass keys, same values for light and dark; the tint is the dark
    // mode's, light mode keeps "from the theme background" with the preset's absorption) ----
    readonly property var glass: [
        { id: "clear",   name: "Clear",   // = the fork's built-in defaults
          v: { refraction: 28, bulb: 48, depth: 1, edge_curve: 1, aberration: 0.05, light_angle: 135, specular_intensity: 1, specular_power: 48, sheen: 0.14, clarity: 1, frost: 3, darkening: 0.35, saturation: 1.25 }, tint: 0x14EEF5FF },
        { id: "frosted", name: "Frosted",
          v: { refraction: 14, bulb: 48, depth: 0.6, edge_curve: 1, aberration: 0.02, light_angle: 135, specular_intensity: 0.6, specular_power: 48, sheen: 0.2, clarity: 0.55, frost: 10, darkening: 0.4, saturation: 1.1 }, tint: 0x30EEF5FF },
        { id: "smoked",  name: "Smoked",
          v: { refraction: 24, bulb: 48, depth: 0.8, edge_curve: 1, aberration: 0.03, light_angle: 135, specular_intensity: 0.5, specular_power: 48, sheen: 0.08, clarity: 0.9, frost: 2, darkening: 0.6, saturation: 0.9 }, tint: 0x60000000 },
        { id: "liquid",  name: "Liquid",
          v: { refraction: 48, bulb: 40.05, depth: 1, edge_curve: 1.005, aberration: 0.0501, light_angle: 137.4, specular_intensity: 0.015, specular_power: 32.1, sheen: 0, clarity: 0.247, frost: 0, darkening: 0, saturation: 1.902 }, tint: 0xFA000000 }
    ]
    function glassMatches(p, values) {
        for (const k of Object.keys(p.v)) {
            const o = GlassTuneCtl.spec(k)
            if (!o || values[k] === undefined) return false
            if (!near(values[k], p.v[k], 0.015 * (o.max - o.min))) return false
        }
        return true
    }
    readonly property string glassCurrent: { const v = GlassTuneCtl.values; const p = glass.find(p => glassMatches(p, v)); return p ? p.id : "custom" }
    function applyGlass(id) {
        const p = glass.find(p => p.id === id)
        if (!p || !GlassTuneCtl.editable) return false
        for (const k of Object.keys(p.v)) GlassTuneCtl.set(k, p.v[k])
        if (GlassTuneCtl.loadedMode === "light") {
            // keep the theme colour, take the preset's absorption
            const cur = Math.round(GlassTuneCtl.values.tint) >>> 0
            GlassTuneCtl.set("tint", (((p.tint >>> 24) & 255) * 16777216 + (cur & 0xFFFFFF)) >>> 0)
            GlassTuneCtl.setTintFromBg(true)
        } else {
            GlassTuneCtl.set("tint", p.tint)
            if (GlassTuneCtl.tintFromBgSet !== undefined) GlassTuneCtl.setTintFromBg(false)
        }
        return true
    }

    // ---- Motion (Motion: popups + Hyprland; a preset clears the per-category overrides too) ----
    readonly property var motion: [
        { id: "off",     name: "Off",
          v: { popupStyle: "none", hyprEnabled: false } },
        { id: "calm",    name: "Calm",
          v: { popupSpeed: 0.75, popupCurve: "expo", popupStyle: "scale", launcherMotion: true, hyprEnabled: true, hyprSpeed: 0.7, hyprCurve: "snappy" } },
        { id: "snappy",  name: "Snappy",
          v: { popupSpeed: 1.5, popupCurve: "cubic", popupStyle: "scale", launcherMotion: true, hyprEnabled: true, hyprSpeed: 1.5, hyprCurve: "snappy" } },
        { id: "playful", name: "Playful",
          v: { popupSpeed: 1, popupCurve: "back", popupStyle: "scale", launcherMotion: true, hyprEnabled: true, hyprSpeed: 1, hyprCurve: "overshoot" } }
    ]
    readonly property var motionKeys: ["popupSpeed", "popupCurve", "popupStyle", "launcherMotion", "hyprEnabled", "hyprSpeed", "hyprCurve"]
    readonly property bool motionGroupsTouched: {
        void Motion.data
        return Motion.groups.some(g => (Motion.overridden(g.id + "Enabled") && Motion.value(g.id + "Enabled") !== true)
                                    || (Motion.overridden(g.id + "Speed") && !near(Motion.value(g.id + "Speed"), 1, 0.001))
                                    || (Motion.overridden(g.id + "Curve") && Motion.value(g.id + "Curve") !== ""))
    }
    readonly property string motionCurrent: {
        void Motion.data
        for (const p of motion) {
            let ok = true
            for (const k of Object.keys(p.v)) {
                const cur = Motion.value(k), want = p.v[k]
                if (typeof want === "number" ? !near(cur, want, 0.011) : cur !== want) { ok = false; break }
            }
            if (ok && (p.id === "off" || !motionGroupsTouched)) return p.id
        }
        return "custom"
    }
    function applyMotion(id) {
        const p = motion.find(p => p.id === id)
        if (!p) return false
        for (const g of Motion.groups) for (const s of ["Enabled", "Speed", "Curve"]) Motion.unset(g.id + s)
        for (const k of motionKeys) {
            const want = p.v[k] !== undefined ? p.v[k] : Motion.defaults[k]
            if (want === Motion.defaults[k]) Motion.unset(k)
            else Motion.set(k, want)
        }
        return true
    }

    // ---- Shape (Appearance: radius, window gap, border; the edge gap follows the gap, smart gaps are left alone) ----
    readonly property var shape: [
        { id: "sharp", name: "Sharp", v: { radius: 0, gap: 6, border: 1 } },
        { id: "soft",  name: "Soft",             v: { radius: 10, gap: 10, border: 1 } },
        { id: "round", name: "Round",   v: { radius: 17, gap: 14, border: 0 } }
    ]
    readonly property string shapeCurrent: {
        void Appearance.data
        const edgeOk = !Appearance.overridden("edgeGap") || Theme.gapOut === Theme.gap
        if (!edgeOk) return "custom"
        const p = shape.find(p => Theme.radius === p.v.radius && Theme.gap === p.v.gap && Theme.borderSize === p.v.border)
        return p ? p.id : "custom"
    }
    function applyShape(id) {
        const p = shape.find(p => p.id === id)
        if (!p) return false
        for (const k of Object.keys(p.v)) Appearance.set(k, p.v[k])
        Appearance.unset("edgeGap")
        return true
    }

    // ---- Bar look (BarConfig, per bar: floating / docked / transparent-when-flush) ----
    readonly property var barLook: [
        { id: "floating",    name: "Floating" },
        { id: "docked",      name: "Docked" },
        { id: "transparent", name: "Transparent" }
    ]
    function barLookOf(s) {
        if (!s) return "docked"
        if (BarConfig.floating(s)) return "floating"
        return BarConfig.transparentFlush(s) ? "transparent" : "docked"
    }
    function applyBarLook(s, id) {
        if (!s || !BarConfig.enabled(s)) return false
        if (id === "floating") { BarConfig.set(s, "floating", true); return true }
        BarConfig.set(s, "floating", false)
        BarConfig.set(s, "transparentFlush", id === "transparent")
        return true
    }

    // ---- Lock screen (LockPrefs) ----
    readonly property var lockLayout: [
        { id: "minimal",  name: "Minimal",       v: { showDate: false, mediaCard: false } },
        { id: "date",     name: "Clock & date",       v: { showDate: true, mediaCard: false } },
        { id: "playback", name: "With playback", v: { showDate: true, mediaCard: true } }
    ]
    readonly property string lockLayoutCurrent: {
        void LockPrefs.data
        const p = lockLayout.find(p => LockPrefs.showDate === p.v.showDate && LockPrefs.mediaCard === p.v.mediaCard)
        return p ? p.id : "custom"
    }
    function applyLockLayout(id) { const p = lockLayout.find(p => p.id === id); if (!p) return false; for (const k of Object.keys(p.v)) LockPrefs.set(k, p.v[k]); return true }

    readonly property var lockSize: [{ id: "s", name: "Small", v: 0.18 }, { id: "m", name: "Medium", v: 0.24 }, { id: "l", name: "Large", v: 0.3 }]
    readonly property string lockSizeCurrent: { void LockPrefs.data; const p = lockSize.find(p => near(LockPrefs.clockSize, p.v, 0.005)); return p ? p.id : "custom" }
    function applyLockSize(id) { const p = lockSize.find(p => p.id === id); if (!p) return false; LockPrefs.set("clockSize", p.v); return true }

    readonly property var lockBackdrop: [
        { id: "dim",     name: "Dimmed",     v: { dim: 0.5, blur: 0 } },
        { id: "blurred", name: "Blurred", v: { dim: 0.4, blur: 24 } },
        { id: "plain",   name: "Plain",      v: { dim: 0.2, blur: 0 } }
    ]
    readonly property string lockBackdropCurrent: {
        void LockPrefs.data
        const p = lockBackdrop.find(p => near(LockPrefs.dim, p.v.dim, 0.011) && LockPrefs.blur === p.v.blur)
        return p ? p.id : "custom"
    }
    function applyLockBackdrop(id) { const p = lockBackdrop.find(p => p.id === id); if (!p) return false; for (const k of Object.keys(p.v)) LockPrefs.set(k, p.v[k]); return true }

    // ---- Morph (LockPrefs / DeskClockPrefs `morph`: x the default morph time) ----
    readonly property var morph: [{ id: "off", name: "Off", v: 0 }, { id: "calm", name: "Calm", v: 1 }, { id: "lively", name: "Lively", v: 2 }]
    function morphOf(v) { const p = morph.find(p => near(v, p.v, 0.011)); return p ? p.id : "custom" }
    function morphValue(id) { const p = morph.find(p => p.id === id); return p ? p.v : undefined }

    // ---- Desktop clock (DeskClockPrefs) ----
    readonly property var deskSize: [{ id: "s", name: "Small", v: 0.12 }, { id: "m", name: "Medium", v: 0.16 }, { id: "l", name: "Large", v: 0.22 }]
    readonly property string deskSizeCurrent: { void DeskClockPrefs.data; const p = deskSize.find(p => near(DeskClockPrefs.size, p.v, 0.005)); return p ? p.id : "custom" }
    function applyDeskSize(id) { const p = deskSize.find(p => p.id === id); if (!p) return false; DeskClockPrefs.set("size", p.v); return true }
}
