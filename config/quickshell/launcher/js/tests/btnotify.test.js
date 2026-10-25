const test = require("node:test");
const assert = require("node:assert");
const { load } = require("./load");
const B = load("BtNotify.js");

const pods = { connected: true, name: "Test Buds", headset: false,
    left: { level: 79 }, right: { level: 100 }, box: { level: -1 }, max: { level: -1 } };

test("icon mapping by BlueZ icon, with a fallback", () => {
    assert.strictEqual(B.iconName({ icon: "audio-headset" }), "audio-headset");
    assert.strictEqual(B.iconName({ icon: "input-keyboard" }), "input-keyboard");
    assert.strictEqual(B.iconName({ icon: "audio-card" }), "audio-speakers");
    assert.strictEqual(B.iconName({ icon: "video-display" }), "tv");
    assert.strictEqual(B.iconName({ icon: "something-new" }), "bluetooth");
    assert.strictEqual(B.iconName({}), "bluetooth");
    assert.strictEqual(B.iconName(null), "bluetooth");
});

test("AirPods by name, or by the daemon naming the same device", () => {
    assert.ok(B.isAirPods({ name: "Test AirPods Pro" }, null));
    assert.ok(B.isAirPods({ name: "Test Buds" }, pods));
    assert.ok(!B.isAirPods({ name: "Test Buds" }, null));
    assert.ok(!B.isAirPods({ name: "Test Buds" }, { connected: false, name: "Test Buds" }));
    assert.ok(!B.isAirPods({ name: "Kbd" }, pods));
    assert.ok(!B.isAirPods(null, pods));
});

test("icon: AirPods drawing vs symbolic name", () => {
    assert.strictEqual(B.icon({ name: "My AirPods", icon: "audio-headset" }, null, "/a"), "/a/airpods-pro-buds.svg");
    assert.strictEqual(B.icon({ name: "Cans", icon: "audio-headphones" }, null, "/a"), "audio-headphones");
});

test("title and body", () => {
    assert.strictEqual(B.title({ name: "Cans" }, true), "Cans connected");
    assert.strictEqual(B.title({ name: "Cans" }, false), "Cans disconnected");
    assert.strictEqual(B.title({}, true), "Bluetooth device connected");
    assert.strictEqual(B.body({ name: "Test Buds" }, pods, true), "L 79% · R 100%");
    assert.strictEqual(B.body({ name: "Test Buds" }, pods, false), "");
    assert.strictEqual(B.body({ name: "Mouse", batteryAvailable: true, battery: 0.8 }, null, true), "Battery 80%");
    assert.strictEqual(B.body({ name: "Mouse", batteryAvailable: false, battery: 0 }, null, true), "");
});

test("pods body: headset, nothing known", () => {
    assert.strictEqual(B.podsBody({ headset: true, max: { level: 64 } }), "64%");
    assert.strictEqual(B.podsBody({ left: { level: -1 }, right: { level: -1 }, box: { level: -1 } }), "");
    assert.ok(!B.podsReady(null));
    assert.ok(B.podsReady(pods));
});

test("argv is a plain array; body only when known", () => {
    const a = B.argv({ name: "Mouse", icon: "input-mouse" }, null, true, "/a");
    assert.strictEqual(JSON.stringify(a), JSON.stringify(["notify-send", "-a", "Bluetooth", "-u", "low", "-t", "5000", "-i", "input-mouse", "--", "Mouse connected"]));
    const b = B.argv({ name: "Test Buds" }, pods, true, "/a");
    assert.strictEqual(b[b.length - 1], "L 79% · R 100%");
});
