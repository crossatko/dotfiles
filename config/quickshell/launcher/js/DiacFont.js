.pragma library

// Dot font of the diacritics pill (DiacPill / DiacDots): mixed-case 5x7 Czech letters with descenders, accent marks and dot-drawn
// state icons, rasterised into plain grids. Pure functions, no processes; tests: node --test launcher/js/tests/diacfont.test.js
// A grid is { c, r, v, m, fv, fs, lf } (columns, rows, then c*r cells each):
//   v   dot intensity 0..1 (letters, marks, icons)        m   mix to the mark colour 0..1
//   fv  accent flare intensity (the mark's glow)          fs  flare position 0..1 (0 = bright head)
//   lf  letter pulse 0..1 (the letter that just got its mark)
// A glyph is up to 9 rows: capitals and ascenders on rows 0..6, the x-height band on rows 2..6, descenders on rows 7..8; the base band
// (rows 0..6) is what the scene centres. Widths vary (i l j f t are narrow), advance = width + 1. A mark sits above the glyph's
// top row (acute and caron with one empty row between, the ring right on it); d / t take the apostrophe to their right instead. Marks differ in SHAPE, not just position, so they read apart at 3.8 px
// pitch: acute = two dots on a slant, caron = a V, ring = a closed 3x3 diamond (three rows tall).

var glyphs = {};
// rows: object { rowIndex: pattern } on a w-wide cell, 9 rows
function G(ch, w, rows) {
    var r = [];
    for (var i = 0; i < 9; i++) r.push(rows[i] || "0".repeat(w));
    glyphs[ch] = { w: w, rows: r };
}
var caps = {
    A: ["01110", "10001", "10001", "11111", "10001", "10001", "10001"], B: ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    C: ["01110", "10001", "10000", "10000", "10000", "10001", "01110"], D: ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    E: ["11111", "10000", "10000", "11110", "10000", "10000", "11111"], F: ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    G: ["01110", "10001", "10000", "10111", "10001", "10001", "01111"], H: ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    I: ["01110", "00100", "00100", "00100", "00100", "00100", "01110"], J: ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
    K: ["10001", "10010", "10100", "11000", "10100", "10010", "10001"], L: ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    M: ["10001", "11011", "10101", "10101", "10001", "10001", "10001"], N: ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    O: ["01110", "10001", "10001", "10001", "10001", "10001", "01110"], P: ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    Q: ["01110", "10001", "10001", "10001", "10101", "10010", "01101"], R: ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    S: ["01111", "10000", "10000", "01110", "00001", "00001", "11110"], T: ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    U: ["10001", "10001", "10001", "10001", "10001", "10001", "01110"], V: ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    W: ["10001", "10001", "10001", "10101", "10101", "11011", "10001"], X: ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    Y: ["10001", "10001", "01010", "00100", "00100", "00100", "00100"], Z: ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    0: ["01110", "10001", "10011", "10101", "11001", "10001", "01110"], 1: ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    2: ["01110", "10001", "00001", "00010", "00100", "01000", "11111"], 3: ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    4: ["00010", "00110", "01010", "10010", "11111", "00010", "00010"], 5: ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    6: ["00110", "01000", "10000", "11110", "10001", "10001", "01110"], 7: ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    8: ["01110", "10001", "10001", "01110", "10001", "10001", "01110"], 9: ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    "?": ["01110", "10001", "00001", "00110", "00100", "00000", "00100"], "@": ["01110", "10001", "10111", "10101", "10111", "10000", "01110"],
    "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"]
};
for (var k in caps) glyphs[k] = { w: 5, rows: caps[k].concat(["00000", "00000"]) };
// lowercase: x-height rows 2..6, ascenders from row 0, descenders rows 7..8
function X(from, rows7, desc) {
    var o = {};
    rows7.forEach(function (p, i) { o[from + i] = p; });
    (desc || []).forEach(function (p, i) { o[7 + i] = p; });
    return o;
}
G("a", 5, X(2, ["01110", "00001", "01111", "10001", "01111"]));
G("b", 5, X(0, ["10000", "10000", "10110", "11001", "10001", "11001", "10110"]));
G("c", 5, X(2, ["01110", "10001", "10000", "10001", "01110"]));
G("d", 4, X(0, ["0001", "0001", "0111", "1001", "1001", "1001", "0111"]));
G("e", 5, X(2, ["01110", "10001", "11111", "10000", "01110"]));
G("f", 4, X(0, ["0110", "1000", "1110", "1000", "1000", "1000", "1000"]));
G("g", 5, X(2, ["01110", "10001", "10001", "01111", "00001"], ["10001", "01110"]));
G("h", 5, X(0, ["10000", "10000", "10110", "11001", "10001", "10001", "10001"]));
// i: a dot, one empty row, a plain x-height stem (no flag, no foot: that would read as the digit 1; l is the same stem running up to the ascender
// row); j the same with a hooked descender; the dotless i (for í) is the bare stem, the acute stands where the dot was
G("i", 3, X(0, ["010", "000", "010", "010", "010", "010", "010"]));
G("ı", 3, X(2, ["010", "010", "010", "010", "010"]));
G("j", 3, X(0, ["001", "000", "001", "001", "001", "001", "001"], ["001", "110"]));
G("k", 5, X(0, ["10000", "10000", "10010", "10100", "11000", "10100", "10010"]));
G("l", 3, X(0, ["010", "010", "010", "010", "010", "010", "010"]));
G("m", 5, X(2, ["11010", "10101", "10101", "10101", "10101"]));
G("n", 5, X(2, ["10110", "11001", "10001", "10001", "10001"]));
G("o", 5, X(2, ["01110", "10001", "10001", "10001", "01110"]));
G("p", 5, X(2, ["10110", "11001", "10001", "11001", "10110"], ["10000", "10000"]));
G("q", 5, X(2, ["01101", "10011", "10001", "10011", "01101"], ["00001", "00001"]));
G("r", 5, X(2, ["10110", "11001", "10000", "10000", "10000"]));
G("s", 5, X(2, ["01111", "10000", "01110", "00001", "11110"]));
G("t", 4, X(1, ["0100", "1110", "0100", "0100", "0100", "0011"]));
G("u", 5, X(2, ["10001", "10001", "10001", "10011", "01101"]));
G("v", 5, X(2, ["10001", "10001", "10001", "01010", "00100"]));
G("w", 5, X(2, ["10001", "10001", "10101", "10101", "01010"]));
G("x", 5, X(2, ["10001", "01010", "00100", "01010", "10001"]));
G("y", 5, X(2, ["10001", "10001", "10001", "01111", "00001"], ["10001", "01110"]));
G("z", 5, X(2, ["11111", "00010", "00100", "01000", "11111"]));
G(".", 1, X(6, ["1"])); G(",", 2, X(6, ["01"], ["10"])); G("!", 1, X(0, ["1", "1", "1", "1", "1", "0", "1"]));
G("-", 3, X(4, ["111"])); G(":", 1, X(3, ["1", "0", "0", "1"])); G("'", 1, X(0, ["1", "1"]));
G("(", 2, X(0, ["01", "10", "10", "10", "10", "10", "01"])); G(")", 2, X(0, ["10", "01", "01", "01", "01", "01", "10"]));
G(";", 2, X(3, ["01", "00", "00", "01"], ["10"])); G("\"", 3, X(0, ["101", "101"]));

// marks by glyph width (rows top to bottom, centred over the glyph)
// An acute or caron floats one empty row above the letter (GAP) so it never merges with the stem (an acute on the stem of i reads as
// the digit 1, one on the a blobs into it); the ring is a closed shape and sits right on the letter.
var GAP = { acute: 1, caron: 1, ring: 0 };
var marks = {
    5: { caron: ["01010", "00100"], acute: ["00010", "00100"], ring: ["010", "101", "010"] },
    3: { caron: ["101", "010"], acute: ["001", "010"], ring: ["010", "101", "010"] }
};
// letter -> [base glyph, mark, (apostrophe column, row)]
var accented = {};
function acc(chars, bases, mark) { for (var i = 0; i < chars.length; i++) accented[chars[i]] = [bases[i], mark]; }
acc("ÁÉÍÓÚÝ", "AEIOUY", "acute"); acc("áéóúý", "aeouy", "acute"); accented["í"] = ["ı", "acute"];
acc("ČĚŇŘŠŽĎŤ", "CENRSZDT", "caron"); acc("ěčňřšž", "ecnrsz", "caron");
accented["Ů"] = ["U", "ring"]; accented["ů"] = ["u", "ring"];
accented["ď"] = ["d", "apos", 4, 0]; accented["ť"] = ["t", "apos", 3, 0];

// a character's glyph (and mark); characters the font lacks fall back to their base letter without the accent (ö -> o), else null
function glyphOf(ch) {
    var a = accented[ch], g = glyphs[a ? a[0] : ch];
    if (!g && !a) {
        var b = ch.normalize ? ch.normalize("NFD").charAt(0) : "";
        if (b && b !== ch) { g = glyphs[b]; a = null }
    }
    return g ? { g: g, a: a } : null;
}
// advance in columns (width + 1 gap); an accented letter is as wide as its base letter (an apostrophe sits in the gap column or inside the
// glyph), so fixing a letter never changes the layout
function advance(ch) {
    var o = glyphOf(ch);
    return o ? o.g.w + 1 : 0;
}
function hasMark(ch) { return !!accented[ch]; }
function top(g) { return g.rows.findIndex(function (r) { return r.indexOf("1") >= 0; }); }

function blank(c, r) {
    function z() { return new Array(c * r).fill(0); }
    return { c: c, r: r, v: z(), m: z(), fv: z(), fs: z(), lf: z() };
}
function hash(a, b, c) {
    var h = (a * 374761393 + b * 668265263 + (c || 0) * 2147483647) | 0;
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}
function put(g, x, y, v, m) {
    if (x < 0 || y < 0 || x >= g.c || y >= g.r) return;
    var i = y * g.c + x;
    if (v > g.v[i]) { g.v[i] = v; g.m[i] = m; }
}
function clamp01(x) { return Math.max(0, Math.min(1, x)); }
// the flare layer: the brighter value wins
function fxPut(g, x, y, v, s) {
    if (x < 0 || y < 0 || x >= g.c || y >= g.r) return;
    var i = y * g.c + x;
    if (v > g.fv[i]) { g.fv[i] = v; g.fs[i] = s; }
}

// y = the row of the capital top (the base band is rows y..y+6); a = letter dissolve 0..1; markA = mark dissolve
function stampChar(g, ch, x, y, a, markA, markDy, tint) {
    var o = glyphOf(ch);
    if (!o) return;
    var gl = o.g, ac = o.a;
    for (var ry = 0; ry < 9; ry++) for (var rx = 0; rx < gl.w; rx++) {
        if (gl.rows[ry][rx] !== "1") continue;
        var v = Math.max(0, Math.min(1, (a - hash(x + rx, y + ry, 3)) * 4 + 0.15)) * (a > 0 ? 1 : 0);
        if (v > 0.02) put(g, x + rx, y + ry, v, tint || 0);
    }
    if (ac && markA > 0) {
        var draw = function (rx, ry, salt) {
            var v = Math.max(0, Math.min(1, (markA - hash(x + rx, y + ry, salt)) * 4 + 0.2));
            if (v > 0.02) put(g, x + rx, y + ry + (markDy || 0), v, 1);
        };
        if (ac[1] === "apos") {
            for (var k = 0; k < 2; k++) draw(ac[2], ac[3] + k, 9);
        } else {
            var mr = (marks[gl.w] || marks[5])[ac[1]], t = top(gl) - GAP[ac[1]], off = Math.floor((gl.w - mr[0].length) / 2);
            for (var my = 0; my < mr.length; my++) for (var mx = 0; mx < mr[0].length; mx++)
                if (mr[my][mx] === "1") draw(mx + off, t - mr.length + my, 9);
        }
    }
}

// ---- state icons: progress 0..1 draws the shape dot by dot (2 dots thick) ----
function drawPts(g, pts, progress, cx, cy, v, m) {
    var n = Math.round(pts.length * clamp01(progress));
    for (var i = 0; i < n; i++) {
        var lead = n < pts.length && i >= n - 2 ? 0.6 : 1;       // the drawing head glows softer
        put(g, cx + pts[i][0], cy + pts[i][1], v * lead, m);
        put(g, cx + pts[i][0] + 1, cy + pts[i][1], v * lead, m);
    }
}
var shapes = {
    check: function (g, cx, cy, p, v, m) {
        var pts = [], i;
        for (i = 0; i < 3; i++) pts.push([-5 + i, -1 + i]);
        for (i = 0; i < 7; i++) pts.push([-2 + i, 2 - i]);
        drawPts(g, pts, p, cx, cy, v, m);
    },
    cross: function (g, cx, cy, p, v, m) {
        var pts = [], i;
        for (i = -3; i <= 3; i++) pts.push([i, i]);
        for (i = -3; i <= 3; i++) pts.push([i, -i]);
        drawPts(g, pts, p, cx, cy, v, m);
    },
    nosign: function (g, cx, cy, progress, v, m) {            // circle with a slash: the ring sweeps round, then the slash
        var R = 4.3, ring = [], slash = [];
        for (var y = -5; y <= 5; y++) for (var x = -5; x <= 5; x++) {
            var d = Math.sqrt(x * x + y * y);
            if (Math.abs(d - R) < 0.55) ring.push([x, y, Math.atan2(y, x)]);
            if (x === -y && d < R) slash.push([x, y]);
        }
        ring.sort(function (a, b) { return a[2] - b[2]; });
        var p = clamp01(progress), nr = Math.round(ring.length * Math.min(1, p / 0.7)), i;
        for (i = 0; i < nr; i++) put(g, cx + ring[i][0], cy + ring[i][1], v, m);
        var ns = Math.round(slash.length * Math.max(0, (p - 0.7) / 0.3));
        for (i = 0; i < ns; i++) put(g, cx + slash[i][0], cy + slash[i][1], v, m);
    }
};
