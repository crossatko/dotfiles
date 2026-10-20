.pragma library

// Frecency and usage bookkeeping. All functions are pure: usage objects are
// plain JSON data and updates return new objects.
//
// frecency = avgWeight * ln(1 + count)
//   avgWeight: mean bucket weight over entry.times (last <= 10 launches):
//   100 within 4 days, 70 within 14, 50 within 31, 30 within 90, else 10.

var DAY = 86400000;
var MAX_TIMES = 10;
var MAX_TERMS = 20;
var PRUNE_DAYS = 180;

function bucketWeight(ageMs) {
    var d = ageMs / DAY;
    if (d <= 4) return 100;
    if (d <= 14) return 70;
    if (d <= 31) return 50;
    if (d <= 90) return 30;
    return 10;
}

function frecency(entry, now) {
    if (!entry || !entry.count) return 0;
    var times = entry.times || [];
    if (times.length === 0) return 10 * Math.log(1 + entry.count);
    var sum = 0;
    for (var i = 0; i < times.length; i++) sum += bucketWeight(Math.max(0, now - times[i]));
    return (sum / times.length) * Math.log(1 + entry.count);
}

function cloneEntry(e) {
    var out = {
        count: (e && e.count) || 0,
        times: ((e && e.times) || []).slice(),
        terms: {}
    };
    var t = (e && e.terms) || {};
    for (var k in t) out.terms[k] = t[k];
    if (e && e.pinned) out.pinned = true;
    if (e && e.hidden) out.hidden = true;
    return out;
}

function cloneUsage(usage, skipId) {
    var out = {};
    for (var id in (usage || {})) if (id !== skipId) out[id] = usage[id];
    return out;
}

function record(usage, id, query, now) {
    var out = cloneUsage(usage, id);
    var e = cloneEntry(usage ? usage[id] : null);
    e.count += 1;
    e.times.push(now);
    if (e.times.length > MAX_TIMES) e.times = e.times.slice(e.times.length - MAX_TIMES);
    var q = (query || "").toLowerCase().replace(/^\s+|\s+$/g, "");
    if (q) {
        e.terms[q] = (e.terms[q] || 0) + 1;
        var keys = Object.keys(e.terms);
        while (keys.length > MAX_TERMS) {
            var worst = keys[0];
            for (var i = 1; i < keys.length; i++)
                if (e.terms[keys[i]] < e.terms[worst]) worst = keys[i];
            delete e.terms[worst];
            keys = Object.keys(e.terms);
        }
    }
    out[id] = e;
    return out;
}

function setFlag(usage, id, flag, value) {
    var out = cloneUsage(usage, id);
    var e = cloneEntry(usage ? usage[id] : null);
    if (value) e[flag] = true; else delete e[flag];
    out[id] = e;
    return out;
}

function setPinned(usage, id, value) { return setFlag(usage, id, "pinned", value); }
function setHidden(usage, id, value) { return setFlag(usage, id, "hidden", value); }

function prune(usage, now) {
    var out = {};
    for (var id in (usage || {})) {
        var e = usage[id];
        var times = e.times || [];
        var last = times.length ? times[times.length - 1] : 0;
        if (e.pinned || e.hidden || (now - last) <= PRUNE_DAYS * DAY) out[id] = e;
    }
    return out;
}
