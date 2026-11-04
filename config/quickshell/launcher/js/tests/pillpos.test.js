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
    eq(r, { atTop: true, onBar: true, inset: 56, left: 332, cardW: 336 });
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
