const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");
const { load } = require("./load");
const F = load("Fs.js");
const HOME = "/home/user";
// values from the vm context have foreign prototypes: compare as plain JSON
const eq = (a, b) => assert.deepStrictEqual(JSON.parse(JSON.stringify(a)), JSON.parse(JSON.stringify(b)));

test("query parsing per mode", () => {
    eq(F.browseQuery("/etc/pa", "/etc/pa", HOME), { base: "/etc/", text: "pa", tilde: false });
    eq(F.browseQuery("~/Doc", "~/Doc", HOME), { base: HOME + "/", text: "Doc", tilde: true });
    assert.strictEqual(F.browseQuery("etc", "etc", HOME), null);
    assert.strictEqual(F.browseQuery("~", "~", HOME), null);
    eq(F.findQuery("f  notes ", "f  notes ", HOME), { base: HOME, text: "notes" });
    assert.strictEqual(F.findQuery("firefox", "firefox", HOME), null);
    assert.strictEqual(F.findQuery("f", "f", HOME), null);
    eq(F.projectQuery("c x", "c x", HOME, "/r"), { base: "/r", text: "x" });
    eq(F.projectQuery("code", "code ", HOME, "/r"), { base: "/r", text: "" });
    assert.strictEqual(F.projectQuery("code", "code", HOME, "/r"), null);   // bare word stays a normal search
    assert.strictEqual(F.projectQuery("c", "c", HOME, "/r"), null);
    assert.strictEqual(F.projectQuery("codex", "codex", HOME, "/r"), null);
    assert.strictEqual(F.projectQuery("clip", "clip", HOME, "/r"), null);
});

test("paths and sizes", () => {
    assert.strictEqual(F.tilde(HOME + "/a/b", HOME), "~/a/b");
    assert.strictEqual(F.tilde(HOME + "x/a", HOME), HOME + "x/a");
    assert.strictEqual(F.tilde("/etc", HOME), "/etc");
    assert.strictEqual(F.human(512), "512 B");
    assert.strictEqual(F.human(1536), "1.5 KB");
    assert.strictEqual(F.human(20 * 1024 * 1024), "20 MB");
});

test("categories and the zellij target", () => {
    assert.strictEqual(F.category("a.PNG"), "image");
    assert.strictEqual(F.category("x.qml"), "code");
    assert.strictEqual(F.category("notes.md"), "text");
    assert.strictEqual(F.category("Makefile"), "text");
    assert.strictEqual(F.category(".bashrc"), "file");
    assert.strictEqual(F.zellijTarget({ isDir: false, cat: "text", path: "/p/a.md", dir: "/p" }), "/p/a.md");
    assert.strictEqual(F.zellijTarget({ isDir: false, cat: "image", path: "/p/a.png", dir: "/p" }), "/p");
    assert.strictEqual(F.zellijTarget({ isDir: true, cat: "dir", path: "/p/d", dir: "/p/d" }), "/p/d");
    const ids = a => a.map(x => x.id);
    eq(ids(F.actionsFor("dir", false)), ["openfolder", "term", "zellij", "copypath"]);
    eq(ids(F.actionsFor("dir", true)), ["openfolder", "term", "copypath"]);
    eq(ids(F.actionsFor("text", false)), ["edit", "copyfile", "zellij", "showfolder", "copypath"]);
});

const listing = text => ({ ok: true, entries: F.parseFolder(text, "/d/") });
const rec = (t, s, n) => t + "\t" + s + "\t" + n + "\0";
const names = rows => rows.map(r => r.name);

test("folder listing: parse, order, hidden rule, open-folder row, descend", () => {
    const l = listing(rec("f", 10, "b.txt") + rec("d", 0, "Src") + rec("d", 0, ".git") + rec("f", 3, "a\nb") + rec("d", 0, "src2") + "junk\0");
    eq(l.entries.map(e => e.name), [".git", "Src", "src2", "a\nb", "b.txt"]);
    let rows = F.folderRows(l, { base: "/d/", text: "", tilde: false }, HOME);
    eq(names(rows), ["Open folder", "Src/", "src2/", "a\nb", "b.txt"]);
    assert.strictEqual(rows[0].path, "/d/");
    assert.strictEqual(rows[1].descend, "/d/Src/");
    assert.strictEqual(rows[3].descend, undefined);
    assert.strictEqual(rows[4].subtitle, "10 B");
    eq(rows[1].alt, { id: "zellij", hint: "zellij" });
    rows = F.folderRows(l, { base: "/d/", text: "src", tilde: false }, HOME);    // exact folder name -> open that folder
    eq(names(rows), ["Open folder", "Src/", "src2/"]);
    assert.strictEqual(rows[0].path, "/d/Src");
    rows = F.folderRows(l, { base: "/d/", text: "b", tilde: false }, HOME);      // prefix matches first
    eq(names(rows), ["b.txt", "a\nb"]);
    eq(names(F.folderRows(l, { base: "/d/", text: ".g", tilde: false }, HOME)), [".git/"]);
    const hl = { ok: true, entries: F.parseFolder(rec("d", 0, "x"), HOME + "/") };
    assert.strictEqual(F.folderRows(hl, { base: HOME + "/", text: "", tilde: true }, HOME)[1].descend, "~/x/");
    assert.strictEqual(F.folderRows({ ok: false, entries: [] }, { base: "/no/", text: "" }, HOME)[0].kind, "info");
    let many = ""; for (let i = 0; i < 600; i++) many += rec("f", 1, "f" + i);
    assert.strictEqual(F.folderRows(listing(many), { base: "/d/", text: "" }, HOME).length, 501);
});

test("name search rows: shallowest first, max 30", () => {
    const found = ["d\t" + HOME + "/a/b/notes", "f\t" + HOME + "/notes.md", "f\t" + HOME + "/x/notes.txt"].map(F.parseFindLine);
    const rows = F.findRows({ entries: found }, {}, HOME);
    eq(rows.map(r => r.subtitle), ["~/notes.md", "~/x/notes.txt", "~/a/b/notes"]);
    assert.strictEqual(rows[2].isDir, true);
    assert.strictEqual(rows[2].descend, undefined);   // search folders open, they do not descend
    const lots = []; for (let i = 0; i < 40; i++) lots.push(F.parseFindLine("f\t/h/f" + i));
    assert.strictEqual(F.findRows({ entries: lots }, {}, HOME).length, 30);
    const argv = F.findArgv(HOME, "a*b");
    assert.ok(argv.includes("node_modules") && argv.includes(HOME + "/.local/share/Trash"));
    eq(argv.slice(argv.indexOf("-iname"), argv.indexOf("-iname") + 2), ["-iname", "*a\\*b*"]);
    assert.ok(F.findArgv(HOME, "a/b").includes("-ipath"));
});

test("project heuristic on a fake tree, rows open in zellij", () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "fs-test-"));
    try {
        for (const d of ["solo/.git", "group/one/.git", "group/two/.git", "group/notrepo", "plain/sub", ".hidden/.git",
            "node_modules/x/.git", "deep/a/b/.git"]) fs.mkdirSync(path.join(root, d), { recursive: true });
        const argv = F.projectArgv(root), r = spawnSync(argv[0], argv.slice(1), { encoding: "utf8" });
        const ps = F.parseProjects(r.stdout, root);
        eq(ps.map(p => p.rel).sort(), ["deep", "group/one", "group/two", "plain", "solo"]);
        const rows = F.projectRows({ entries: ps }, { text: "two" });
        assert.strictEqual(rows[0].path, root + "/group/two");
        assert.strictEqual(rows[0].zellij, true);
        assert.strictEqual(rows[0].alt, undefined);
        assert.strictEqual(rows[0].id, "project:group/two");
        assert.strictEqual(F.projectRows({ entries: ps }, { text: "" }).length, 5);
    } finally { fs.rmSync(root, { recursive: true, force: true }); }
});

test("project lister: an empty or missing root lists nothing (no literal glob row)", () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "fs-test-"));
    try {
        for (const r of [root, root + "/missing"]) {
            const argv = F.projectArgv(r), out = spawnSync(argv[0], argv.slice(1), { encoding: "utf8" });
            eq(F.parseProjects(out.stdout, r), []);
        }
        fs.mkdirSync(path.join(root, "grp/empty"), { recursive: true });   // a group folder whose only child has no repo
        const argv = F.projectArgv(root), out = spawnSync(argv[0], argv.slice(1), { encoding: "utf8" });
        eq(F.parseProjects(out.stdout, root).map(p => p.rel), ["grp"]);
    } finally { fs.rmSync(root, { recursive: true, force: true }); }
});

test("every mode is complete", () => {
    for (const [name, m] of Object.entries(F.MODES)) {
        assert.ok(m.title && m.glyph && m.match && m.argv && m.rows, name);
        assert.ok(!!m.read !== !!m.readLine, name + ": exactly one of read / readLine");
    }
    assert.strictEqual(F.MODES.browse.match("/x", "/x", HOME, "/r").base, "/");
    assert.strictEqual(F.MODES.projects.match("c a", "c a", HOME, "/r").base, "/r");
});

test("Tab completion of a path query", () => {
    const es = [{ name: "Code", dir: true }, { name: "code-notes.md", dir: false }, { name: "Documents", dir: true },
        { name: "docker.txt", dir: false }, { name: ".config", dir: true }, { name: ".cache", dir: true }, { name: "x", dir: false }];
    const c = (t, sel) => F.completePath(t, es, sel || null);
    assert.strictEqual(c("~/Docu"), "~/Documents/");                 // one match: complete, folder gets "/", "~" kept
    assert.strictEqual(c("~/docum"), "~/Documents/");                // case-insensitive, real case written
    assert.strictEqual(c("/h/x"), "/h/x");                           // a file: its name, no slash
    assert.strictEqual(c("~/co"), "~/Code");                         // common prefix (Code, code-notes.md), first match's case
    assert.strictEqual(c("~/do"), "~/Doc");
    assert.strictEqual(c("~/.c"), null);                            // .config / .cache: nothing to add, no selection
    assert.strictEqual(c("~/.co"), "~/.config/");                    // hidden only when typed with "."
    assert.strictEqual(c("~/con"), null);                            // .config is hidden; nothing matches, nothing selected
    assert.strictEqual(c("~/", { name: "Code", dir: true }), "~/Code/");   // nothing typed: the selected row
    assert.strictEqual(c("~/code", { name: "code-notes.md", dir: false }), "~/code-notes.md");   // prefix adds nothing: selection
    assert.strictEqual(c("~/"), null);
    assert.strictEqual(F.completePath("abc", es, null), null);
});
