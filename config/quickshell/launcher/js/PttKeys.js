.pragma library

// Push-to-talk key strings (Settings > Voice, PttPrefs.qml / KeyCaptureField.qml). Pure functions, no processes.
// A key is kept in Hyprland's Lua bind syntax: modifiers in a fixed order, then one key or mouse button, joined by " + "
// ("SUPER + SHIFT + F9", "F9", "CTRL + ALT + space", "code:191", "mouse:276", "SUPER + mouse:275"). "" = no key.
// Mouse buttons are evdev codes (272 left, 273 right, 274 middle, 275 side, 276 extra, 277 forward, 278 back, ...).

// modifier name -> Hyprland modmask bit (hyprctl binds -j); the canonical order
var MODS = [["SUPER", 64], ["CTRL", 4], ["ALT", 8], ["SHIFT", 1]];
var ALIAS = { SUPER: "SUPER", WIN: "SUPER", META: "SUPER", LOGO: "SUPER", MOD4: "SUPER", CMD: "SUPER",
              CTRL: "CTRL", CONTROL: "CTRL", CTL: "CTRL", ALT: "ALT", MOD1: "ALT", OPTION: "ALT", SHIFT: "SHIFT" };
var KEY = /^([A-Za-z0-9_]{1,40}|code:\d{1,4}|mouse:\d{3})$/;
var WHEEL = /^mouse_(up|down|left|right)$/i;

function modOf(tok) { return ALIAS[String(tok).toUpperCase()] || ""; }
function keyName(k) {
    if (/^[a-z]$/.test(k)) return k.toUpperCase();
    if (/^f\d{1,2}$/.test(k)) return k.toUpperCase();
    return k;
}

// typed text -> { keys, error }. Accepts "SUPER + F9", "super+f9", "SUPER SHIFT, F9" (hyprland.conf style),
// aliases (WIN / META / CONTROL / MOD4 ...). Empty text = { keys: "" } (no key).
function parse(text) {
    var s = String(text || "").trim();
    if (s === "") return { keys: "", error: "" };
    var toks = s.split(/\s*[+,]\s*|\s+/).filter(function (t) { return t !== ""; });
    if (toks.length === 0) return { keys: "", error: "" };
    var have = {}, i;
    for (i = 0; i < toks.length - 1; i++) {
        var m = modOf(toks[i]);
        if (m === "") return { keys: "", error: "Not a modifier: " + toks[i] };
        have[m] = true;
    }
    var last = toks[toks.length - 1].replace(/^(mouse|code):/i, function (m) { return m.toLowerCase(); });
    if (modOf(last) !== "") return { keys: "", error: "Add a key after " + modOf(last) };
    if (WHEEL.test(last)) return { keys: "", error: "The wheel has no release" };
    if (!KEY.test(last)) return { keys: "", error: "Not a key name: " + last };
    if (/^mouse:/.test(last) && !/^mouse:(27[2-9]|2[89]\d|3[01]\d)$/.test(last)) return { keys: "", error: "Not a mouse button: " + last };
    if ((last === "mouse:272" || last === "mouse:273") && toks.length === 1) return { keys: "", error: "Left / right click needs a modifier" };
    var out = [];
    for (i = 0; i < MODS.length; i++) if (have[MODS[i][0]]) out.push(MODS[i][0]);
    out.push(keyName(last));
    return { keys: out.join(" + "), error: "" };
}

// canonical key string -> { mask, key } (key lower-cased, for comparing with hyprctl binds -j)
function split(keys) {
    var toks = String(keys || "").split(" + "), mask = 0, i, j;
    for (i = 0; i < toks.length - 1; i++)
        for (j = 0; j < MODS.length; j++) if (MODS[j][0] === toks[i]) mask |= MODS[j][1];
    return { mask: mask, key: String(toks[toks.length - 1] || "").toLowerCase() };
}
function same(a, b) {
    if (!a || !b) return false;
    var x = split(a), y = split(b);
    return x.mask === y.mask && x.key === y.key;
}

// one `hyprctl binds -j` entry's key as we write it ("code:N" for a keycode bind)
function bindKey(b) { return b.key ? String(b.key).toLowerCase() : b.keycode > 0 ? "code:" + b.keycode : ""; }

// what else uses `keys`: `binds` = hyprctl binds -j, `own(b)` true for our own push-to-talk binds (skipped: the
// other two keys are checked by the caller against the saved ones). -> [{ text, global }] (global: another app's
// global shortcut, the dispatcher is `global`)
function conflicts(keys, binds, own) {
    if (!keys) return [];
    var k = split(keys), out = [];
    (binds || []).forEach(function (b) {
        if (!b || b.catch_all || (own && own(b))) return;
        if ((b.modmask || 0) !== k.mask || bindKey(b) !== k.key) return;
        var d = String(b.dispatcher || "");
        var global = /\(global\)$/.test(d) || d === "global";
        var name = b.description || (global ? "another app" : (/^HL\.Dispatcher\((.*)\)$/.exec(d) || [0, "a Hyprland bind"])[1]);
        out.push({ text: (global ? "Global shortcut: " : "") + name + (b.submap ? " (submap " + b.submap + ")" : ""), global: global });
    });
    return out;
}

function isMouse(keys) { return /(^| )mouse:\d+$/.test(String(keys || "")); }
var BUTTONS = { 272: "Left button", 273: "Right button", 274: "Middle button", 275: "Side button", 276: "Extra button",
                277: "Forward button", 278: "Back button", 279: "Task button" };
function buttonName(code) { return BUTTONS[code] || "Mouse button " + code; }
// a key string for people: the mouse button named ("SUPER + Side button (mouse:275)")
function label(keys) {
    var m = /^(.*?)mouse:(\d+)$/.exec(String(keys || ""));
    return m ? m[1] + buttonName(Number(m[2])) + " (mouse:" + m[2] + ")" : String(keys || "");
}
// a pressed Qt mouse button (one Qt.MouseButton bit) + modifiers -> "SUPER + mouse:276". Qt numbers the buttons as the
// evdev codes from BTN_LEFT (272) on: bit 0 left, 1 right, 2 middle, 3 back (BTN_SIDE 275), 4 forward (BTN_EXTRA 276),
// 5.. ExtraButton3.. (277..)
function fromMouse(button, modifiers) {
    var i = 0;
    if (!(button > 0)) return "";
    while (i < 31 && !(button & (1 << i))) i++;
    return modsOf(modifiers).concat(["mouse:" + (272 + i)]).join(" + ");
}

// ---- capture: a key press in the field (QML KeyEvent fields) -> Hyprland key string, or "" while only modifiers
// are down. Qt.Key_* values are passed in by the caller (QML), so this file needs no Qt import.
var QT_MOD = { meta: 0x10000000, ctrl: 0x04000000, alt: 0x08000000, shift: 0x02000000 };
// Qt key code -> xkb keysym name (the keys Qt reports by code, not by text)
var NAMED = {
    0x01000000: "Escape", 0x01000001: "Tab", 0x01000002: "Tab", 0x01000003: "BackSpace", 0x01000004: "Return",
    0x01000005: "KP_Enter", 0x01000006: "Insert", 0x01000007: "Delete", 0x01000008: "Pause", 0x01000009: "Print",
    0x0100000a: "Sys_Req", 0x0100000b: "Clear", 0x01000010: "Home", 0x01000011: "End", 0x01000012: "Left",
    0x01000013: "Up", 0x01000014: "Right", 0x01000015: "Down", 0x01000016: "Prior", 0x01000017: "Next",
    0x01000024: "Caps_Lock", 0x01000025: "Num_Lock", 0x01000026: "Scroll_Lock", 0x01000055: "Menu",
    0x20: "space", 0x27: "apostrophe", 0x2c: "comma", 0x2d: "minus", 0x2e: "period", 0x2f: "slash",
    0x3b: "semicolon", 0x3d: "equal", 0x5b: "bracketleft", 0x5c: "backslash", 0x5d: "bracketright", 0x60: "grave"
};
// shifted US symbols -> the key they are on (SHIFT + 1 arrives as "!")
var SHIFTED = { 0x21: "1", 0x40: "2", 0x23: "3", 0x24: "4", 0x25: "5", 0x5e: "6", 0x26: "7", 0x2a: "8", 0x28: "9", 0x29: "0",
                0x5f: "minus", 0x2b: "equal", 0x7b: "bracketleft", 0x7d: "bracketright", 0x7c: "backslash", 0x3a: "semicolon",
                0x22: "apostrophe", 0x3c: "comma", 0x3e: "period", 0x3f: "slash", 0x7e: "grave" };
var MOD_KEYS = [0x01000020, 0x01000021, 0x01000022, 0x01000023, 0x01001103, 0x01000053, 0x01000054]; // Shift Ctrl Meta Alt AltGr Super_L Super_R

function isModifierKey(key) { return MOD_KEYS.indexOf(key) >= 0; }
function modsOf(modifiers) {
    var out = [];
    if (modifiers & QT_MOD.meta) out.push("SUPER");
    if (modifiers & QT_MOD.ctrl) out.push("CTRL");
    if (modifiers & QT_MOD.alt) out.push("ALT");
    if (modifiers & QT_MOD.shift) out.push("SHIFT");
    return out;
}
// -> the key's name ("" = unknown: the caller falls back to code:<scan code>)
function qtKeyName(key) {
    if (key >= 0x41 && key <= 0x5a) return String.fromCharCode(key);            // A-Z
    if (key >= 0x30 && key <= 0x39) return String.fromCharCode(key);            // 0-9
    if (key >= 0x01000030 && key <= 0x01000052) return "F" + (key - 0x01000030 + 1);   // F1-F35
    if (NAMED[key] !== undefined) return NAMED[key];
    if (SHIFTED[key] !== undefined) return SHIFTED[key];
    return "";
}
function fromQt(key, modifiers, scanCode) {
    if (isModifierKey(key)) return "";
    var name = qtKeyName(key);
    if (name === "" && scanCode > 0) name = "code:" + scanCode;
    if (name === "") return "";
    return modsOf(modifiers).concat([name]).join(" + ");
}
// a key press the field captures as a combo instead of editing the text: anything with SUPER / CTRL / ALT, or a key
// that types no text (F keys, Pause, Insert ...) other than the editing keys (arrows, Home / End, Backspace / Delete,
// Enter, Tab, Esc) and CTRL + A / C / V / X / Z (select all, copy, paste, cut, undo: type those combos). Plain text
// keys type, so "SUPER + F9" can be written by hand.
var EDIT = [0x01000000, 0x01000001, 0x01000002, 0x01000003, 0x01000004, 0x01000005, 0x01000007, 0x01000010, 0x01000011,
            0x01000012, 0x01000013, 0x01000014, 0x01000015];
var EDIT_CTRL = [0x41, 0x43, 0x56, 0x58, 0x5a];
function captures(key, modifiers, text) {
    if ((modifiers & (QT_MOD.meta | QT_MOD.ctrl | QT_MOD.alt | QT_MOD.shift)) === QT_MOD.ctrl && EDIT_CTRL.indexOf(key) >= 0) return false;
    if (modifiers & (QT_MOD.meta | QT_MOD.ctrl | QT_MOD.alt)) return true;
    if (isModifierKey(key)) return false;
    if (EDIT.indexOf(key) >= 0) return false;
    return !text || /^[\x00-\x1f\x7f]$/.test(text);
}
