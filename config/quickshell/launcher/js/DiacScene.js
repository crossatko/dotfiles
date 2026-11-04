.pragma library
.import "DiacFont.js" as F

// Scenes of the diacritics pill (DiacDots): pure functions of time returning a dot grid (DiacFont.js layout, only lit dots, no
// background dots). Port of the approved "Flare" prototype (variant c1):
//   words    the real words, cut into chunks that fit the row (about 15 characters), swapped word over word; each chunk stands still,
//            centred, the base letters optically centred with the marks above; the marks appear one by one in reading order
//            (MARK_GAP apart), each with a short accent flare that settles to white while its letter pulses once; READ s dwell after the last
//   neutral  the same look without the words (Settings: show text off): pseudo-words as dotted lines fill the row left to right, marks
//            pop up over some of them with the same flare; `dim` = the loading variant (slower, no marks, half bright)
//   replay   when the service reports `done` with the fixed text (it only has it at the end), a fast replay of the whole fixed text:
//            every chunk in turn with its marks flaring in one by one, at most REPLAY_MAX s in all (replayPlan / replay), then the check
//   end states  the working picture lets go (0.2 s), then the icon draws in dot by dot: done = check + sparks, failed = cross that
//            shakes, unsupported = no-sign
// Timings are seconds; the grid is COLS x ROWS with the 7-row base band on rows 3..9 (the card's centre line).
//   live     while the model works the service streams the fixed words; they are put into the chunk on screen and their marks flare in as they
//            arrive (liveNew / liveFeed / liveScene); on done the replay carries on from there (liveFinish) instead of starting over
// Tests: node --test launcher/js/tests/diacscene.test.js

var COLS = 78, ROWS = 13;
var MAXW = 76;                  // columns that fit the row
var SPACE = 4;                  // a space, columns
var BASE_Y = 3;                 // row of the capital top
var SWAP = 0.07;                // chunk swap, dissolve in / out
var MARK_START = 0.08, MARK_GAP = 0.04, DWELL = 0.30;   // first mark after the swap-in, spacing, read time after the last mark

function tokens(s) { return s.split(/\s+/).filter(function (w) { return w !== ""; }); }

// text -> { chunks: [{ chars: [{ ch, x, w, mark }], width, marks, dur }], starts, total }; x relative to the chunk's left edge.
// Characters the font lacks are skipped; very long input is cut (the pill only needs a taste of it).
function prepare(text) {
    function lay(w, wi) {
        var cs = [], x = 0;
        for (var i = 0; i < w.length; i++) {
            var ch = w.charAt(i), adv = F.advance(ch);
            if (!adv) continue;
            cs.push({ ch: ch, x: x, w: adv - 1, mark: F.hasMark(ch), wi: wi, k: cs.length });
            x += adv;
        }
        return { cs: cs, width: x - 1 };
    }
    function piece(cs, x) {
        var last = cs[cs.length - 1];
        return { cs: cs.map(function (k) { return { ch: k.ch, x: k.x - x, w: k.w, mark: k.mark, wi: k.wi, k: k.k }; }), width: last.x - x + last.w };
    }
    var words = tokens(String(text || "").slice(0, 20000)).map(lay).filter(function (w) { return w.cs.length; });
    var pieces = [];                       // words wider than the row are split
    words.forEach(function (w) {
        if (w.width <= MAXW) { pieces.push(w); return; }
        var cur = [], x = 0;
        w.cs.forEach(function (c) {
            if (cur.length && c.x - x + c.w > MAXW) { pieces.push(piece(cur, x)); cur = []; x = c.x; }
            cur.push(c);
        });
        if (cur.length) pieces.push(piece(cur, x));
    });
    var chunks = [], cur2 = [];
    function flush() {
        if (!cur2.length) return;
        var chars = [], x = 0;
        cur2.forEach(function (w, wi) {
            if (wi) x += SPACE;
            w.cs.forEach(function (c) { chars.push({ ch: c.ch, x: x + c.x, w: c.w, mark: c.mark, wi: c.wi, k: c.k }); });
            x += w.width + 1;
        });
        var marks = chars.filter(function (c) { return c.mark; }).length;
        chunks.push({ chars: chars, width: x - 1, marks: marks, dur: MARK_START + marks * MARK_GAP + DWELL });
        cur2 = [];
    }
    pieces.forEach(function (w) {
        var n = cur2.reduce(function (a, w2) { return a + w2.width + 1 + SPACE; }, 0) + w.width;
        if (cur2.length && n > MAXW) flush();
        cur2.push(w);
    });
    flush();
    var starts = [], total = 0;
    chunks.forEach(function (c) { starts.push(total); total += c.dur; });
    return { chunks: chunks, starts: starts, total: total };
}

// the chunk index at loop time q (binary search over the chunk starts)
function chunkAt(prep, q) {
    var lo = 0, hi = prep.chunks.length - 1;
    while (lo < hi) {
        var mid = (lo + hi + 1) >> 1;
        if (prep.starts[mid] <= q) lo = mid; else hi = mid - 1;
    }
    return lo;
}

// the flare of a mark that landed `age` s ago: 1 at once, fading to 0 over FLARE s (the glow, the oversize white mark)
var FLARE = 0.25;
function flareLife(age) {
    if (age < 0 || age >= FLARE) return 0;
    var k = 1 - age / FLARE;
    return k * k;
}

// the mark's moment: the letter pulses once, the mark gets a glow behind it (flare layer) and starts oversize (DotGridCanvas)
function flareMark(g, x, y, w, age) {
    var fl = flareLife(age), pu = Math.exp(-age / 0.16), x1 = x + Math.max(w, 6), rx, ry;
    for (ry = 0; ry < 9; ry++) for (rx = x; rx < x1; rx++) {         // the letter pulses once; the mark gets a glow behind it
        var j = (y + ry) * COLS + rx;
        if (rx >= COLS || g.v[j] <= 0) continue;
        if (g.m[j] > 0.5) F.fxPut(g, rx, y + ry, fl, 0); else g.lf[j] = pu;
    }
    for (ry = -3; ry < 0; ry++) for (rx = x; rx < x1; rx++) {
        var k = (y + ry) * COLS + rx;
        if (rx < COLS && y + ry >= 0 && g.v[k] > 0 && g.m[k] > 0.5) F.fxPut(g, rx, y + ry, fl, 0);
    }
}

// one chunk at time q: letters dissolved in by `alpha`, mark n landing at markStart + n * markGap (or at lands[n] when given)
function drawChunk(g, c, y, q, alpha, markStart, markGap, lands) {
    var x0 = Math.floor((COLS - c.width) / 2), n = 0;
    for (var k = 0; k < c.chars.length; k++) {
        var ch = c.chars[k], x = x0 + ch.x;
        var age = ch.mark ? q - (lands ? lands[n] : markStart + n * markGap) : -1;
        if (ch.mark) n++;
        F.stampChar(g, ch.ch, x, y, alpha, age >= 0 ? alpha : 0, 0, 0);
        if (age >= 0 && age < 0.5) flareMark(g, x, y, ch.w, age);
    }
}

function words(prep, t) {
    var g = F.blank(COLS, ROWS);
    if (!prep || !prep.chunks.length) return g;
    var q = t % prep.total, i = chunkAt(prep, q);
    q -= prep.starts[i];
    var c = prep.chunks[i], dur = c.dur;
    var alpha = Math.min(F.clamp01(q / SWAP), 1 - F.clamp01((q - (dur - SWAP)) / SWAP));
    drawChunk(g, c, BASE_Y, q, alpha, MARK_START, MARK_GAP);
    return g;
}

// ---- replay of the fixed text on `done` ----
// The service has the fixed text only at the end, so the marks cannot flare while it works. On `done` the pill plays the whole
// fixed text again, fast: each chunk in turn (R_IN dissolve in, the marks R_GAP apart, R_HOLD after the last), chunks without marks
// flash by (R_BARE). Everything fits REPLAY_MAX s: first the unmarked chunks are dropped, then the speed rises (down to R_MINSCALE),
// then only the first chunks that fit are shown. The last chunk stays R_TAIL s so its flare can settle before the check.
var REPLAY_MAX = 1.5, R_IN = 0.04, R_GAP = 0.04, R_HOLD = 0.10, R_BARE = 0.05, R_OUT = 0.03, R_TAIL = 0.20, R_MINSCALE = 0.6;

// prep -> { items: [{ i: chunk index, start, dur, s: speed scale }], total }; no marks anywhere = no items (nothing to replay).
// `cont` (the live view carries on into the replay, see liveFinish): { i, dur, q0, lands } = the chunk already on screen, first in the plan,
// continuing at q0 with its own mark times; only the chunks after it are replayed, in what is left of the budget.
function replayPlan(prep, max, cont) {
    var chunks = (prep && prep.chunks) || [], budget = (max || REPLAY_MAX) - R_TAIL, items = [], i;
    function nat(i) { return chunks[i].marks ? R_IN + chunks[i].marks * R_GAP + R_HOLD : R_BARE; }
    function sum(list) { return list.reduce(function (a, k) { return a + nat(k); }, 0); }
    var list = [], t = 0;
    for (i = cont ? cont.i + 1 : 0; i < chunks.length; i++) list.push(i);
    if (cont) {
        items.push({ i: cont.i, start: 0, dur: cont.dur, s: 1, cont: cont });
        t = cont.dur;
        budget = Math.max(budget - cont.dur, 0.2);
        list = list.filter(function (k) { return chunks[k].marks; });
    }
    if (!list.some(function (k) { return chunks[k].marks; })) {
        if (!items.length) return { items: items, total: 0 };
        items[0].dur += R_TAIL;
        return { items: items, total: t + R_TAIL };
    }
    if (sum(list) > budget) list = list.filter(function (k) { return chunks[k].marks; });
    var sc = Math.max(R_MINSCALE, Math.min(1, budget / sum(list))), used = 0;
    for (i = 0; i < list.length; i++) {
        var d = nat(list[i]) * sc;
        if (used + d > budget && used) break;
        items.push({ i: list[i], start: t, dur: d, s: sc });
        t += d;
        used += d;
    }
    items[items.length - 1].dur += R_TAIL;
    return { items: items, total: t + R_TAIL };
}

// the replay picture at time t (held on the last frame after plan.total)
function replay(prep, plan, t) {
    var g = F.blank(COLS, ROWS), items = plan && plan.items;
    if (!items || !items.length) return g;
    var k = 0;
    while (k < items.length - 1 && items[k + 1].start <= t) k++;
    var it = items[k], c = prep.chunks[it.i], q = Math.max(0, Math.min(t, plan.total) - it.start), last = k === items.length - 1;
    var cq = it.cont ? it.cont.q0 + q : q;                      // a continued chunk is already on screen: its own clock
    var alpha = it.cont ? F.clamp01(cq / SWAP) : F.clamp01(q / (R_IN * it.s));
    if (!last) alpha = Math.min(alpha, 1 - F.clamp01((q - (it.dur - R_OUT * it.s)) / (R_OUT * it.s)));
    drawChunk(g, c, BASE_Y, cq, alpha, R_IN * it.s, R_GAP * it.s, it.cont ? it.cont.lands : null);
    return g;
}

// ---- live: the marks flare while the model works ----
// The service streams the fixed text (whole words, `fixed` of the working events). The pill shows the ORIGINAL text's chunks (the layout
// never moves) and, as each fixed word arrives, puts that word's letters and marks in; the marks flare one by one in reading order, MARK_GAP
// apart, never before their word arrived. The chunk on screen stays until all its words arrived and its marks landed (+ LIVE_HOLD), then
// the next one dissolves in; a chunk whose words arrived long ago shows its marks at once, quickly. A fixed word is applied only when it has
// the original's letters (a mark added, nothing else); any other word stays as typed, and the done replay then plays the whole fixed text
// (liveFinish returns null). liveFinish otherwise continues from the chunk on screen: the same flares are never played again.
var LIVE_HOLD = 0.12;
var BASEOF = {};
(function () {
    var a = "ÁÉÍÓÚÝČĚŇŘŠŽĎŤŮáéíóúýčěňřšžďťů", b = "AEIOUYCENRSZDTUaeiouycenrszdtu";
    for (var i = 0; i < a.length; i++) BASEOF[a.charAt(i)] = b.charAt(i);
})();

function laid(word) {
    var o = [];
    for (var i = 0; i < word.length; i++) if (F.advance(word.charAt(i))) o.push(word.charAt(i));
    return o;
}

// text -> live state, or null when there is nothing to show; t0 = the clock (s) when the first chunk comes on screen
function liveNew(text, t0) {
    var prep = prepare(text);
    if (!prep.chunks.length) return null;
    var byWord = {};
    prep.chunks.forEach(function (c) {
        c.chars.forEach(function (ch) { (byWord[ch.wi] = byWord[ch.wi] || []).push(ch); });
    });
    return { prep: prep, toks: tokens(String(text || "").slice(0, 20000)), byWord: byWord, arr: [], n: 0, skipped: 0, extra: false, ci: 0, entry: t0 || 0 };
}

function liveApply(live, i, fixedWord) {
    var o = laid(live.toks[i]), f = laid(fixedWord), k;
    if (!o.length) return;
    if (o.length !== f.length) { live.skipped++; return; }
    for (k = 0; k < o.length; k++) if (o[k] !== f[k] && BASEOF[f[k]] !== o[k]) { live.skipped++; return; }
    (live.byWord[i] || []).forEach(function (ch) { ch.ch = f[ch.k]; ch.mark = F.hasMark(ch.ch); });
    live.prep.chunks.forEach(function (c) {          // the replay plan goes by the marks of the fixed text
        c.marks = c.chars.filter(function (k) { return k.mark; }).length;
    });
}

// the fixed text so far (whole words) arrived at clock t: every new word is put in (or skipped)
function liveFeed(live, fixedText, t) {
    var fw = tokens(String(fixedText || "").slice(0, 20000)), i;
    for (i = live.n; i < fw.length; i++) {
        if (i >= live.toks.length) { live.extra = true; continue; }
        live.arr[i] = t;
        liveApply(live, i, fw[i]);
    }
    live.n = Math.max(live.n, Math.min(fw.length, live.toks.length));
}

// the chunk's mark landing times relative to its entry E, whether all its words arrived, and when the last mark has landed
// A chunk whose words all arrived before it came on screen (the display is behind the model) is "late": it plays faster
// (LATE_START / LATE_GAP / LATE_HOLD), so the picture catches up instead of lagging behind the finished text.
var LATE_START = SWAP, LATE_GAP = 0.03, LATE_HOLD = 0.07;
function liveChunk(live, c, E) {
    var ready = true, lastArr = -1e9, k, ch, a;
    for (k = 0; k < c.chars.length; k++) {
        a = live.arr[c.chars[k].wi];
        if (a === undefined) ready = false; else lastArr = Math.max(lastArr, a - E);
    }
    var late = ready && lastArr <= 0, start = late ? LATE_START : MARK_START, gap = late ? LATE_GAP : MARK_GAP;
    var lands = [], prev = start - gap;
    for (k = 0; k < c.chars.length; k++) {
        ch = c.chars[k]; a = live.arr[ch.wi];
        if (a !== undefined && ch.mark) { prev = Math.max(start, a - E, prev + gap); lands.push(prev); }
    }
    return { lands: lands, ready: ready, hold: late ? LATE_HOLD : LIVE_HOLD, last: Math.max(lands.length ? prev : start, lastArr) };
}

// move on to the next chunk(s) while the one on screen is complete at clock t
function liveStep(live, t) {
    var n = live.prep.chunks.length;
    while (live.ci < n - 1) {
        var info = liveChunk(live, live.prep.chunks[live.ci], live.entry), end = live.entry + info.last + info.hold;
        if (!info.ready || t < end) break;
        live.ci++;
        live.entry = end;
    }
}

function liveScene(live, t) {
    var g = F.blank(COLS, ROWS);
    liveStep(live, t);
    var c = live.prep.chunks[live.ci], q = t - live.entry, info = liveChunk(live, c, live.entry);
    var alpha = F.clamp01(q / SWAP);
    if (info.ready && live.ci < live.prep.chunks.length - 1) alpha = Math.min(alpha, 1 - F.clamp01((q - (info.last + info.hold - SWAP)) / SWAP));
    drawChunk(g, c, BASE_Y, q, alpha, 0, 0, info.lands);
    return g;
}

// the model is done at clock t with the full fixed text: a replay plan (replayPlan / replay with live.prep) that carries on from the
// chunk on screen, or null when the live picture cannot be trusted (a word was skipped, the word counts differ): replay the fixed text then
function liveFinish(live, fixedText, t) {
    liveFeed(live, fixedText, t);
    if (live.skipped || live.extra || live.n < live.toks.length) return null;
    liveStep(live, t);
    var c = live.prep.chunks[live.ci], q0 = t - live.entry, info = liveChunk(live, c, live.entry);
    var pending = info.lands.some(function (l) { return l > q0 - FLARE; });
    if (!pending) {
        var rest = replayPlan(live.prep, REPLAY_MAX, { i: live.ci, dur: 0.001, q0: q0, lands: info.lands });
        return rest.items.length > 1 ? rest : { items: [], total: 0 };       // nothing left to show: the live picture just stays
    }
    return replayPlan(live.prep, REPLAY_MAX, { i: live.ci, dur: Math.max(0.05, info.last + R_HOLD - q0), q0: q0, lands: info.lands });
}

// ---- neutral: pseudo-words filling the row (no real text) ----
var N_CYC = 1.5, N_FILL = 0.85;
function neutral(t, dim) {
    var g = F.blank(COLS, ROWS), sp = dim ? 0.55 : 1;
    var cyc = N_CYC / sp, kc = Math.floor(t / cyc), q = (t - kc * cyc) * sp;       // q in unit-speed seconds
    var target = 54 + Math.floor(F.hash(kc, 99, 1) * 14), segs = [], x = 0, i;
    while (x < target) {
        var w = Math.min(3 + Math.floor(F.hash(kc, x, 7) * 8), target - x);
        segs.push({ x: x, w: w });
        x += w + SPACE;
    }
    var width = x - SPACE, x0 = Math.floor((COLS - width) / 2), head = (q / N_FILL) * (width + 3);
    var alpha = Math.min(F.clamp01(q / SWAP), 1 - F.clamp01((q - (N_CYC - SWAP)) / SWAP)), vm = dim ? 0.5 : 1;
    for (i = 0; i < segs.length; i++) {
        var s = segs[i];
        for (var cx = 0; cx < s.w; cx++) {
            var col = s.x + cx, lit = F.clamp01((head - col) / 3);
            if (lit <= 0) continue;
            for (var ry = 5; ry <= 7; ry++) {
                if (ry !== 6 && F.hash(x0 + col, ry, 4) < 0.62) continue;      // the middle row is solid, the rows around it are dithered
                var v = F.clamp01((alpha - F.hash(x0 + col, ry, 3)) * 4 + 0.15) * (alpha > 0 ? 1 : 0) * lit * vm;
                if (v > 0.02) F.put(g, x0 + col, ry, v, 0);
            }
        }
        if (dim || F.hash(kc, i, 5) < 0.45 || s.w < 4) continue;
        var mid = s.x + (s.w >> 1), age = q - (mid / (width + 3)) * N_FILL - 0.14;
        if (age < 0) continue;
        var caron = F.hash(kc, i, 6) < 0.5, mx = x0 + mid, a = Math.min(1, age * 12) * alpha;
        var dots = caron ? [[-1, 3], [1, 3], [0, 4]] : [[1, 3], [0, 4]];
        dots.forEach(function (d) { F.put(g, mx + d[0], d[1], F.clamp01(a), 1); });
        if (age < 0.5) {
            var fl = flareLife(age), pu = Math.exp(-age / 0.16);
            dots.forEach(function (d) { F.fxPut(g, mx + d[0], d[1], fl, 0); });
            for (var px = x0 + s.x; px < x0 + s.x + s.w; px++) for (var py = 5; py <= 7; py++) {
                var j = py * COLS + px;
                if (g.v[j] > 0) g.lf[j] = pu;
            }
        }
    }
    return g;
}

// ---- the end states over the fading working picture. state: working | done | failed | unsupported; sT = seconds since the state began ----
// `live` (words only): the live state (liveNew) whose picture replaces the looping one; t is then the live clock
function scene(kind, state, t, sT, prep, plan, live) {
    var v = kind === "neutral" ? neutral(t, false) : kind === "loading" ? neutral(t, true) : kind === "replay" ? replay(prep, plan, t)
          : live ? liveScene(live, t) : words(prep, t);
    if (state === "working" || state === "loading" || state === "replay") return v;
    var g = F.blank(COLS, ROWS), fade = 1 - F.clamp01(sT / 0.2), i;
    if (fade > 0) for (i = 0; i < g.v.length; i++) { g.v[i] = v.v[i] * fade; g.m[i] = v.m[i]; g.fv[i] = v.fv[i] * fade; g.fs[i] = v.fs[i]; g.lf[i] = v.lf[i]; }
    var d = F.clamp01((sT - 0.15) / (state === "unsupported" ? 0.6 : 0.35));
    if (state === "done") {
        F.shapes.check(g, 38, 7, d, 1, 0);
        var flash = F.clamp01(1 - (sT - 0.5) / 0.35);
        if (d >= 1 && flash > 0) for (var k = -12; k <= 12; k += 4) F.put(g, 38 + k + 1, k % 8 === 0 ? 1 : 12, flash * 0.8, 0);
    } else if (state === "failed") {
        var shake = Math.round(Math.sin(sT * 55) * 2 * (1 - F.clamp01((sT - 0.45) / 0.3)) * (d >= 1 ? 1 : 0));
        F.shapes.cross(g, 38 + shake, 6, d, 1, 0);
    } else F.shapes.nosign(g, 38, 6, d, 0.9, 0);
    return g;
}
