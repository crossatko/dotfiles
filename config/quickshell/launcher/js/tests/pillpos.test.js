const test = require("node:test");
const assert = require("node:assert");
const { load } = require("./load");
const P = load("PillPos.js");
const eq = (a, b) => assert.deepStrictEqual(JSON.parse(JSON.stringify(a)), JSON.parse(JSON.stringify(b)));

test("parse: missing / malformed = defaults", () => {
    eq(P.parse(null), P.DEFAULTS);
    eq(P.parse([]), P.DEFAULTS);
    eq(P.parse({ pill_edge: "left", pill_gap: "3", pill_x: null, pill_screen: 5 }), P.DEFAULTS);
});

test("parse: valid values kept, numbers clamped", () => {
    eq(P.parse({ pill_edge: "top", pill_gap: 3.25, pill_x: 0.25, pill_screen: "Some monitor" }),
       { pill_edge: "top", pill_gap: 3.3, pill_x: 0.25, pill_screen: "Some monitor" });
    eq(P.parse({ pill_gap: 99, pill_x: -1 }), { pill_edge: "bar", pill_gap: 8, pill_x: 0, pill_screen: "" });
    assert.strictEqual(P.parse({ pill_screen: "a\nb" }).pill_screen, "");
});

test("parse: legacy edge applies only when pill_edge is missing or bad", () => {
    assert.strictEqual(P.parse({}, "bottom").pill_edge, "bottom");
    assert.strictEqual(P.parse({ pill_edge: "nope" }, "bottom").pill_edge, "bottom");
    assert.strictEqual(P.parse({ pill_edge: "bar" }, "bottom").pill_edge, "bar");
    assert.strictEqual(P.parse({}, "sideways").pill_edge, "bar");
});

const base = { edge: "bar", barEdge: "top", gap: 2, x: 0.5, screenW: 1000, pillW: 336, side: 12, barInset: 40, gapBar: 8, gapEdge: 12 };

test("place: the old look by default (centred, past the top bar)", () => {
    const r = P.place(base);
    eq(r, { atTop: true, onBar: true, inset: 56, left: 332, margin: 332, cardW: 336 });
});

test("place: the edge away from the bar uses the edge gap", () => {
    const r = P.place(Object.assign({}, base, { edge: "bottom" }));
    assert.strictEqual(r.atTop, false);
    assert.strictEqual(r.onBar, false);
    assert.strictEqual(r.inset, 24);
    const t = P.place(Object.assign({}, base, { edge: "top", barEdge: "bottom" }));
    assert.strictEqual(t.atTop, true);
    assert.strictEqual(t.inset, 24);
});

test("place: no bar = the bottom edge, bar gap from the bare edge", () => {
    const r = P.place(Object.assign({}, base, { barEdge: "", barInset: 0 }));
    assert.strictEqual(r.atTop, false);
    assert.strictEqual(r.onBar, false);
    assert.strictEqual(r.inset, 16);
});

test("place: horizontal position between the side gaps; narrow screen shrinks the card", () => {
    assert.strictEqual(P.place(Object.assign({}, base, { x: 0 })).left, 12);
    assert.strictEqual(P.place(Object.assign({}, base, { x: 1 })).left, 1000 - 12 - 336);
    const n = P.place(Object.assign({}, base, { screenW: 300, x: 1 }));
    assert.strictEqual(n.cardW, 276);
    assert.strictEqual(n.left, 12);
    assert.strictEqual(P.place(Object.assign({}, base, { gap: 0 })).inset, 40);
});

test("place: a reserved side strip (pinned video): centred and spanning the usable width", () => {
    const pip = Object.assign({}, base, { screenW: 2560, resR: 866 });
    const usable = 2560 - 866;
    const c = P.place(pip);
    assert.strictEqual(c.left, Math.round(12 + (usable - 24 - 336) / 2), "x 0.5 = the centre of the usable area");
    assert.strictEqual(c.margin, c.left, "a full-screen window: margin from the screen edge");
    const right = P.place(Object.assign({}, pip, { x: 1 }));
    assert.strictEqual(right.left + right.cardW, usable - 12, "x 1 stops at the strip, never over it");
    const inside = P.place(Object.assign({}, pip, { resL: 100, resR: 0, x: 0, inUsable: true }));
    assert.strictEqual(inside.left, 112);
    assert.strictEqual(inside.margin, 12, "zone 0: the compositor measures from the usable area's left");
});

test("withKey: a copy with one valid value, else null", () => {
    const p = P.parse({});
    eq(P.withKey(p, "pill_x", 2), Object.assign({}, p, { pill_x: 1 }));
    eq(p, P.DEFAULTS, "not mutated");
    assert.strictEqual(P.withKey(p, "pill_edge", "left"), null);
    assert.strictEqual(P.withKey(p, "mic", ""), null);
});
