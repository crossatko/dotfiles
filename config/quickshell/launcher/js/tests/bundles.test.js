const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { load } = require("./load");
const B = load("Bundles.js");
const eq = (a, b) => assert.deepStrictEqual(JSON.parse(JSON.stringify(a)), JSON.parse(JSON.stringify(b)));
const optDir = path.join(__dirname, "../../../../../packages/optional");

test("parsePackages: names, comments, blanks", () => {
    eq(B.parsePackages("# head\n\nfoo\n  bar-git  # why\nbaz_2\n#qux\n"), ["foo", "bar-git", "baz_2"]);
    eq(B.parsePackages(""), []);
});

test("installCommand", () => {
    assert.strictEqual(B.installCommand(["a", "b-git"]), "yay -S --needed a b-git");
});

test("fallback names match packages/optional/<name>.txt", () => {
    for (const name of Object.keys(B.BUNDLES)) {
        const f = path.join(optDir, name + ".txt");
        assert.ok(fs.existsSync(f), f + " missing");
        eq(B.parsePackages(fs.readFileSync(f, "utf8")), B.BUNDLES[name].fallback);
    }
    // every list file has a bundle entry
    for (const f of fs.readdirSync(optDir).filter(f => f.endsWith(".txt"))) assert.ok(B.BUNDLES[f.slice(0, -4)], f + " has no entry in Bundles.js");
});

test("checkArgv + parseMissing against a PATH with and without the binaries", () => {
    const argv = Array.from(B.checkArgv());
    const run = env => spawnSync("/bin/sh", argv.slice(1), { encoding: "utf8", env }).stdout;
    eq(Object.keys(B.parseMissing(run({ PATH: "/nonexistent" }))).sort(), Object.keys(B.BUNDLES).sort());
    const bin = fs.mkdtempSync(path.join(require("os").tmpdir(), "bundles-"));
    for (const n of ["rife-ncnn-vulkan", "quickemu"]) { fs.writeFileSync(path.join(bin, n), "#!/bin/sh\n", { mode: 0o755 }); }
    // quickemu alone is not enough for virtualization (quickget missing too); rife is complete
    const m = B.parseMissing(run({ PATH: bin + ":/nonexistent" }));
    eq(Object.keys(m).sort(), ["gaming", "virtualization"]);
    eq(B.parseMissing("bogus\n"), {});
});

test("hintRow", () => {
    const r = B.hintRow("gaming", "yay -S --needed x", { name: "Switch to Gamescope" });
    assert.strictEqual(r.kind, "pkg-hint");
    assert.strictEqual(r.name, "Switch to Gamescope");
    assert.strictEqual(r.installCommand, "yay -S --needed x");
});
