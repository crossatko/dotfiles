.pragma library

// A per-monitor clock (desktop clock, lock clock): which monitors show it. The ONE rule, used by DeskClockPrefs.shownOn
// (main shell, wallpaper engine, Settings) and LockPrefs.clockOn (lock screen, Settings). Stored as an on switch
// (deskclock.json `enabled`, lock.json `clock`) + `hidden` ({ "<monitor key>": true }); a monitor shows the clock when
// on and not hidden there. Settings writes per monitor through toggle() / setAll(), which keep the pair consistent:
// the switch is true only while some connected monitor shows the clock.
// state = { enabled, hidden }; keys = the connected monitors' keys; toggle / setAll return a NEW { enabled, hidden }.

function shown(enabled, hidden, key) {
    return enabled === true && typeof key === "string" && key !== "" && !(hidden && hidden[key] === true)
}

function shownKeys(state, keys) {
    return keys.filter(k => shown(state.enabled, state.hidden, k))
}

// one monitor on / off. On while off everywhere = this monitor only (the other connected ones get hidden). Off on the
// last connected monitor that shows it = off everywhere (`enabled` false; `hidden` keeps where it was shown).
function toggle(state, keys, key, on) {
    const h = Object.assign({}, state.hidden || {})
    const en = state.enabled === true
    if (typeof key !== "string" || key === "") return { enabled: en, hidden: h }
    if (on) {
        if (!en) for (const k of keys) if (k !== key) h[k] = true
        delete h[key]
        return { enabled: true, hidden: h }
    }
    if (!en) return { enabled: false, hidden: h }
    const rest = keys.filter(k => k !== key && shown(true, h, k))
    if (rest.length === 0) return { enabled: false, hidden: h }
    h[key] = true
    return { enabled: true, hidden: h }
}

// every connected monitor on / off (monitors not connected keep their saved choice)
function setAll(state, keys, on) {
    const h = Object.assign({}, state.hidden || {})
    if (!on) return { enabled: false, hidden: h }
    for (const k of keys) delete h[k]
    return { enabled: true, hidden: h }
}
