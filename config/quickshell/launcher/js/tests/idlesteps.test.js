const test = require("node:test");
const assert = require("node:assert");
const { load } = require("./load");
const I = load("IdleSteps.js");

test("steps: Immediately first, Never last, labels match", () => {
    assert.strictEqual(I.VALUES.length, I.LABELS.length);
    assert.strictEqual(I.VALUES[0], 1);
    assert.strictEqual(I.LABELS[0], "Immediately");
    assert.strictEqual(I.VALUES[I.VALUES.length - 1], 0);
});

test("nearest: listed values map to themselves (old 600 = 10 min)", () => {
    for (const v of I.VALUES) assert.strictEqual(I.nearest(v), v);
    assert.strictEqual(I.LABELS[I.VALUES.indexOf(I.nearest(600))], "10 min");
});

test("nearest: never, immediately, off-list values snap by ratio", () => {
    assert.strictEqual(I.nearest(-1), 0);
    assert.strictEqual(I.nearest("x"), 0);
    assert.strictEqual(I.nearest(0.5), 1);
    assert.strictEqual(I.nearest(5), 15);      // 3x from 15, 5x from 1
    assert.strictEqual(I.nearest(400), 300);
    assert.strictEqual(I.nearest(500), 600);
    assert.strictEqual(I.nearest(86400), 3600);
});
