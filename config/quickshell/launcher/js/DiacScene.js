.pragma library
.import "DiacFont.js" as F

// Scenes of the diacritics pill (DiacDots): pure functions of time returning a dot grid (DiacFont.js layout, only lit dots, no
// background dots). Port of the approved "Flare" prototype (variant c1):
//   words    the real words, cut into chunks that fit the row (about 15 characters), swapped word over word; each chunk stands still,
//            centred, the base letters optically centred with the marks above; the marks appear one by one in reading order
//            (MARK_GAP apart), each with a short accent flare that settles to white while its letter pulses once; READ s dwell after the last
//   neutral  the same look without the words (Settings: show text off): pseudo-words as dotted lines fill the row left to right, marks
//            pop up over some of them with the same flare; `dim` = the loading variant (slower, no marks, half bright)
//   end states  the working picture lets go (0.2 s), then the icon draws in dot by dot: done = check + sparks, failed = cross that
//            shakes, unsupported = no-sign
// Timings are seconds; the grid is COLS x ROWS with the 7-row base band on rows 3..9 (the card's centre line).
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
    function lay(w) {
        var cs = [], x = 0;
        for (var i = 0; i < w.length; i++) {
            var ch = w.charAt(i), adv = F.advance(ch);
            if (!adv) continue;
            cs.push({ ch: ch, x: x, w: adv - 1, mark: F.hasMark(ch) });
            x += adv;
        }
        return { cs: cs, width: x - 1 };
    }
    function piece(cs, x) {
        var last = cs[cs.length - 1];
        return { cs: cs.map(function (k) { return { ch: k.ch, x: k.x - x, w: k.w, mark: k.mark }; }), width: last.x - x + last.w };
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
            w.cs.forEach(function (c) { chars.push({ ch: c.ch, x: x + c.x, w: c.w, mark: c.mark }); });
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

// the mark's moment: the letter pulses once, the mark gets a glow behind it (flare layer)
function flareMark(g, x, y, w, age) {
    var fl = Math.exp(-age / 0.12), pu = Math.exp(-age / 0.16), x1 = x + Math.max(w, 6), rx, ry;
    for (ry = 0; ry < 9; ry++) for (rx = x; rx < x1; rx++) {         // the letter pulses once; the mark gets a glow behind it
        var j = (y + ry) * COLS + rx;
        if (rx >= COLS || g.v[j] <= 0) continue;
        if (g.m[j] > 0.5) F.fxPut(g, rx, y + ry, fl, 0); else g.lf[j] = pu * 0.9;
    }
    for (ry = -3; ry < 0; ry++) for (rx = x; rx < x1; rx++) {
        var k = (y + ry) * COLS + rx;
        if (rx < COLS && y + ry >= 0 && g.v[k] > 0 && g.m[k] > 0.5) F.fxPut(g, rx, y + ry, fl, 0);
    }
}

function words(prep, t) {
    var g = F.blank(COLS, ROWS), y = BASE_Y;
    if (!prep || !prep.chunks.length) return g;
    var q = t % prep.total, i = chunkAt(prep, q);
    q -= prep.starts[i];
    var c = prep.chunks[i], dur = c.dur, x0 = Math.floor((COLS - c.width) / 2);
    var alpha = Math.min(F.clamp01(q / SWAP), 1 - F.clamp01((q - (dur - SWAP)) / SWAP));
    var n = 0;
    for (var k = 0; k < c.chars.length; k++) {
        var ch = c.chars[k], x = x0 + ch.x;
        var age = ch.mark ? q - (MARK_START + n * MARK_GAP) : -1;
        if (ch.mark) n++;
        F.stampChar(g, ch.ch, x, y, alpha, age >= 0 ? alpha : 0, 0, 0);
        if (age >= 0 && age < 0.5) flareMark(g, x, y, ch.w, age);
    }
    return g;
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
            var fl = Math.exp(-age / 0.12), pu = Math.exp(-age / 0.16);
            dots.forEach(function (d) { F.fxPut(g, mx + d[0], d[1], fl, 0); });
            for (var px = x0 + s.x; px < x0 + s.x + s.w; px++) for (var py = 5; py <= 7; py++) {
                var j = py * COLS + px;
                if (g.v[j] > 0) g.lf[j] = pu * 0.9;
            }
        }
    }
    return g;
}

// ---- the end states over the fading working picture. state: working | done | failed | unsupported; sT = seconds since the state began ----
function scene(kind, state, t, sT, prep) {
    var v = kind === "neutral" ? neutral(t, false) : kind === "loading" ? neutral(t, true) : words(prep, t);
    if (state === "working" || state === "loading") return v;
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
