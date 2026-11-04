.pragma library

// Where a feature pill sits (dictation pill, diacritics pill): the four position keys both prefs files share
// (dictation-prefs.json, diacritics.json; written by DictationPrefs / DiacriticsPrefs, read by the shell only) and the pure
// geometry PillPlacement.qml feeds with the bar's tokens. One rule for the real pills and the Settings preview.
//   pill_edge    "bar" = the bar's edge (no bar: the bottom), "top", "bottom"
//   pill_gap     distance from that edge, in gap tokens (the bar's popup gap past a bar, the edge gap from a bare edge); 2 = before
//   pill_x       0 = left, 0.5 = centred, 1 = right (between the edge gaps of the screen sides)
//   pill_screen  "" = the focused monitor; else a monitor key (Appearance.monitorKey); a monitor that is not connected = focused

var DEFAULTS = { pill_edge: "bar", pill_gap: 2, pill_x: 0.5, pill_screen: "" }
var KEYS = ["pill_edge", "pill_gap", "pill_x", "pill_screen"]
var EDGES = ["bar", "top", "bottom"]
// PrefSlider ranges: [min, max, decimals]
var SPEC = { pill_gap: [0, 8, 1], pill_x: [0, 1, 2] }

function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)) }
function round(v, d) { const f = Math.pow(10, d); return Math.round(v * f) / f }

// a valid value for `key`, or undefined (wrong type, unknown key)
function clean(key, v) {
    if (key === "pill_edge") return EDGES.indexOf(v) >= 0 ? v : undefined
    if (key === "pill_gap" || key === "pill_x") {
        if (typeof v !== "number" || !isFinite(v)) return undefined
        const s = SPEC[key]
        return round(clamp(v, s[0], s[1]), s[2])
    }
    if (key === "pill_screen") return typeof v === "string" && v.length <= 200 && !/[\x00-\x1f]/.test(v) ? v : undefined
    return undefined
}

// the four keys of a parsed file object `d`; a missing / bad pill_edge = `legacyEdge` (dictation: its old pill_bottom)
function parse(d, legacyEdge) {
    const o = d !== null && typeof d === "object" && !Array.isArray(d) ? d : {}
    const out = {}
    for (const k of KEYS) {
        const v = clean(k, o[k])
        out[k] = v !== undefined ? v : k === "pill_edge" && EDGES.indexOf(legacyEdge) >= 0 ? legacyEdge : DEFAULTS[k]
    }
    return out
}

// the geometry. p = { edge, barEdge ("top" | "bottom" | "" = no bar), gap, x, screenW, pillW, side (edge gap of the screen
// sides), barInset (screen edge -> the bar's far edge, layout space), gapBar (one gap token past a bar), gapEdge (one from a
// bare edge) } -> { atTop, onBar (hangs off the bar), inset (anchored edge -> card, layout space), left (screen left -> card),
// cardW }
function place(p) {
    const atTop = p.edge === "top" || (p.edge === "bar" && p.barEdge === "top")
    const onBar = p.barEdge !== "" && p.barEdge === (atTop ? "top" : "bottom")
    const g = Math.max(0, Number(p.gap) || 0)
    // past the bar; no bar on this screen: the bar gap from the bare edge (as before); the edge away from the bar: the edge gap
    const inset = onBar ? p.barInset + g * p.gapBar : p.barEdge === "" ? g * p.gapBar : g * p.gapEdge
    const room = Math.max(0, p.screenW - 2 * p.side)
    const cardW = Math.min(p.pillW, room > 0 ? room : p.pillW)
    const left = p.side + clamp(Number(p.x) || 0, 0, 1) * Math.max(0, room - cardW)
    return { atTop: atTop, onBar: onBar, inset: inset, left: Math.round(left), cardW: cardW }
}
