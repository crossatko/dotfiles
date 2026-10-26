const test = require("node:test");
const assert = require("node:assert");
const { load } = require("./load");
const C = load("CalEvent.js");

test("minutes parses HH:MM only", () => {
    assert.strictEqual(C.minutes("09:30"), 570);
    assert.strictEqual(C.minutes("9:05"), 545);
    assert.strictEqual(C.minutes("24:00"), -1);
    assert.strictEqual(C.minutes("12:60"), -1);
    assert.strictEqual(C.minutes("abc"), -1);
});

test("default start: next full hour today, 09:00 otherwise", () => {
    const now = new Date(2026, 9, 26, 14, 20);
    assert.strictEqual(C.defaultStart(new Date(2026, 9, 26), now), "15:00");
    assert.strictEqual(C.defaultStart(new Date(2026, 9, 27), now), "09:00");
    assert.strictEqual(C.defaultStart(new Date(2026, 9, 26), new Date(2026, 9, 26, 23, 10)), "22:00");
    assert.strictEqual(C.plusHour("15:00"), "16:00");
    assert.strictEqual(C.plusHour("23:30"), "23:59");
});

test("validate", () => {
    assert.match(C.validate("  ", "09:00", "10:00", false), /title/);
    assert.match(C.validate("x", "9am", "10:00", false), /Times/);
    assert.match(C.validate("x", "10:00", "10:00", false), /after/);
    assert.strictEqual(C.validate("x", "09:00", "10:00", false), "");
    assert.strictEqual(C.validate("x", "", "", true), "");
});

test("multi-day validation", () => {
    assert.match(C.validate("x", "09:00", "10:00", false, "2026-10-27", "2026-10-26"), /before/);
    assert.match(C.validate("x", "09:00", "10:00", false, "2026-10-27", "27.10."), /Date/);
    assert.match(C.validate("x", "09:00", "08:00", false, "2026-10-27", "2026-10-27"), /after/);
    assert.strictEqual(C.validate("x", "09:00", "08:00", false, "2026-10-27", "2026-10-28"), "");
    assert.strictEqual(C.validate("x", "", "", true, "2026-10-27", "2026-10-29"), "");
    assert.strictEqual(C.validate("x", "09:00", "10:00", false, "2026-10-27", ""), "");
    assert.strictEqual(C.validDate("2026-02-30"), false);
    assert.strictEqual(C.shiftDate("2026-10-31", 1), "2026-11-01");
});

test("createArgs multi-day", () => {
    assert.deepStrictEqual([...C.createArgs("omacal", "T", "2026-10-27", "9:00", "10:00", false, "2026-10-29")],
        ["omacal", "events", "create", "--title", "T", "--date", "2026-10-27", "--start", "09:00", "--end-date", "2026-10-29", "--end", "10:00", "--json"]);
    assert.deepStrictEqual([...C.createArgs("omacal", "T", "2026-10-27", "", "", true, "2026-10-29")],
        ["omacal", "events", "create", "--title", "T", "--date", "2026-10-27", "--all-day", "--last-day", "2026-10-29", "--json"]);
    assert.deepStrictEqual([...C.createArgs("omacal", "T", "2026-10-27", "9:00", "10:00", false, "2026-10-27")].includes("--end-date"), false);
});

test("createArgs keeps keeps user text as one argv element", () => {
    const t = "a; rm -rf ~ $(x) \"q\"";
    assert.deepStrictEqual([...C.createArgs("omacal", "  " + t + " ", "2026-10-27", "9:00", "10:30", false)],
        ["omacal", "events", "create", "--title", t, "--date", "2026-10-27", "--start", "09:00", "--end", "10:30", "--json"]);
    assert.deepStrictEqual([...C.createArgs("omacal", "Day", "2026-10-27", "", "", true)],
        ["omacal", "events", "create", "--title", "Day", "--date", "2026-10-27", "--all-day", "--last-day", "2026-10-27", "--json"]);
});

test("parseResult", () => {
    assert.deepStrictEqual(Object.assign({}, C.parseResult('{"ok":true,"data":{}}', 0)), { ok: true, message: "" });
    assert.strictEqual(C.parseResult('{"ok":false,"error":{"code":"x","message":"conflict"}}', 6).message, "conflict");
    assert.strictEqual(C.parseResult("", 4).ok, false);
});

test("calendar id is passed as --calendar", () => {
    assert.deepStrictEqual([...C.createArgs("omacal", "T", "2026-10-27", "9:00", "10:00", false, "", 7)],
        ["omacal", "events", "create", "--title", "T", "--date", "2026-10-27", "--start", "09:00", "--end", "10:00", "--calendar", "7", "--json"]);
    assert.deepStrictEqual([...C.createArgs("omacal", "T", "2026-10-27", "", "", true, "2026-10-28", 12)],
        ["omacal", "events", "create", "--title", "T", "--date", "2026-10-27", "--all-day", "--last-day", "2026-10-28", "--calendar", "12", "--json"]);
    assert.strictEqual(C.createArgs("omacal", "T", "2026-10-27", "9:00", "10:00", false, "", -1).includes("--calendar"), false);
});

test("pickCalendar: last used, else primary, else first", () => {
    const l = [{ id: 3 }, { id: 7, primary: true }, { id: 9 }];
    assert.strictEqual(C.pickCalendar(l, 9), 2);
    assert.strictEqual(C.pickCalendar(l, 99), 1);
    assert.strictEqual(C.pickCalendar([{ id: 3 }, { id: 4 }], undefined), 0);
    assert.strictEqual(C.pickCalendar([], 1), -1);
});
