const test = require("node:test");
const assert = require("node:assert");
const { load } = require("./load");
const A = load("AirPods.js");

const full = JSON.stringify({
    schema_version: 1, connected: true, device_name: "Test’s AirPods Pro", model_name: "AirPods Pro 3", is_pro_series: true,
    noise_mode: 3, adaptive_noise_level: 40, conversational_awareness: true, ear_detection_behavior: 1,
    supports_noise_control: true, supports_noise_off: false, supports_adaptive: true, supports_conversational_awareness: true,
    left: { available: true, level: 79, charging: false, in_ear: true },
    right: { available: true, level: 100, charging: true, in_ear: false },
    case: { available: true, level: 55, charging: false },
});

test("parses a full status", () => {
    const s = A.parse(full);
    assert.ok(s.valid && s.connected);
    assert.strictEqual(s.left.level, 79);
    assert.strictEqual(s.right.charging, true);
    assert.strictEqual(s.box.level, 55);
    assert.strictEqual(s.mode, 3);
    assert.strictEqual(JSON.stringify(A.modes(s).map((m) => m.value)), JSON.stringify([2, 3, 1]));   // no Off on this model
});
test("unavailable part is unknown and its stale fields are dropped", () => {
    const d = JSON.parse(full);
    d.right = { available: false, level: 100, charging: true, in_ear: true };
    const s = A.parse(JSON.stringify(d));
    assert.strictEqual(s.right.level, -1);
    assert.strictEqual(s.right.charging, false);
});
test("older daemon: capabilities fall back to is_pro_series", () => {
    const s = A.parse('{"schema_version":1,"connected":true,"is_pro_series":false}');
    assert.strictEqual(JSON.stringify(A.modes(s).map((m) => m.value)), JSON.stringify([0, 2, 1]));
    assert.strictEqual(s.canAware, false);
});
test("no listening modes", () => {
    const s = A.parse('{"schema_version":1,"connected":true,"supports_noise_control":false}');
    assert.strictEqual(JSON.stringify(A.modes(s)), JSON.stringify([]));
});
test("headset uses its own battery", () => {
    const s = A.parse('{"schema_version":1,"connected":true,"is_headset":true,"headset":{"available":true,"level":64,"charging":false}}');
    assert.strictEqual(s.max.level, 64);
});
test("broken, empty and too-new input", () => {
    assert.strictEqual(A.parse("").valid, false);
    assert.strictEqual(A.parse("{nope").valid, false);
    assert.strictEqual(A.parse('{"connected":true}').valid, false);
    const n = A.parse('{"schema_version":2,"connected":true}');
    assert.ok(n.tooNew && !n.valid && !n.connected);
});
test("output matching", () => {
    assert.ok(A.looksLikeAirPods("Some AirPods", "bluez_output.1"));
});
test("section title", () => {
    assert.strictEqual(A.title("AirPods Pro 2 (USB-C)"), "AirPods Pro 2");
    assert.strictEqual(A.title("AirPods Max"), "AirPods Max");
    assert.strictEqual(A.title(""), "AirPods");
    assert.strictEqual(A.title(undefined), "AirPods");
});
test("case age", () => {
    assert.strictEqual(A.age(0, 1000), "");
    assert.strictEqual(A.age(-1, 1000), "");
    assert.strictEqual(A.age(1000, 1030), "");
    assert.strictEqual(A.age(1000, 1000 + 600), "10m");
    assert.strictEqual(A.age(1000, 1000 + 7300), "2h");
    assert.strictEqual(A.age(1000, 1000 + 2 * 86400), "2d");
    assert.strictEqual(A.parse(full).caseSeenAt, -1);
    const d = JSON.parse(full); d.case_seen_at = 1234;
    assert.strictEqual(A.parse(JSON.stringify(d)).caseSeenAt, 1234);
});
test("modes carry a glyph and a name", () => {
    const m = A.modes(A.parse(full));
    assert.ok(m.every((x) => x.glyph && x.name));
});
