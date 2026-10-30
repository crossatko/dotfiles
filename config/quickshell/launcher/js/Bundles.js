.pragma library

// Optional package bundles (packages/optional/<name>.txt in the repo): metadata for the "not installed" hints, the
// install-command builder and the missing-binary check. Pure functions, no state, no processes (OptionalPackages.qml
// runs them). The package NAMES live in packages/optional/<name>.txt; `fallback` below is only used when that file
// cannot be read at runtime (tests/bundles.test.js fails when it drifts from the files).

var BUNDLES = {
    "virtualization": {
        title: "Virtual machines need quickemu",
        desc: "Install the virtualization bundle (quickemu, QEMU, TPM, SPICE) to create and run VMs.",
        bins: ["quickemu", "quickget"],
        fallback: ["quickemu-git", "qemu-desktop", "swtpm", "spice-gtk"]
    },
    "video-wallpaper": {
        title: "RIFE is not installed",
        desc: "Optional quality upgrade for the wind-down and replay frames of video wallpapers. Without it the theme engine falls back to ffmpeg's slower, lower-quality interpolation.",
        bins: ["rife-ncnn-vulkan"],
        fallback: ["rife-ncnn-vulkan-bin"]
    },
    "gaming": {
        title: "Gamescope is not installed",
        desc: "Install the gaming bundle (Steam, gamescope, gamemode, MangoHud) to use the Gamescope session.",
        bins: ["gamescope", "steam"],
        fallback: ["steam", "gamescope", "gamemode", "mangohud"]
    }
};

// one package name per line, `#` starts a comment (whole line or trailing), blanks ignored
function parsePackages(text) {
    var out = [];
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var l = lines[i].replace(/#.*$/, "").trim();
        if (/^[A-Za-z0-9@._+-]+$/.test(l)) out.push(l);
    }
    return out;
}

function installCommand(pkgs) { return "yay -S --needed " + pkgs.join(" "); }

// `sh -c SCRIPT sh bundle:bin,bin ...`: prints the name of every bundle with a missing binary, one per line
var CHECK_SCRIPT = 'for a; do n=${a%%:*}; l=${a#*:}; ( IFS=,; for b in $l; do command -v "$b" >/dev/null 2>&1 || { echo "$n"; exit; }; done ); done';
function checkArgv() {
    var argv = ["sh", "-c", CHECK_SCRIPT, "sh"];
    for (var k in BUNDLES) argv.push(k + ":" + BUNDLES[k].bins.join(","));
    return argv;
}
function parseMissing(out) {
    var m = {};
    var lines = String(out || "").split("\n");
    for (var i = 0; i < lines.length; i++) if (BUNDLES[lines[i].trim()]) m[lines[i].trim()] = true;
    return m;
}

// a launcher row (kind "pkg-hint": Enter copies the command). `over` overrides row fields (e.g. the name of a power row).
function hintRow(bundle, cmd, over) {
    var b = BUNDLES[bundle];
    var row = { id: "pkg:" + bundle, name: b.title, subtitle: "Enter copies: " + cmd, kind: "pkg-hint", source: "", glyph: "",
                iconColor: "muted", transient: true, private: true, installCommand: cmd, runLabel: "Copy command" };
    for (var k in (over || {})) row[k] = over[k];
    return row;
}
