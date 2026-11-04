.pragma library

// The "Unload model" steps of Settings > Voice and Settings > Diacritics (IdleUnloadRow over DictationPrefs / DiacriticsPrefs),
// in seconds of `idle_timeout_s`: 1 = Immediately (the services unload right after each session / fix: 0 < x <= 1, their
// UNLOAD_AT_ONCE), 0 = Never (as 0 or a negative number always meant). nearest() = the step a saved value shows as: an
// off-list value snaps to the closest step (by ratio) without being rewritten.
var VALUES = [1, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 0]
var LABELS = ["Immediately", "15 s", "30 s", "1 min", "2 min", "5 min", "10 min", "15 min", "30 min", "1 h", "Never"]

function nearest(v) {
    const n = Number(v)
    if (!isFinite(n) || n <= 0) return 0
    if (n <= 1) return 1
    let best = VALUES[0], gap = Infinity
    for (const s of VALUES) {
        if (s <= 0) continue
        const g = Math.abs(Math.log(n / s))
        if (g < gap) { gap = g; best = s }
    }
    return best
}
