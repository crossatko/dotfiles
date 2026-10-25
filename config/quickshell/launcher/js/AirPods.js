.pragma library

// Parsing and helpers for the AirPods section (AirPods.qml singleton): plain functions, no state, no
// processes. Input is the librepods daemon's status file (`$XDG_STATE_HOME/librepods/status.json`, one JSON line,
// written on every change, removed when the daemon stops). Keys used (schema_version 1): connected, device_name,
// model_name, noise_mode (0 off, 1 anc, 2 transparency, 3 adaptive, -1 unknown), adaptive_noise_level (0-100),
// conversational_awareness, ear_detection_behavior (0 pause when one is out, 1 both, 2 never), left / right
// {available, level, charging, in_ear}, case {available, level, charging}, headset (AirPods Max) with the same
// shape, is_headset, and the capability flags supports_noise_control / _noise_off / _adaptive /
// _conversational_awareness (absent = the older default: control and off true, the rest = is_pro_series), and
// case_seen_at (unix seconds of the last live case reading, 0 none yet; absent = a daemon without case:refresh).

var UNKNOWN = -1;
var SUPPORTED_SCHEMA = 1;

var MODE_OFF = 0, MODE_ANC = 1, MODE_TRANSPARENCY = 2, MODE_ADAPTIVE = 3;

function num(v, fallback) {
    var n = parseInt(v, 10);
    return isFinite(n) ? n : fallback;
}
function flag(v, fallback) { return v === undefined ? fallback : v === true; }

// {level, charging, inEar}; level = -1 when the part is not heard from (its other fields are stale then)
function part(raw) {
    var p = { level: UNKNOWN, charging: false, inEar: false };
    if (!raw || typeof raw !== "object" || raw.available !== true) return p;
    p.level = Math.max(UNKNOWN, Math.min(100, num(raw.level, UNKNOWN)));
    p.charging = raw.charging === true;
    p.inEar = raw.in_ear === true;
    return p;
}

function empty() {
    return {
        valid: false, tooNew: false, connected: false, name: "", model: "", headset: false,
        canControl: false, canOff: false, canAdaptive: false, canAware: false,
        mode: UNKNOWN, adaptive: 0, aware: false, ear: 0,
        left: part(null), right: part(null), box: part(null), max: part(null), caseSeenAt: UNKNOWN
    };
}

// Whole file text -> flat status object (always the full shape; valid=false on empty / broken / too-new input)
function parse(text) {
    var s = empty();
    var d;
    try { d = JSON.parse(String(text || "").trim()); } catch (e) { return s; }
    if (!d || typeof d !== "object" || d.schema_version === undefined) return s;
    if (num(d.schema_version, 0) > SUPPORTED_SCHEMA) { s.tooNew = true; return s; }
    s.valid = true;
    s.connected = d.connected === true;
    s.name = String(d.device_name || "");
    s.model = String(d.model_name || "");
    s.headset = d.is_headset === true;
    var pro = d.is_pro_series === true;
    s.canControl = flag(d.supports_noise_control, true);
    s.canOff = d.supports_noise_off !== false;
    s.canAdaptive = flag(d.supports_adaptive, pro);
    s.canAware = flag(d.supports_conversational_awareness, pro);
    s.mode = num(d.noise_mode, UNKNOWN);
    s.adaptive = Math.max(0, Math.min(100, num(d.adaptive_noise_level, 0)));
    s.aware = d.conversational_awareness === true;
    s.ear = num(d.ear_detection_behavior, 0);
    s.left = part(d.left);
    s.right = part(d.right);
    s.box = part(d["case"]);
    s.max = part(d.headset);
    // unix seconds of the last live case reading; -1 = this daemon does not publish it (no case:refresh verb)
    s.caseSeenAt = d.case_seen_at === undefined ? UNKNOWN : num(d.case_seen_at, 0);
    return s;
}

// Modes the model reports, in display order: [{value, label, name, glyph, verb}] (glyph: Font Awesome ban /
// ear-listen / sparkles / ear-deaf, for the icon-only mode buttons; name: the spelled-out label next to them)
function modes(s) {
    if (!s.canControl) return [];
    var out = [];
    if (s.canOff) out.push({ value: MODE_OFF, label: "Off", name: "Off", glyph: "\uf05e", verb: "noise:off" });
    out.push({ value: MODE_TRANSPARENCY, label: "Transparency", name: "Transparency", glyph: "\uf2a2", verb: "noise:transparency" });
    if (s.canAdaptive) out.push({ value: MODE_ADAPTIVE, label: "Adaptive", name: "Adaptive", glyph: "\uf890", verb: "noise:adaptive" });
    out.push({ value: MODE_ANC, label: "ANC", name: "Noise cancelling", glyph: "\uf2a4", verb: "noise:anc" });
    return out;
}

// ear_detection_behavior -> ctl verb / label
var EAR = [
    { value: 0, label: "One out", verb: "ear:one" },
    { value: 1, label: "Both out", verb: "ear:both" },
    { value: 2, label: "Never", verb: "ear:off" }
];

// Lowest battery of what is in use: both buds (or the Max headset); the case does not count. -1 = none known.
function lowest(s) {
    var levels = (s.headset ? [s.max.level] : [s.left.level, s.right.level]).filter(function (l) { return l >= 0; });
    return levels.length ? Math.min.apply(null, levels) : UNKNOWN;
}
// the part behind lowest() is charging (a bud in the case: the percentage rises)
function lowestCharging(s) {
    if (s.headset) return s.max.charging;
    var l = lowest(s);
    return l >= 0 && [s.left, s.right].some(function (p) { return p.level === l && p.charging; });
}
// Age of a reading for display: "" while fresh (under a minute, or unknown), else "5m" / "3h" / "2d"
function age(seenAt, now) {
    if (!(seenAt > 0) || !(now >= seenAt)) return "";
    var d = Math.floor(now - seenAt);
    return d < 60 ? "" : d < 3600 ? Math.floor(d / 60) + "m" : d < 86400 ? Math.floor(d / 3600) + "h" : Math.floor(d / 86400) + "d";
}

// Section title from the model name: without a trailing "(...)" variant ("AirPods Pro 2 (USB-C)" -> "AirPods Pro 2"),
// which would not fit next to the header toggle; "AirPods" when the daemon gives none
function title(model) {
    return String(model || "").replace(/\s*\([^)]*\)\s*$/, "").trim() || "AirPods";
}

// A bluez output that looks like AirPods (used to say "daemon not running" while the daemon cannot tell us)
function looksLikeAirPods(desc, nodeName) {
    return String(nodeName || "").indexOf("bluez_output") === 0 && /airpods/i.test(String(desc || ""));
}
