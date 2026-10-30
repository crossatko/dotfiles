.pragma library
.import "Ranker.js" as Ranker

// Pure part of the file browser (FileBrowser.qml): the browser's modes (MODES, at the end) and everything they are made of:
// query parsing, lister commands and their output parsers, file categories and Ctrl+K actions, the result rows. No state,
// no processes. Tests: tests/fs.test.js.
// An entry (what a lister yields) = { name, lname, path, dir (bool), size, rel? }; a listing = { base, entries, ok };
// a row = a launcher item of kind "file".

// ---- query parsing: (q = trimmed query, raw = untrimmed, home, codeRoot) -> { base, text, tilde? } or null -----------
// "/..." or "~/...": the folder up to the last "/" (base, with trailing "/"), the text after it filters
function browseQuery(q, raw, home) {
    var t = q;
    if (t.indexOf("~/") === 0) t = home + t.slice(1);
    else if (t.charAt(0) !== "/") return null;
    var i = t.lastIndexOf("/");
    return { base: t.slice(0, i + 1), text: t.slice(i + 1), tilde: q.charAt(0) === "~" };
}
// "f <text>": name search under home
function findQuery(q, raw, home) {
    return /^f\s/.test(q) ? { base: home, text: q.slice(2).trim() } : null;
}
// "code <text>" / "c <text>" on the raw text (a bare "code" / "c" stays a normal search): projects under root
function projectQuery(q, raw, home, codeRoot) {
    var m = typeof raw === "string" ? /^\s*(?:code|c)\s(.*)$/i.exec(raw) : null;
    return m ? { base: codeRoot, text: m[1].trim() } : null;
}

// ---- paths -------------------------------------------------------------------------------------------------------
function tilde(p, home) { return p.indexOf(home + "/") === 0 ? "~" + p.slice(home.length) : p; }
function human(n) {
    var u = ["B", "KB", "MB", "GB", "TB"], i = 0;
    while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
    return (i === 0 ? n : n.toFixed(n < 10 ? 1 : 0)) + " " + u[i];
}
function baseName(p) { return p.slice(p.lastIndexOf("/") + 1); }
function dirName(p) { return p.slice(0, p.lastIndexOf("/")); }

// ---- listers: argv(base, text) and the parser of their output ------------------------------------------------------
// one folder level, NUL-separated "<type>\t<size>\t<name>" records (names may hold newlines)
function folderArgv(dir) {
    return ["timeout", "3", "find", "-H", dir, "-mindepth", "1", "-maxdepth", "1", "-printf", "%Y\\t%s\\t%f\\0"];
}
// folders first, then natural name order; at most 20000 records are read
function parseFolder(text, dir) {
    var out = [], recs = text.split("\u0000");
    for (var k = 0; k < recs.length && out.length < 20000; k++) {
        var rec = recs[k], a = rec.indexOf("\t"), b = rec.indexOf("\t", a + 1);
        if (a < 0 || b < 0) continue;
        var name = rec.slice(b + 1);
        out.push({ name: name, lname: name.toLowerCase(), path: dir + name, dir: rec.slice(0, a) === "d", size: parseInt(rec.slice(a + 1, b)) || 0 });
    }
    out.sort(function (x, y) { return (x.dir === y.dir ? 0 : x.dir ? -1 : 1) || x.lname.localeCompare(y.lname, undefined, { numeric: true }); });
    return out;
}

// Project rule (a few shell globs, no deep walk): a first-level folder with a .git is a project; one without that holds git
// repos is a group whose repos (second level) are the projects; one with neither is a project itself. Hidden folders,
// node_modules and anything deeper than two levels are never looked at (an unmatched glob, empty or missing root, yields nothing).
// NUL-separated absolute paths.
var PROJECT_SCRIPT = "root=$1; for d in \"$root\"/*/; do d=${d%/}; [ -d \"$d\" ] || continue; [ \"${d##*/}\" = node_modules ] && continue; " +
    "if [ -e \"$d/.git\" ]; then printf '%s\\0' \"$d\"; continue; fi; n=0; " +
    "for s in \"$d\"/*/; do s=${s%/}; [ -e \"$s/.git\" ] && { printf '%s\\0' \"$s\"; n=1; }; done; [ $n = 0 ] && printf '%s\\0' \"$d\"; done";
function projectArgv(root) { return ["timeout", "3", "sh", "-c", PROJECT_SCRIPT, "sh", root]; }
function parseProjects(text, root) {
    var out = [], recs = text.split("\u0000");
    for (var k = 0; k < recs.length; k++) {
        var path = recs[k];
        if (path.indexOf(root + "/") !== 0) continue;
        var rel = path.slice(root.length + 1), name = baseName(rel);
        out.push({ name: name, lname: name.toLowerCase(), path: path, dir: true, size: 0, rel: rel, id: "project:" + rel, keywords: rel.split("/") });
    }
    return out;
}

// name search: depth <= 6, junk / huge trees pruned, "<y>\t<path>" lines; text with a "/" matches the whole path
var PRUNE_NAMES = [".git", "node_modules", ".cache", ".steam", ".wine", "drive_c", "compatdata", ".cargo", ".rustup", ".npm"];
var PRUNE_PATHS = ["/.local/share/Steam", "/.local/share/lutris", "/.local/share/wineprefixes", "/.local/share/Trash"];
function globEsc(s) { return s.replace(/[\\*?\[\]]/g, "\\$&"); }
function findArgv(home, text) {
    return ["timeout", "3", "find", home, "-maxdepth", "6"].concat(pruneExpr(home),
        ["-o"], text.indexOf("/") >= 0 ? ["-ipath", "*" + globEsc(text) + "*"] : ["-iname", "*" + globEsc(text) + "*"],
        ["-printf", "%y\t%p\n"]);
}
function pruneExpr(home) {
    var e = ["("];
    PRUNE_NAMES.forEach(function (n) { if (e.length > 1) e.push("-o"); e.push("-name", n); });
    PRUNE_PATHS.forEach(function (p) { e.push("-o", "-path", home + p); });
    return e.concat([")", "-prune"]);
}
function parseFindLine(line) {
    var tab = line.indexOf("\t");
    if (tab < 0) return null;
    var path = line.slice(tab + 1), name = baseName(path);
    return { name: name, lname: name.toLowerCase(), path: path, dir: line.slice(0, tab) === "d", size: 0 };
}

// ---- categories and actions ----------------------------------------------------------------------------------------
var EXTS = {
    image: "png jpg jpeg webp gif bmp avif tif tiff svg ico heic jxl",
    video: "mp4 webm mkv mov avi m4v wmv flv ogv ts",
    audio: "mp3 flac ogg opus wav m4a aac",
    text: "txt md log csv ini conf cfg toml yaml yml json xml lua py js mjs sh zsh bash fish qml css html htm c h cpp hpp rs go java rb php nix kdl rasi tex diff patch service desktop",
    code: "lua py js mjs sh zsh bash fish qml css html htm c h cpp hpp rs go java rb php nix kdl rasi",
    archive: "zip tar gz xz zst bz2 7z rar",
    pdf: "pdf"
};
var TEXT_NAMES = ["makefile", "readme", "license", "dockerfile", "pkgbuild", "changelog"];
var CATS = {
    image: { glyph: "", label: "Image" }, video: { glyph: "", label: "Video" },
    audio: { glyph: "", label: "Audio" }, code: { glyph: "", label: "Code" },
    text: { glyph: "", label: "Text" }, archive: { glyph: "", label: "Archive" },
    pdf: { glyph: "", label: "PDF" }, file: { glyph: "", label: "File" },
    dir: { glyph: "", label: "Folder" }
};
function category(name) {
    var dot = name.lastIndexOf("."), e = dot > 0 ? name.slice(dot + 1).toLowerCase() : "";
    var has = function (k) { return e !== "" && EXTS[k].split(" ").indexOf(e) >= 0; };
    var order = ["image", "video", "audio", "archive", "pdf", "code", "text"];
    for (var i = 0; i < order.length; i++) if (has(order[i])) return order[i];
    return TEXT_NAMES.indexOf(name.toLowerCase()) >= 0 ? "text" : "file";
}
// files an editor makes sense for (unknown types included: extension-less config files)
function editable(cat) { return cat === "text" || cat === "code" || cat === "file"; }

// Ctrl+K entries per type, all non-destructive; Enter itself is the row's run action. `zellij` = the row's Enter already
// opens it in zellij (projects), so the panel does not repeat it.
function actionsFor(cat, zellij) {
    var a = [];
    if (cat === "dir") a.push({ id: "openfolder", label: "Open folder", glyph: "" }, { id: "term", label: "Open terminal here", glyph: "" });
    else if (cat === "image") a.push({ id: "copyfile", label: "Copy image to clipboard", glyph: "" }, { id: "wallpaper", label: "Set as wallpaper (full theme apply)", glyph: "" });
    else if (cat === "video") a.push({ id: "mpv", label: "Play in mpv", glyph: "" }, { id: "wallpaper", label: "Set as video wallpaper (full theme apply)", glyph: "" });
    else if (cat === "text" || cat === "code") a.push({ id: "edit", label: "Open in editor", glyph: "" }, { id: "copyfile", label: "Copy contents to clipboard", glyph: "" });
    if (!zellij) a.push({ id: "zellij", label: zellijLabel(cat), glyph: "" });
    if (cat !== "dir") a.push({ id: "showfolder", label: "Show in folder", glyph: "" });
    a.push({ id: "copypath", label: "Copy path", glyph: "" });
    return a;
}
function zellijLabel(cat) { return cat === "dir" ? "Open in zellij" : editable(cat) ? "Edit in zellij" : "Open its folder in zellij"; }
// what code-open gets: a folder, or a file it opens in the editor (other files: their folder)
function zellijTarget(item) { return item.isDir || editable(item.cat) ? item.path : item.dir; }

// ---- rows ----------------------------------------------------------------------------------------------------------
// One result row. o: { id, name, subtitle, source, glyph, descend, runLabel, zellij (Enter opens in zellij) }; Enter =
// xdg-open, or code-open when o.zellij; rows that do not open in zellij on Enter get it as the Ctrl+Enter `alt` action.
function row(path, isDir, o) {
    var cat = isDir ? "dir" : category(baseName(path)), ci = CATS[cat];
    var r = {
        id: o.id || "file:" + path, name: o.name !== undefined ? o.name : baseName(path), subtitle: o.subtitle || "",
        kind: "file", source: o.source || ci.label, glyph: o.glyph || ci.glyph, transient: true,
        path: path, isDir: isDir, cat: cat, dir: isDir ? path : dirName(path), zellij: !!o.zellij,
        actions: actionsFor(cat, !!o.zellij)
    };
    if (o.runLabel) r.runLabel = o.runLabel;
    if (o.descend !== undefined) r.descend = o.descend;
    if (!o.zellij) r.alt = { id: "zellij", hint: "zellij" };
    return r;
}

// folder browsing: "Open folder" first (the folder itself, or the folder the filter names exactly), then folders, then files;
// hidden entries only when the filter starts with "."; entries whose name starts with the filter first; max 500.
function folderRows(listing, p, home) {
    if (!listing.ok) return [{ id: "file:err:" + p.base, kind: "info", source: "", name: "Cannot read folder", subtitle: tilde(p.base, home), glyph: "", transient: true }];
    var f = p.text.toLowerCase(), hidden = f.charAt(0) === ".";
    var es = listing.entries.map(function (e, i) { return { e: e, i: i, pre: f !== "" && e.lname.indexOf(f) === 0 ? 0 : 1 }; })
        .filter(function (x) { return hidden ? x.e.lname.indexOf(f) === 0 : x.e.name.charAt(0) !== "." && (f === "" || x.e.lname.indexOf(f) >= 0); });
    if (f !== "") es.sort(function (a, b) { return (a.e.dir === b.e.dir ? 0 : a.e.dir ? -1 : 1) || a.pre - b.pre || a.i - b.i; });
    var rows = [];
    var exact = f === "" ? null : es.find(function (x) { return x.e.dir && x.e.lname === f; });
    var open = f === "" ? p.base : exact ? p.base + exact.e.name : "";
    if (open !== "") rows.push(row(open, true, { id: "file:open:" + open, name: "Open folder", subtitle: tilde(open, home), source: "Folder", glyph: "" }));
    es.slice(0, 500).forEach(function (x) {
        var e = x.e;
        rows.push(row(e.path, e.dir, {
            name: e.dir ? e.name + "/" : e.name, subtitle: e.dir ? "" : human(e.size), runLabel: e.dir ? "Browse" : "Open",
            descend: e.dir ? (p.tilde ? tilde(e.path, home) : e.path) + "/" : undefined
        }));
    });
    return rows;
}

// name search: shallowest first, then shorter paths; max 30
function findRows(listing, p, home) {
    var depth = function (e) { return e.path.split("/").length; };
    return listing.entries.slice().sort(function (a, b) { return depth(a) - depth(b) || a.path.length - b.path.length; }).slice(0, 30)
        .map(function (e) { return row(e.path, e.dir, { subtitle: tilde(e.path, home) }); });
}

// projects: ranked by name / path parts (Ranker, no usage), max 50; Enter opens them in zellij
function projectRows(listing, p) {
    var list = p.text === "" ? listing.entries.slice(0, 50) : Ranker.rank(listing.entries, p.text, {}, 0, { limit: 50 }).map(function (r) { return r.item; });
    return list.map(function (e) {
        return row(e.path, true, { id: e.id, name: e.name, subtitle: e.rel, source: "Project", glyph: "\ue0be", runLabel: "Open in zellij", zellij: true });
    });
}

// ---- Tab completion of a path query ("/..." or "~/...", the text as typed; "~" stays) --------------------------------
// entries = the listing of the folder up to the last "/" ([{ name, dir }]), selected = the selected row's entry or null.
// The component after the last "/" is matched as a case-insensitive prefix (hidden entries only when it starts with "."):
// one match completes fully (a folder gets "/"), several complete to their common prefix in the first match's case; when
// nothing is typed or that adds nothing, the selected entry is taken. Returns the new text, or null (nothing to complete).
function completePath(text, entries, selected) {
    var i = text.lastIndexOf("/");
    if (i < 0) return null;
    var head = text.slice(0, i + 1), typed = text.slice(i + 1), f = typed.toLowerCase();
    var full = function (e) { return head + e.name + (e.dir ? "/" : ""); };
    if (typed !== "") {
        var hidden = f.charAt(0) === ".";
        var m = entries.filter(function (e) { return (hidden || e.name.charAt(0) !== ".") && e.name.toLowerCase().indexOf(f) === 0; });
        if (m.length === 1) return full(m[0]);
        if (m.length > 1) {
            var n = m[0].name.length;
            for (var k = 1; k < m.length; k++) {
                var a = m[0].name.toLowerCase(), b = m[k].name.toLowerCase(), j = 0;
                while (j < n && j < b.length && a.charAt(j) === b.charAt(j)) j++;
                n = j;
            }
            if (n > typed.length) return head + m[0].name.slice(0, n);
        }
    }
    return selected ? full(selected) : null;
}

// ---- the modes ------------------------------------------------------------------------------------------------------
// A mode = how a query selects it (match), what lists its entries (argv; read parses the whole output, or readLine each line
// of a streamed lister), how long a listing stays fresh (ttl ms; Infinity = until the launcher opens again), the shortest
// text worth listing (minText) and how the listing becomes rows. Enter / Ctrl+Enter are decided per row (row()).
var MODES = {
    browse:   { title: "Files",    glyph: "\ue0bd", match: browseQuery,  argv: folderArgv,  read: parseFolder,     ttl: 2000,     rows: folderRows },
    find:     { title: "Files",    glyph: "\ue0bd", match: findQuery,    argv: findArgv,    readLine: parseFindLine, minText: 2, rows: findRows },
    projects: { title: "Projects", glyph: "\ue0be", match: projectQuery, argv: projectArgv, read: parseProjects,   ttl: Infinity, rows: projectRows }
};
