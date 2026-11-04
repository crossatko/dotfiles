const test = require("node:test");
const assert = require("node:assert");
const { load } = require("./load");
const D = load("DictLangs.js");
const plain = v => JSON.parse(JSON.stringify(v));

test("the list has whisper's languages", () => {
    assert.strictEqual(D.LANGS.length, 100);
    assert.strictEqual(D.name("cs"), "Czech");
    assert.strictEqual(D.name("zz"), "ZZ");
    assert.ok(D.isCode("yue") && !D.isCode("auto") && !D.isCode("CS") && !D.isCode(5));
});

test("normalize: valid, unique, in order", () => {
    assert.deepStrictEqual(plain(D.normalize(["ja", "xx", "ja", "cs", 3])), ["ja", "cs"]);
    assert.deepStrictEqual(plain(D.normalize("cs")), []);
});

test("entries: Auto always, a key per language, a translate key for every language but English", () => {
    assert.deepStrictEqual(plain(D.entriesFor([]).map(e => e.name)), ["ptt-auto"]);
    const e = D.entriesFor(["cs", "en", "ja"]);
    assert.deepStrictEqual(plain(e.map(x => x.name)), ["ptt-auto", "ptt-cs", "ptt-cs-en", "ptt-en", "ptt-ja", "ptt-ja-en"]);
    const t = e.find(x => x.name === "ptt-cs-en");
    assert.strictEqual(t.service, "translate:cs");
    assert.strictEqual(t.pill, "cs-en");
    assert.strictEqual(t.label, "Czech → English");
    assert.strictEqual(e.find(x => x.name === "ptt-en").service, "en");
    assert.strictEqual(e[0].service, "auto");
});

test("parseName", () => {
    assert.deepStrictEqual(plain(D.parseName("ptt-ja")), { lang: "ja", translate: false });
    assert.deepStrictEqual(plain(D.parseName("ptt-cs-en")), { lang: "cs", translate: true });
    assert.deepStrictEqual(plain(D.parseName("ptt-auto")), { lang: "auto", translate: false });
    for (const bad of ["ptt-en-en", "ptt-xx", "ptt-", "ptt-cs-de", "quickshell:ptt-cs", "x", "ptt-CS"])
        assert.strictEqual(D.parseName(bad), null, bad);
});

test("search: code or name, prefix first, skips the chosen", () => {
    assert.strictEqual(D.search("czech")[0].code, "cs");
    assert.strictEqual(D.search("cs")[0].code, "cs");
    assert.strictEqual(D.search("", ["cs"]).length, 99);
    const r = D.search("ta").map(l => l.code);
    assert.ok(r.indexOf("ta") < r.indexOf("fa") || r.indexOf("fa") < 0, "a name starting with it comes first");
    assert.deepStrictEqual(plain(D.search("zzzz")), []);
});
