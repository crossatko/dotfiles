const test = require("node:test");
const assert = require("node:assert");
const { load } = require("./load");
const R = load("Ranker.js");
const F = load("Frecency.js");
const DAY = 86400000, NOW = 1.8e12;

const items = [
    { id: "ff", name: "Firefox", kind: "app", source: "apps", aliases: ["browser"] },
    { id: "vsc", name: "Visual Studio Code", kind: "app", source: "apps", keywords: ["editor"] },
    { id: "ks", name: "KittyShell", kind: "app", source: "apps" },
    { id: "ft", name: "Files Thing", kind: "app", source: "apps", subtitle: "Manage documents" },
    { id: "gimp", name: "GIMP", kind: "app", source: "apps" },
    { id: "calc", name: "Calculator", kind: "app", source: "apps" },
];
const ids = (rows) => rows.map((r) => r.item.id);
const top = (q, usage) => ids(R.rank(items, q, usage || {}, NOW))[0];

test("exact alias wins", () => assert.strictEqual(top("browser"), "ff"));
test("name prefix", () => assert.strictEqual(top("fire"), "ff"));
test("word boundary prefix", () => assert.strictEqual(top("studio"), "vsc"));
test("acronym", () => {
    assert.strictEqual(top("vsc"), "vsc");
    assert.strictEqual(top("ft"), "ft");
});
test("camelCase boundary", () => assert.strictEqual(top("shell"), "ks"));
test("fuzzy subsequence", () => assert.strictEqual(top("frfx"), "ff"));
test("keyword and subtitle match", () => {
    assert.strictEqual(top("editor"), "vsc");
    assert.strictEqual(top("documents"), "ft");
});
test("multi-token requires all", () => {
    assert.strictEqual(top("visual code"), "vsc");
    assert.strictEqual(JSON.stringify(ids(R.rank(items, "visual zzz", {}, NOW))), JSON.stringify([]));
});
test("non-matches dropped", () => assert.strictEqual(R.rank(items, "qqqq", {}, NOW).length, 0));
test("limit", () => assert.strictEqual(R.rank(items, "", {}, NOW, { limit: 2 }).length, 2));

test("learned term boost", () => {
    const before = ids(R.rank(items, "g", {}, NOW));
    assert.strictEqual(before[0], "gimp");
    const u = F.record({}, "ks", "g", NOW);
    assert.strictEqual(top("g", u), "ks");
});

test("frecency does not drown a clearly better text match", () => {
    let u = {};
    for (let i = 0; i < 200; i++) u = F.record(u, "calc", "", NOW - 1000 * i);
    assert.strictEqual(top("firefox", u), "ff");
});

test("empty query: frecency order, then name", () => {
    let u = F.record({}, "calc", "", NOW - DAY);
    u = F.record(u, "gimp", "", NOW - DAY);
    u = F.record(u, "gimp", "", NOW - DAY / 2);
    const out = ids(R.rank(items, "", u, NOW));
    assert.strictEqual(JSON.stringify(out.slice(0, 2)), JSON.stringify(["gimp", "calc"]));
    assert.strictEqual(JSON.stringify(out.slice(2)), JSON.stringify(["ft", "ff", "ks", "vsc"]));
});

test("pinned first on empty query; hidden excluded", () => {
    let u = F.record({}, "calc", "", NOW);
    u = F.setPinned(u, "vsc", true);
    u = F.setHidden(u, "ff", true);
    const out = ids(R.rank(items, "", u, NOW));
    assert.strictEqual(JSON.stringify(out.slice(0, 2)), JSON.stringify(["vsc", "calc"]));
    assert.ok(!out.includes("ff"));
    assert.ok(!ids(R.rank(items, "firefox", u, NOW)).includes("ff"));
    assert.ok(ids(R.rank(items, "firefox", u, NOW, { includeHidden: true })).includes("ff"));
});

test("rank does not mutate inputs", () => {
    const u = F.record({}, "ff", "f", NOW);
    const a = JSON.stringify(items), b = JSON.stringify(u);
    R.rank(items, "f", u, NOW);
    assert.strictEqual(JSON.stringify(items), a);
    assert.strictEqual(JSON.stringify(u), b);
});

test("section row wins an exact tie with a same-named app, for every prefix of the name", () => {
    const sec = { id: "sec:jf", name: "Jellyfin", subtitle: "Movies", keywords: ["jellyfin"], aliases: ["jf"], kind: "section" };
    const app = { id: "app:jf", name: "Jellyfin", subtitle: "", keywords: ["Desktop client"], kind: "app" };
    for (const q of ["jell", "jelly", "jellyf", "jellyfin"]) {
        assert.strictEqual(R.rank([app, sec], q, {}, NOW)[0].item.id, "sec:jf", q);
        assert.strictEqual(R.rank([sec, app], q, {}, NOW)[0].item.id, "sec:jf", q);
    }
});
