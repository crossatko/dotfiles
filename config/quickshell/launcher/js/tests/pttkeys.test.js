const test = require("node:test");
const assert = require("node:assert");
const { load } = require("./load");
const K = load("PttKeys.js");
const plain = v => JSON.parse(JSON.stringify(v));   // vm-context objects -> this realm

test("parse: canonical modifier order and key case", () => {
    assert.strictEqual(K.parse("super+f9").keys, "SUPER + F9");
    assert.strictEqual(K.parse("SHIFT SUPER, F9").keys, "SUPER + SHIFT + F9");
    assert.strictEqual(K.parse(" control + alt + space ").keys, "CTRL + ALT + space");
    assert.strictEqual(K.parse("WIN + a").keys, "SUPER + A");
    assert.strictEqual(K.parse("Pause").keys, "Pause");
    assert.strictEqual(K.parse("code:191").keys, "code:191");
    assert.strictEqual(K.parse("").keys, "");
    assert.strictEqual(K.parse("   ").error, "");
});

test("parse: errors", () => {
    assert.match(K.parse("SUPER").error, /Add a key/);
    assert.match(K.parse("HYPER + F9").error, /Not a modifier/);
    assert.match(K.parse("SUPER + F9|x").error, /Not a key/);
    assert.match(K.parse("SUPER + F9 + F10").error, /Not a modifier/);
});

test("same / split compare like Hyprland (mask + case-insensitive key)", () => {
    assert.deepStrictEqual(plain(K.split("SUPER + SHIFT + F9")), { mask: 65, key: "f9" });
    assert.ok(K.same("SUPER + A", "SUPER + A"));
    assert.ok(!K.same("SUPER + A", "SUPER + SHIFT + A"));
    assert.ok(!K.same("", ""));
});

test("conflicts: hyprctl binds -j entries", () => {
    const binds = [
        { modmask: 64, key: "D", dispatcher: "HL.Dispatcher(exec_cmd)", description: "Launcher" },
        { modmask: 0, key: "F7", dispatcher: "HL.Dispatcher(global)", description: "" },
        { modmask: 0, key: "F9", dispatcher: "HL.Dispatcher(global)", description: "Push-to-talk: Czech" },
        { modmask: 64, key: "h", dispatcher: "function: 0x1", description: "Focus left", submap: "resize" },
        { modmask: 64, key: "mouse:272", mouse: true, dispatcher: "HL.Dispatcher(drag)" },
        { modmask: 0, key: "", keycode: 191, dispatcher: "HL.Dispatcher(exec_cmd)" },
    ];
    const own = b => /^Push-to-talk/.test(b.description || "");
    assert.deepStrictEqual(plain(K.conflicts("SUPER + d", binds, own)).map(c => c.text), ["Launcher"]);
    assert.deepStrictEqual(plain(K.conflicts("F7", binds, own)).map(c => [c.text, c.global]), [["Global shortcut: another app", true]]);
    assert.deepStrictEqual(plain(K.conflicts("F9", binds, own)), []);
    assert.deepStrictEqual(plain(K.conflicts("SUPER + H", binds, own)).map(c => c.text), ["Focus left (submap resize)"]);
    assert.deepStrictEqual(plain(K.conflicts("code:191", binds, own)).map(c => c.text), ["exec_cmd"]);
    assert.deepStrictEqual(plain(K.conflicts("", binds, own)), []);
    assert.deepStrictEqual(plain(K.conflicts("SUPER + mouse:272", binds, own)).map(c => c.text), ["drag"]);
    assert.deepStrictEqual(plain(K.conflicts("mouse:277", binds.concat([{ modmask: 0, key: "mouse:277", dispatcher: "HL.Dispatcher(exec_cmd)", description: "Back" }]), own)).map(c => c.text), ["Back"]);
});

test("fromQt: key events -> Hyprland strings", () => {
    const META = 0x10000000, CTRL = 0x04000000, SHIFT = 0x02000000;
    assert.strictEqual(K.fromQt(0x01000038, META, 75), "SUPER + F9");          // Qt.Key_F9
    assert.strictEqual(K.fromQt(0x41, CTRL | SHIFT, 38), "CTRL + SHIFT + A");
    assert.strictEqual(K.fromQt(0x21, META | SHIFT, 10), "SUPER + SHIFT + 1");  // "!" with shift
    assert.strictEqual(K.fromQt(0x01000008, 0, 127), "Pause");
    assert.strictEqual(K.fromQt(0x20, CTRL, 65), "CTRL + space");
    assert.strictEqual(K.fromQt(0x01000021, CTRL, 37), "");                   // only a modifier
    assert.strictEqual(K.fromQt(0x0100ffff, 0, 191), "code:191");             // unknown key -> scan code
});

test("captures: combos and non-text keys, not typing", () => {
    const META = 0x10000000, SHIFT = 0x02000000;
    assert.ok(K.captures(0x01000038, 0, ""));          // F9
    assert.ok(K.captures(0x41, META, "a"));            // SUPER + A
    assert.ok(!K.captures(0x41, 0, "a"));              // typing
    assert.ok(!K.captures(0x2b, SHIFT, "+"));          // typing "+"
    assert.ok(!K.captures(0x01000003, 0, "\b"));       // Backspace edits
    assert.ok(!K.captures(0x01000012, 0, ""));         // Left edits
    assert.ok(!K.captures(0x56, 0x04000000, "\x16"));  // CTRL + V pastes
    assert.ok(K.captures(0x56, 0x04000000 | SHIFT, "")); // CTRL + SHIFT + V is a combo
});

test("mouse buttons", () => {
    const META = 0x10000000;
    assert.strictEqual(K.parse("mouse:277").keys, "mouse:277");
    assert.strictEqual(K.parse("super + MOUSE:275").keys, "SUPER + mouse:275");
    assert.strictEqual(K.parse("super + mouse:275").keys, "SUPER + mouse:275");
    assert.match(K.parse("mouse:272").error, /needs a modifier/);
    assert.strictEqual(K.parse("CTRL + mouse:272").keys, "CTRL + mouse:272");
    assert.match(K.parse("mouse:999").error, /Not a mouse button/);
    assert.match(K.parse("mouse:271").error, /Not a mouse button/);
    assert.match(K.parse("mouse_down").error, /wheel/);
    assert.ok(K.isMouse("SUPER + mouse:276") && !K.isMouse("F9"));
    assert.strictEqual(K.label("SUPER + mouse:275"), "SUPER + Side button (mouse:275)");
    assert.strictEqual(K.label("F9"), "F9");
    assert.strictEqual(K.fromMouse(0x8, 0), "mouse:275");          // Qt.BackButton
    assert.strictEqual(K.fromMouse(0x10, META), "SUPER + mouse:276"); // Qt.ForwardButton
    assert.strictEqual(K.fromMouse(0x20, 0), "mouse:277");         // Qt.ExtraButton3
    assert.strictEqual(K.fromMouse(0, 0), "");
});
