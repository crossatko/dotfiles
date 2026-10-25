const test = require("node:test");
const assert = require("node:assert");
const { load } = require("./load");
const G = load("NotifGlyph.js");
const cp = n => { const g = G.glyph(n); return g === "" ? "" : g.charCodeAt(0).toString(16); };

test("standard names map to glyphs", () => {
    assert.strictEqual(cp("dialog-warning"), "f071");
    assert.strictEqual(cp("dialog-error-symbolic"), "f057");
    assert.strictEqual(cp("dialog-information"), "f05a");
    assert.strictEqual(cp("folder-download"), "e053");
    assert.strictEqual(cp("x-office-calendar"), "f133");
    assert.strictEqual(cp("mail-unread"), "f0e0");
    assert.strictEqual(cp("audio-headset"), "f590");
    assert.strictEqual(cp("input-keyboard"), "f11c");
    assert.strictEqual(cp("bluetooth-active"), "f293");
});

test("families", () => {
    assert.strictEqual(cp("network-wireless-signal-good"), "f1eb");
    assert.strictEqual(cp("network-wireless-offline"), "f6ac");
    assert.strictEqual(cp("network-transmit-receive"), "f6ff");
    assert.strictEqual(cp("audio-volume-muted-blocking"), "f028");
    assert.strictEqual(cp("audio-volume-muted"), "f6a9");
    assert.strictEqual(cp("camera-whatever"), "f030");
});

test("battery levels", () => {
    assert.strictEqual(cp("battery-level-100"), "f240");
    assert.strictEqual(cp("battery-level-70-symbolic"), "f241");
    assert.strictEqual(cp("battery-level-50"), "f242");
    assert.strictEqual(cp("battery-level-20"), "f243");
    assert.strictEqual(cp("battery-level-0"), "f244");
    assert.strictEqual(cp("battery-level-80-charging"), "f376");
    assert.strictEqual(cp("battery-caution"), "f244");
});

test("app-specific and unknown names have no glyph", () => {
    for (const n of ["steam", "discord", "org.gnome.Nautilus", "weird-icon", "", null, undefined, "batteryfoo-app".replace("batteryf", "x")])
        assert.strictEqual(G.glyph(n), "");
});
