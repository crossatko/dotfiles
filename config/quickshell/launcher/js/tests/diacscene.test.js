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

test("marks float one empty row above the letter (acute, caron), the ring sits on it; every Czech letter has its mark", () => {
    const rowsOf = ch => { const g = F.blank(12, 13); F.stampChar(g, ch, 3, 3, 1, 1, 0, 0); return rows(g).map(r => r.slice(3, 10)); };
    for (const ch of "áéíóúýěčňřšžÁÉÍÓÚÝĚČŇŘŠŽ") {
        const r = rowsOf(ch), first = r.findIndex(x => x.includes("#")), mark = r.findIndex((x, i) => i > first && !x.includes("#"));
        assert.ok(mark > first, ch + " has a gap row under its mark");      // mark rows, an empty row, then the letter
    }
    for (const ch of "ůŮ") { const r = rowsOf(ch), f = r.findIndex(x => x.includes("#")); assert.ok(r.slice(f, f + 5).every(x => x.includes("#")), ch + " ring sits on the letter (no empty row)"); }
    for (const ch of "ďť") assert.ok(F.hasMark(ch));
    assert.notDeepStrictEqual(glyphRows("í"), glyphRows("1"));
    assert.strictEqual(glyphRows("í").length, 5 + 2);                      // acute (2 rows) + stem (5 rows)
});

test("replayPlan: a short text plays every chunk at natural speed, marks 0.04 s apart, last chunk lingers", () => {
    const p = S.prepare("Dobrý den, posílám vám nabídku");
    const pl = S.replayPlan(p);
    assert.strictEqual(pl.items.length, p.chunks.length);
    assert.ok(pl.total <= 1.5 + 1e-9);
    assert.strictEqual(pl.items[0].s, 1);
    const c0 = p.chunks[0];
    assert.ok(Math.abs(pl.items[0].dur - (0.04 + c0.marks * 0.04 + 0.10)) < 1e-9);
    assert.ok(pl.items[pl.items.length - 1].dur > 0.2);
    for (let i = 1; i < pl.items.length; i++) assert.ok(Math.abs(pl.items[i].start - (pl.items[i - 1].start + pl.items[i - 1].dur)) < 1e-9);
});

test("replayPlan: long text fits 1.5 s (unmarked chunks dropped, then faster, then only the first chunks)", () => {
    const some = "Dobrý den, posílám vám upravenou nabídku na zítřek ve čtrnáct hodin. ", plain = "Prosim o potvrzeni terminu a dalsich veci. ";
    const mixed = S.replayPlan(S.prepare((some + plain).repeat(3)));
    assert.ok(mixed.total <= 1.5 + 1e-9);
    const huge = S.prepare((some + plain).repeat(60)), pl = S.replayPlan(huge);
    assert.ok(pl.total <= 1.5 + 1e-9 && pl.items.length >= 1 && pl.items.length < huge.chunks.length);
    assert.ok(pl.items.every(it => huge.chunks[it.i].marks > 0), "only chunks with marks");
    assert.ok(pl.items.every(it => it.s >= 0.6 - 1e-9));
    for (let i = 1; i < pl.items.length; i++) assert.ok(pl.items[i].i > pl.items[i - 1].i, "reading order");
});

test("replayPlan: unmarked chunks flash by when the text is short; no marks anywhere = nothing to replay", () => {
    const p = S.prepare("Prosim o potvrzeni terminu na zitrek ve ctrnact hodin, dekuji ěš");
    const pl = S.replayPlan(p);
    assert.ok(pl.items.some(it => p.chunks[it.i].marks === 0) || p.chunks.every(c => c.marks > 0));
    assert.strictEqual(S.replayPlan(S.prepare("Prosim o potvrzeni")).items.length, 0);
    assert.strictEqual(S.replayPlan(S.prepare("")).items.length, 0);
});

test("replay: marks land in reading order with a flare, last frame is held, then scene fades it for the check", () => {
    const p = S.prepare("ěščř"), pl = S.replayPlan(p), at = t => S.replay(p, pl, t);
    const marks = g => g.m.filter(m => m > 0.5).length;
    assert.strictEqual(marks(at(0.03)), 0);
    const n1 = marks(at(0.045)), n4 = marks(at(0.04 + 3 * 0.04 + 0.03));
    assert.ok(n1 > 0 && n4 > n1);
    assert.ok(at(0.045).fv.some(v => v > 0.7));                  // strong flare at the moment the mark lands
    assert.strictEqual(Math.max(...at(0.04 + 0.04 + 0.04 + 0.04 + 0.3).fv), 0);   // flare gone after 0.25 s
    assert.deepStrictEqual(at(pl.total).v, at(pl.total + 5).v);  // held on the last frame
    const d = S.scene("replay", "done", pl.total, 0.1, p, pl);
    assert.ok(lit(d) > 0 && lit(d) <= lit(at(pl.total)) + 40);
    assert.ok(S.scene("replay", "done", pl.total, 0.6, p, pl).v.some(v => v > 0));   // the check is drawing
});

test("flareLife: 1 at once, 0 after 0.25 s", () => {
    assert.strictEqual(S.flareLife(0), 1);
    assert.ok(S.flareLife(0.12) > 0.2 && S.flareLife(0.12) < 0.5);
    assert.strictEqual(S.flareLife(0.25), 0);
    assert.strictEqual(S.flareLife(-1), 0);
});
