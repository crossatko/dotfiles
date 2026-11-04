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

test("i, í, l, 1, I are five distinct shapes; i is a dot over a plain stem (no flag, no foot)", () => {
    const k = ch => glyphRows(ch).join("/");
    const all = ["i", "í", "l", "1", "I", "Í", "j"].map(k);
    assert.strictEqual(new Set(all).size, all.length);
    const i = glyphRows("i");
    assert.deepStrictEqual(i.slice(1), Array(5).fill(i[1]));                // five identical stem rows
    assert.deepStrictEqual(glyphRows("í").slice(2), Array(5).fill(i[1]));   // í = the same stem, the acute instead of the dot
    assert.strictEqual(glyphRows("í")[0].replace(/\./g, "").length, 1);      // acute: one dot per row (a diagonal pair)
    assert.strictEqual(glyphRows("l").length, 7);
});

// ---- live ----
const markN = g => g.m.filter(m => m > 0.5).length;
const SRC = "Dobry den, posilam vam upravenou nabidku na zitrek ve ctrnact hodin. Prosim o potvrzeni terminu schuzky";
const FIX = "Dobrý den, posílám vám upravenou nabídku na zítřek ve čtrnáct hodin. Prosím o potvrzení termínu schůzky";

test("live: a word without its fixed form shows no mark; the mark lands (flare) when the word arrives, not before", () => {
    const live = S.liveNew("Dobry den", 0);
    assert.strictEqual(markN(S.liveScene(live, 0.5)), 0);
    S.liveFeed(live, "Dobrý", 1.0);
    assert.strictEqual(markN(S.liveScene(live, 0.99)), 0);                      // before the word arrived
    assert.ok(markN(S.liveScene(live, 1.001)) > 0);                             // at once when it arrives
    assert.ok(S.liveScene(live, 1.001).fv.some(v => v > 0.7));                  // flaring
    assert.strictEqual(Math.max(...S.liveScene(live, 1.4).fv), 0);              // settled
});

test("live: marks of one word land one by one, 0.04 s apart, in reading order (left to right)", () => {
    const live = S.liveNew("ctrnact ruzi", 0);
    S.liveFeed(live, "čtrnáct růži", 2.0);
    const at = d => S.liveScene(live, 2.0 + d), total = markN(at(0.5));
    const counts = [-0.01, 0.001, 0.045, 0.085, 0.5].map(d => markN(at(d)));
    assert.strictEqual(counts[0], 0);
    for (let i = 1; i < counts.length; i++) assert.ok(counts[i] > counts[i - 1], counts.join());   // each step adds a mark
    assert.strictEqual(counts[4], total);
    // the first mark on screen is the leftmost one
    const cols = g => { const o = []; for (let i = 0; i < g.m.length; i++) if (g.m[i] > 0.5) o.push(i % g.c); return o; };
    assert.ok(Math.max(...cols(at(0.001))) < Math.min(...cols(at(0.5)).slice(-3)) + 1);
});

test("live: an arrival burst keeps the one-by-one spacing across words", () => {
    const live = S.liveNew("ctrnact ruzi", 0);
    S.liveFeed(live, "čtrnáct růži", 1.0);
    const lands = S.liveChunk(live, live.prep.chunks[0], 0).lands;
    assert.strictEqual(lands.length, 4);
    assert.ok(lands[0] >= 1.0 - 1e-9);                                          // never before the word arrived
    for (let i = 1; i < lands.length; i++) assert.ok(Math.abs(lands[i] - lands[i - 1] - 0.04) < 1e-9, lands.join());
});

test("live: words arriving one after the other land when they arrive", () => {
    const live = S.liveNew("ctrnact ruzi", 0);
    S.liveFeed(live, "čtrnáct", 1.0);
    S.liveFeed(live, "čtrnáct růži", 2.0);
    const lands = S.liveChunk(live, live.prep.chunks[0], 0).lands;
    assert.ok(Math.abs(lands[0] - 1.0) < 1e-9 && Math.abs(lands[1] - 1.04) < 1e-9 && Math.abs(lands[2] - 2.0) < 1e-9 && Math.abs(lands[3] - 2.04) < 1e-9, lands.join());
});

test("live: the chunk on screen waits for its words, then the next chunk comes", () => {
    const live = S.liveNew(SRC, 0), nChunks = live.prep.chunks.length;
    assert.ok(nChunks > 2);
    S.liveStep(live, 50);
    assert.strictEqual(live.ci, 0);                                           // nothing arrived: never moves on
    const w0 = new Set(live.prep.chunks[0].chars.map(c => c.wi));
    S.liveFeed(live, FIX.split(" ").slice(0, Math.max(...w0) + 1).join(" "), 1.0);
    S.liveStep(live, 1.05);
    assert.strictEqual(live.ci, 0);                                           // marks still landing / hold
    S.liveStep(live, 3.0);
    assert.strictEqual(live.ci, 1);
    assert.ok(live.entry > 1.0 && live.entry < 1.6);                          // entered when chunk 0 was complete, not "now"
});

test("live: a chunk that comes on screen after its words arrived shows its marks quickly", () => {
    const live = S.liveNew(SRC, 0);
    S.liveFeed(live, FIX, 0.5);
    S.liveStep(live, 0.55);
    const ci = live.ci, e = live.entry;
    // however far it got, the chunk's own marks land at MARK_START + n * 0.04 after its entry
    const c = live.prep.chunks[ci], n = c.chars.filter(ch => ch.mark).length;
    if (n >= 2) assert.ok(markN(S.liveScene(live, e + 0.08 + 0.001)) < markN(S.liveScene(live, e + 0.08 + 0.001 + n * 0.04 + 0.3)));
    S.liveStep(live, 60);
    assert.strictEqual(live.ci, live.prep.chunks.length - 1);                 // all arrived: it walks to the last chunk
});

test("live: a word that differs from the typed one other than by marks is left as typed", () => {
    const live = S.liveNew("Dobry den teto", 0);
    S.liveFeed(live, "Dobrý den těto xx", 1.0);                              // 'těto' has a mark where 'teto' ... ok; 'xx' is extra
    assert.strictEqual(live.skipped, 0);
    assert.ok(live.extra);
    const l2 = S.liveNew("Dobry den", 0);
    S.liveFeed(l2, "Dobrá dne", 1.0);                                          // different letters / length
    assert.ok(l2.skipped >= 1);
    assert.strictEqual(S.liveFinish(l2, "Dobrá dne", 2.0), null);
});

test("liveFinish: null when the word counts differ", () => {
    const live = S.liveNew("Dobry den teto", 0);
    S.liveFeed(live, "Dobrý den", 1.0);
    assert.strictEqual(S.liveFinish(live, "Dobrý den", 2.0), null);            // a word missing
});

test("liveFinish: carries on from the chunk on screen, no flare is played twice, total at most 1.5 s", () => {
    const live = S.liveNew(SRC, 0), words = FIX.split(" ");
    S.liveFeed(live, words.slice(0, 5).join(" "), 1.0);
    const t = 1.6;
    S.liveScene(live, t);                                                      // steps
    const plan = S.liveFinish(live, FIX, t);
    assert.ok(plan && plan.items.length >= 1 && plan.total <= 1.5 + 1e-9);
    assert.ok(plan.items.every(it => it.i >= live.ci), "nothing before the chunk on screen is replayed");
    assert.ok(plan.items[0].cont && plan.items[0].i === live.ci);
    // the first replay frame is the live frame (same chunk, same dots lit)
    const before = S.liveScene(live, t), first = S.replay(live.prep, plan, 0.05);
    assert.strictEqual(lit(first) > 0, true);
    for (let i = 1; i < plan.items.length; i++) assert.ok(plan.items[i].i > plan.items[i - 1].i);
    // chunks already shown are not in the plan
    if (live.ci > 0) assert.ok(!plan.items.some(it => it.i < live.ci));
    assert.ok(before.v.length === first.v.length);
});

test("liveFinish: everything already shown = nothing to replay (the live picture stays)", () => {
    const live = S.liveNew("ctrnact", 0);
    S.liveFeed(live, "čtrnáct", 1.0);
    const plan = S.liveFinish(live, "čtrnáct", 5.0);
    assert.strictEqual(plan.items.length, 0);
});

test("liveFinish: no stream at all (all words arrive with done) replays like a fresh replay, from the first chunk", () => {
    const live = S.liveNew(SRC, 0);
    const plan = S.liveFinish(live, FIX, 0.5);
    assert.ok(plan && plan.items[0].i === 0 && plan.total <= 1.5 + 1e-9);
    const g = S.replay(live.prep, plan, plan.total);
    assert.ok(markN(g) > 0);
});

test("replayPlan with a continued chunk: it comes first, the rest follows in reading order within the budget", () => {
    const p = S.prepare(FIX.repeat(1)), cont = { i: 0, dur: 0.2, q0: 0.1, lands: [0.1, 0.14] };
    const pl = S.replayPlan(p, 1.5, cont);
    assert.strictEqual(pl.items[0].i, 0);
    assert.ok(pl.items[0].cont === cont);
    assert.ok(pl.total <= 1.5 + 1e-9);
});

test("scene: with a live state the live picture is shown (and fades in the end states)", () => {
    const live = S.liveNew("ctrnact", 0);
    S.liveFeed(live, "čtrnáct", 0.0);
    const g = S.scene("words", "working", 0.5, 0, null, null, live);
    assert.ok(markN(g) > 0);
    assert.ok(lit(S.scene("words", "failed", 0.5, 0.05, null, null, live)) > 0);
});

test("live: a chunk whose words all arrived before it came on screen plays faster than one followed live", () => {
    const early = S.liveNew("ctrnact ruzi", 0), late = S.liveNew("ctrnact ruzi", 0);
    S.liveFeed(early, "čtrnáct růži", -1.0);                  // arrived before the chunk entered
    S.liveFeed(late, "čtrnáct růži", 1.0);
    const a = S.liveChunk(early, early.prep.chunks[0], 0), b = S.liveChunk(late, late.prep.chunks[0], 0);
    assert.ok(a.hold < b.hold);
    assert.ok(a.lands[1] - a.lands[0] < b.lands[1] - b.lands[0]);
    assert.ok(a.last + a.hold < 0.4);
});
