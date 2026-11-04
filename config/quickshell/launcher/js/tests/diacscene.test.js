const test = require("node:test");
const assert = require("node:assert");
const { load } = require("./load");
const S = load("DiacScene.js");
const F = S.F;

const lit = g => g.v.reduce((n, v) => n + (v > 0 ? 1 : 0), 0);
const rows = g => { const o = []; for (let y = 0; y < g.r; y++) { let s = ""; for (let x = 0; x < g.c; x++) s += g.v[y * g.c + x] > 0 ? "#" : "."; o.push(s); } return o; };
// the dots of one stamped character as text rows (x-aligned, empty rows trimmed)
function glyphRows(ch) {
    const g = F.blank(12, 13);
    F.stampChar(g, ch, 3, 3, 1, 1, 0, 0);
    return rows(g).map(r => r.slice(3, 10)).filter(r => r.includes("#"));
}

test("marks differ in shape: acute, caron and ring are three distinct patterns", () => {
    const [a, c, r] = ["á", "č", "ů"].map(ch => glyphRows(ch).slice(0, 3).join("/"));
    assert.notStrictEqual(a, c);
    assert.notStrictEqual(c, r);
    assert.notStrictEqual(a, r);
    // the ring is a closed shape three rows tall above u, the others two rows
    assert.deepStrictEqual(glyphRows("ů").slice(0, 3), ["..#....", ".#.#...", "..#...."]);
    assert.deepStrictEqual(glyphRows("č").slice(0, 2), [".#.#...", "..#...."]);
});

test("an unmarked i is not the digit 1", () => {
    assert.notDeepStrictEqual(glyphRows("i"), glyphRows("1"));
    const i = glyphRows("i");
    assert.strictEqual(i[0].trim(), ".#.....".trim());          // the dot
    assert.strictEqual(i.length, 6);                            // dot + five stem rows (the gap row is empty and dropped)
});

test("characters without a glyph fall back to their base letter; unknown ones are skipped", () => {
    assert.ok(F.advance("ö") > 0);
    assert.strictEqual(F.advance("€"), 0);
});

test("prepare: chunks fit the row and keep word order", () => {
    const p = S.prepare("Dobry den, posilam vam upravenou nabidku na zitrek ve ctrnact hodin. Prosim o potvrzeni terminu");
    assert.ok(p.chunks.length > 1);
    p.chunks.forEach(c => assert.ok(c.width <= 76 && c.width > 0));
    assert.strictEqual(p.chunks[0].chars[0].ch, "D");
    assert.ok(Math.abs(p.total - p.chunks.reduce((n, c) => n + c.dur, 0)) < 1e-9);
});

test("prepare: a word wider than the row is split, empty text has no chunks", () => {
    const p = S.prepare("Nejnepravdepodobnejsiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii");
    assert.ok(p.chunks.length >= 2);
    assert.strictEqual(S.prepare("   ").chunks.length, 0);
    assert.strictEqual(lit(S.words(S.prepare(""), 1)), 0);
});

test("words: the marks appear one by one, 0.04 s apart, with a flare", () => {
    const p = S.prepare("ěščř");
    const at = t => S.words(p, t);
    const marks = g => g.m.filter(m => m > 0.5).length;
    assert.strictEqual(marks(at(0.075)), 0);                   // swapped in, no mark yet
    const n1 = marks(at(0.095)), n4 = marks(at(0.08 + 3 * 0.04 + 0.1));
    assert.ok(n1 > 0 && n4 > n1);
    assert.ok(at(0.095).fv.some(v => v > 0.5));                // flare while the first mark lands
    assert.ok(at(0.095).lf.some(v => v > 0.5));                // and its letter pulses
});

test("words: loops, and the chunk swap dissolves the picture", () => {
    const p = S.prepare("ahoj");
    assert.deepStrictEqual(S.words(p, 0.2).v, S.words(p, 0.2 + p.total).v);
    assert.ok(lit(S.words(p, 0.001)) < lit(S.words(p, 0.2)));
});

test("neutral: draws dots without text, dim is quieter, no marks while dim", () => {
    const g = S.neutral(1.0, false), d = S.neutral(1.0, true);
    assert.ok(lit(g) > 20);
    assert.ok(Math.max(...d.v) <= 0.5 + 1e-9);
    assert.ok(!d.m.some(m => m > 0));
    let marks = 0;
    for (let k = 0; k < 6; k++) marks += S.neutral(k * 1.5 + 1.2, false).m.filter(m => m > 0.5).length;
    assert.ok(marks > 0);
});

test("scene: end states fade the picture, then draw their icon", () => {
    const p = S.prepare("ahoj");
    for (const st of ["done", "failed", "unsupported"]) {
        assert.strictEqual(lit(S.scene("words", st, 5, 0.0, p)) > 0, true);       // still the picture at 0 s
        const full = S.scene("words", st, 5, 1.0, p);
        assert.ok(lit(full) > 8, st);
        assert.ok(!full.m.some(m => m > 0), st);                                   // icons carry no mark colour
    }
    assert.strictEqual(lit(S.scene("words", "unsupported", 5, 0.1, null)), 0);
});
