const test = require("node:test");
const assert = require("node:assert");
const { load } = require("./load");
const F = load("Frecency.js");
const DAY = 86400000, NOW = 1.8e12;

test("frecency: recent beats old, more beats fewer", () => {
    const recent = { count: 3, times: [NOW - DAY] };
    const old = { count: 3, times: [NOW - 200 * DAY] };
    const many = { count: 30, times: [NOW - DAY] };
    assert.ok(F.frecency(recent, NOW) > F.frecency(old, NOW));
    assert.ok(F.frecency(many, NOW) > F.frecency(recent, NOW));
    assert.strictEqual(F.frecency(undefined, NOW), 0);
});

test("record: counts, caps times and terms, lowercases query", () => {
    let u = {};
    for (let i = 0; i < 15; i++) u = F.record(u, "a", "FF", NOW + i);
    assert.strictEqual(u.a.count, 15);
    assert.strictEqual(u.a.times.length, 10);
    assert.strictEqual(u.a.times[9], NOW + 14);
    assert.strictEqual(u.a.terms.ff, 15);
    for (let i = 0; i < 25; i++) u = F.record(u, "a", "t" + i, NOW);
    assert.ok(Object.keys(u.a.terms).length <= 20);
    assert.strictEqual(u.a.terms.ff, 15, "most used term survives");
    u = F.record(u, "b", "", NOW);
    assert.strictEqual(JSON.stringify(u.b.terms), JSON.stringify({}));
});

test("immutability", () => {
    const u0 = F.record({}, "a", "x", NOW);
    const snap = JSON.stringify(u0);
    F.record(u0, "a", "y", NOW + 1);
    F.setPinned(u0, "a", true);
    F.setHidden(u0, "a", true);
    F.prune(u0, NOW + 400 * DAY);
    assert.strictEqual(JSON.stringify(u0), snap);
});

test("pin / hide toggle and survive record", () => {
    let u = F.setPinned({}, "a", true);
    assert.strictEqual(u.a.pinned, true);
    u = F.record(u, "a", "", NOW);
    assert.strictEqual(u.a.pinned, true);
    u = F.setPinned(u, "a", false);
    assert.strictEqual(u.a.pinned, undefined);
    u = F.setHidden(u, "a", true);
    assert.strictEqual(u.a.hidden, true);
});

test("prune drops stale unless pinned/hidden", () => {
    let u = F.record({}, "old", "", NOW - 200 * DAY);
    u = F.record(u, "fresh", "", NOW - DAY);
    u = F.record(u, "pin", "", NOW - 300 * DAY);
    u = F.setPinned(u, "pin", true);
    const p = F.prune(u, NOW);
    assert.strictEqual(JSON.stringify(Object.keys(p).sort()), JSON.stringify(["fresh", "pin"]));
});
