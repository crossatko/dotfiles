const test = require("node:test");
const assert = require("node:assert");
const { load } = require("./load");
const D = load("MonitorShown.js");
const eq = (a, b) => assert.deepStrictEqual(JSON.parse(JSON.stringify(a)), JSON.parse(JSON.stringify(b)));
const keys = ["A", "B", "C"];
const on = (s) => D.shownKeys(s, keys);

test("shown: enabled and not hidden", () => {
    assert.ok(D.shown(true, {}, "A"));
    assert.ok(!D.shown(true, { A: true }, "A"));
    assert.ok(!D.shown(false, {}, "A"));
    assert.ok(!D.shown(true, {}, ""));
    assert.ok(D.shown(true, undefined, "A"));
});

test("off everywhere -> on for B only", () => {
    const s = D.toggle({ enabled: false, hidden: {} }, keys, "B", true);
    eq(on(s), ["B"]);
    eq(s, { enabled: true, hidden: { A: true, C: true } });
});

test("off everywhere with an old map -> on for A only", () => {
    const s = D.toggle({ enabled: false, hidden: { B: true, X: true } }, keys, "A", true);
    eq(on(s), ["A"]);
    assert.strictEqual(s.hidden.X, true);           // a monitor not connected keeps its choice
});

test("all on -> A off keeps the others", () => {
    const s = D.toggle({ enabled: true, hidden: {} }, keys, "A", false);
    eq(on(s), ["B", "C"]);
    assert.strictEqual(s.enabled, true);
});

test("the last one off = off everywhere, map remembers it", () => {
    const s = D.toggle({ enabled: true, hidden: { A: true, C: true } }, keys, "B", false);
    eq(on(s), []);
    eq(s, { enabled: false, hidden: { A: true, C: true } });
    eq(on({ enabled: true, hidden: s.hidden }), ["B"]);   // `enabled` true again (ipc / old Settings) = where it was
});

test("on while some on adds just that one", () => {
    const s = D.toggle({ enabled: true, hidden: { A: true, C: true } }, keys, "C", true);
    eq(on(s), ["B", "C"]);
});

test("enabled but every connected monitor hidden (after a hot-plug) -> on for one", () => {
    const s = D.toggle({ enabled: true, hidden: { A: true, B: true, C: true } }, keys, "A", true);
    eq(on(s), ["A"]);
});

test("off on a monitor that is already off changes nothing", () => {
    eq(D.toggle({ enabled: false, hidden: {} }, keys, "A", false), { enabled: false, hidden: {} });
    eq(D.toggle({ enabled: true, hidden: { A: true } }, keys, "A", false), { enabled: true, hidden: { A: true } });
});

test("empty key is ignored", () => {
    eq(D.toggle({ enabled: false, hidden: {} }, keys, "", true), { enabled: false, hidden: {} });
});

test("all on / off", () => {
    const a = D.setAll({ enabled: false, hidden: { A: true, X: true } }, keys, true);
    eq(a, { enabled: true, hidden: { X: true } });
    eq(on(a), keys);
    const b = D.setAll(a, keys, false);
    eq(on(b), []);
    eq(b.hidden, { X: true });
});

test("single monitor", () => {
    const s = D.toggle({ enabled: false, hidden: {} }, ["A"], "A", true);
    eq(s, { enabled: true, hidden: {} });
    eq(D.toggle(s, ["A"], "A", false), { enabled: false, hidden: {} });
});

test("inputs are not mutated", () => {
    const h = { A: true };
    D.toggle({ enabled: true, hidden: h }, keys, "B", false);
    D.setAll({ enabled: true, hidden: h }, keys, true);
    eq(h, { A: true });
});
