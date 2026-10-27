#!/usr/bin/env python3
"""Run the extractor + palette builder against nasty synthetic wallpapers and
assert the result is always usable. `python3 -I selftest.py`"""
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

# the analysis / probe caches of this run live in a temp dir (never the real ~/.cache/theme; nothing is a stale hit)
_CACHE = tempfile.TemporaryDirectory()
os.environ["XDG_CACHE_HOME"] = _CACHE.name
spec = importlib.util.spec_from_file_location("theme", Path(__file__).with_name("theme.py"))
theme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(theme)

CASES = {
    "black": ["-size", "800x600", "xc:black"],
    "white": ["-size", "800x600", "xc:white"],
    "mid-grey": ["-size", "800x600", "xc:#808080"],
    "grey-gradient": ["-size", "800x600", "gradient:black-white"],
    "solid-red": ["-size", "800x600", "xc:#ff0000"],
    "solid-yellow": ["-size", "800x600", "xc:#ffee00"],
    "pastel": ["-size", "800x600", "gradient:#ffd1dc-#d1f0ff"],
    "rainbow": ["-size", "800x600", "gradient:red-blue", "-colorspace", "HSL", "-separate", "-combine"],
    "noise": ["-size", "800x600", "xc:", "+noise", "Random"],
    "photo-ish": ["-size", "800x600", "plasma:fractal"],
    "tiny-1x1": ["-size", "1x1", "xc:#3366cc"],
    "tiny-2x1": ["-size", "2x1", "gradient:red-blue"],
    "bright-photo-teal": ["-size", "800x600", "gradient:#e0fff8-#40a090"],
    "dark-blue-night": ["-size", "800x600", "gradient:#02040c-#0a1a3c"],
    "transparent": ["-size", "400x400", "xc:none", "-fill", "#22cc66", "-draw", "circle 200,200 200,100"],
    "cmyk": ["-size", "400x400", "gradient:#ff8800-#0044ff", "-colorspace", "CMYK"],
    "16bit": ["-size", "400x400", "gradient:#445566-#ddeeff", "-depth", "16"],
    "wide-panorama": ["-size", "6000x300", "gradient:#301030-#f0a040"],
    "red-streak-on-black": ["-size", "800x400", "xc:#151515", "-fill", "#701c1a", "-draw", "rectangle 100,50 160,56"],
}
EXTRA_FORMATS = {"anim.gif": ["-size", "100x100", "xc:red", "(", "-size", "100x100", "xc:blue", ")", "-loop", "0"]}

OM_KEYS = ("mode accent selection muted background dark_background darker_background lighter_background foreground "
           "dark_foreground light_foreground bright_foreground red yellow orange green cyan blue magenta brown bright_red "
           "bright_yellow bright_green bright_cyan bright_blue bright_magenta").split()


def omarchy_problems(pal, mode):
    """Render templates/omarchy/colors.toml and check it the way Omarchy's line-based parser reads it."""
    text = theme.render((theme.ROOT / "templates/omarchy/colors.toml").read_text(), pal,
                        {"mode": mode, **theme.omarchy_extras(pal, mode)})
    got, bad = {}, []
    for line in text.splitlines():
        if not line.strip():
            continue
        m = re.fullmatch(r'([A-Za-z0-9_-]+) = "([^"]*)"', line)
        if not m:
            bad.append(f"line {line!r}")
            continue
        got[m.group(1)] = m.group(2)
    bad += [f"missing {k}" for k in OM_KEYS if k not in got]
    bad += [f"extra {k}" for k in got if k not in OM_KEYS]
    bad += [f"{k} not #rrggbb" for k, v in got.items() if k != "mode" and not re.fullmatch(r"#[0-9a-f]{6}", v)]
    if got.get("mode") != mode:
        bad.append("mode")
    if not bad:
        lum = lambda k: theme.luminance(got[k])
        # (a pure #000000 background cannot get darker: equal is all that is possible there)
        ok = lum("darker_background") <= lum("dark_background") <= lum("background") and (lum("background") == 0 or lum("dark_background") < lum("background"))
        if not ok:
            bad.append("background shades not ordered darker < dark < background")
        if mode == "dark" and not lum("lighter_background") > lum("background"):
            bad.append("dark: lighter_background not lighter")
    return bad


fails = 0
with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    jobs = {f"{k}.png": v for k, v in CASES.items()}
    jobs["cmyk.jpg"] = CASES["cmyk"]
    jobs.update(EXTRA_FORMATS)
    for name, args in jobs.items():
        img = d / name
        subprocess.run(["magick", *args, str(img)], check=True)
        try:
            base = theme.extract(img)
            pal = theme.build_palette(base, {})
        except SystemExit as e:
            print(f"FAIL {name}: exit {e}")
            fails += 1
            continue
        bg = pal["bg"]
        checks = {
            "fg>=9": theme.contrast(pal["fg"], bg) >= 9,
            "accent>=4.5": theme.contrast(pal["accent"], bg) >= 4.5,
            "muted>=2.9": theme.contrast(pal["muted"], bg) >= 2.9,
            "subtle>=4.4": theme.contrast(pal["subtle"], bg) >= 4.4,
            "ansi>=4.5": all(theme.contrast(pal[c], bg) >= 4.5 for c in ("green", "yellow", "blue", "cyan", "magenta")),
            "bg dark": theme.luminance(bg) < 0.03,
            "all hex": all(len(v) == 7 and v[0] == "#" for v in pal.values()),
        }
        lp = theme.build_palette(base, {}, "light")   # the light palette must read just as well
        lbg = lp["bg"]
        checks.update({
            "light fg>=9": theme.contrast(lp["fg"], lbg) >= 9,
            "light accent>=4.5": theme.contrast(lp["accent"], lbg) >= 4.5,
            "light muted>=4.1": theme.contrast(lp["muted"], lbg) >= 4.1,
            "light subtle>=4.4": theme.contrast(lp["subtle"], lbg) >= 4.4,
            "light ansi>=4.5": all(theme.contrast(lp[c], lbg) >= 4.5 for c in ("red", "green", "yellow", "blue", "cyan", "magenta")),
            "light bg light": theme.luminance(lbg) > 0.7,
            "light all hex": all(len(v) == 7 and v[0] == "#" for v in lp.values()),
        })
        bad = [k for k, ok in checks.items() if not ok]
        bad += [f"omarchy dark: {p}" for p in omarchy_problems(pal, "dark")]
        bad += [f"omarchy light: {p}" for p in omarchy_problems(lp, "light")]
        status = "ok  " if not bad else "FAIL"
        fails += bool(bad)
        print(f"{status} {name:26} bg {bg} fg {pal['fg']} accent {pal['accent']} (found color: {base['accent'] is not None}) {bad or ''}")


# ---- standout accent (theme.standout_accent): small salient details, not noise
def hue_deg(h):
    (_, a, b) = theme.oklab(theme.hex_to_rgb(h))
    import math
    return math.degrees(math.atan2(b, a)) % 360


def hue_dist_deg(x, y):
    return abs((hue_deg(x) - hue_deg(y) + 180) % 360 - 180)


def is_red(h):
    return h is not None and (hue_deg(h) < 45 or hue_deg(h) > 340)


def field(w, h, rgb, square=None, sq_rgb=(220, 30, 25)):
    """A frame (w, h, px) of one colour with an optional square (x, y, size) of another."""
    px = [rgb] * (w * h)
    if square:
        x0, y0, n = square
        for y in range(y0, y0 + n):
            for x in range(x0, x0 + n):
                px[y * w + x] = sq_rgb
    return w, h, px


def so_check(name, ok, info=""):
    global fails
    fails += not ok
    print(f"{'ok  ' if ok else 'FAIL'} standout {name:24} {info}")


BLUE = (42, 77, 143)
with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    imgs = {
        "red-blob-on-blue": ["-size", "800x450", "xc:#2a4d8f", "-fill", "#d0201c", "-draw", "circle 500,150 500,162"],
        "noise": ["-size", "800x450", "xc:", "+noise", "Random"],
        "mono-blob": ["-size", "800x450", "gradient:#202020-#e0e0e0", "-fill", "#909090", "-draw", "circle 400,200 400,215"],
        "faint-blob": ["-size", "800x450", "xc:#3a4450", "-fill", "#4a4448", "-draw", "circle 400,200 400,215"],
        "corner-logo": ["-size", "800x450", "xc:#2a4d8f", "-fill", "#d0201c", "-draw", "rectangle 2,2 20,12"],
    }
    got = {}
    for name, args in imgs.items():
        subprocess.run(["magick", *args, str(d / f"{name}.png")], check=True)
        got[name] = theme.extract(d / f"{name}.png")
    b = got["red-blob-on-blue"]
    dom = theme.build_palette(b, {"settings": {"accent_pick": "dominant"}})
    so = theme.build_palette(b, {"settings": {"accent_pick": "standout"}})
    so_check("blob: standout = red", is_red(so["accent"]) and theme.contrast(so["accent"], so["bg"]) >= 4.5, so["accent"])
    so_check("blob: dominant = blue", 200 < hue_deg(dom["accent"]) < 290, dom["accent"])
    so_check("blob: accent2 = image blue", 200 < hue_deg(so["accent2"]) < 290, so["accent2"])
    lso = theme.build_palette(b, {"settings": {"accent_pick": "standout"}}, "light")
    so_check("blob: light standout", is_red(lso["accent"]) and theme.contrast(lso["accent"], lso["bg"]) >= 4.5, lso["accent"])
    for name in ("noise", "mono-blob", "faint-blob", "corner-logo"):
        so_check(f"{name}: none", got[name]["standout"] is None and got[name]["standout2"] is None, str(got[name]["standout"]))
    p = theme.build_palette(got["mono-blob"], {})
    so_check("mono: falls back to fg", p["accent"] == p["fg"], p["accent"])
    # fine pass: a 4x4 px green and a 4x4 px red detail on a dark blue 1280 px field (eyes / earrings of a 4K frame)
    tiny = ["-size", "1280x720", "xc:#141c33", "-fill", "#30e070", "-draw", "rectangle 500,300 503,303",
            "-fill", "#e02838", "-draw", "rectangle 760,420 763,423"]
    subprocess.run(["magick", *tiny, str(d / "tiny.png")], check=True)
    t = theme.extract(d / "tiny.png")
    pair = {is_red(t["standout"] or "#000000"), is_red(t["standout2"] or "#000000")}
    green = [c for c in (t["standout"], t["standout2"]) if c and 120 < hue_deg(c) < 170]
    so_check("tiny: red + green", pair == {True, False} and len(green) == 1, f"{t['standout']} {t['standout2']}")
    tp = theme.build_palette(t, {})
    so_check("tiny: accent2 = 2nd detail", hue_dist_deg(tp["accent2"], t["standout2"]) < 15 and theme.contrast(tp["accent2"], tp["bg"]) >= 4.5, tp["accent2"])
    subprocess.run(["magick", "-size", "1280x720", "xc:", "+noise", "Random", str(d / "noise1280.png")], check=True)
    n = theme.extract(d / "noise1280.png")
    so_check("noise 1280: none", n["standout"] is None and n["standout2"] is None, str(n["standout"]))
    # fine-pass frames: a 4x4 detail in 1 of 9 frames is a flash, in 6 of 9 (moving) it persists
    def tiny_frames(present):
        fr = []
        for i in range(9):
            f = d / f"f{i}.png"
            args = ["-size", "1280x720", "xc:#141c33"]
            if present(i):
                args += ["-fill", "#e02838", "-draw", f"rectangle {400 + 30 * i},300 {403 + 30 * i},303"]
            subprocess.run(["magick", *args, str(f)], check=True)
            fr.append(theme.analysis_frame([f"{f}[0]"]))
        return fr
    so_check("tiny video flash: none", not theme.standout_accent(tiny_frames(lambda i: i == 4)))
    r = theme.standout_accent(tiny_frames(lambda i: i % 3 != 0))
    so_check("tiny video persistent: red", len(r) == 1 and is_red(r[0][0]), str(r))
    # a vivid red glow (robot eyes) on a dull warm brown / peach scene: close in hue to the dominant colour, but far more
    # intense: it must still win; a same-intensity brown detail on it must not
    warm = ["-size", "1280x720", "gradient:#8a6a55-#c79a80", "-fill", "#f04a3a", "-draw", "circle 400,250 400,258",
            "-draw", "circle 900,260 900,268"]
    subprocess.run(["magick", *warm, str(d / "warm.png")], check=True)
    wb = theme.extract(d / "warm.png")
    wp = theme.build_palette(wb, {})
    so_check("warm field: red eyes win", is_red(wb["standout"]) and is_red(wp["accent"]) and theme.contrast(wp["accent"], wp["bg"]) >= 4.5, f"{wb['standout']} -> {wp['accent']}")
    dull = ["-size", "1280x720", "gradient:#8a6a55-#c79a80", "-fill", "#a07058", "-draw", "circle 400,250 400,258"]
    subprocess.run(["magick", *dull, str(d / "dull.png")], check=True)
    so_check("warm field: dull spot none", theme.extract(d / "dull.png")["standout"] is None)
    # hot pixels: 60 isolated red pixels on the analysis grid itself (no resize can hide them)
    w, h, px = field(320, 180, BLUE)
    for i in range(60):
        px[(i * 7919) % (w * h)] = (255, 16, 16)
    so_check("hot pixels: none", not theme.standout_accent([(w, h, px)]))
    # video frames: a red detail in 1 of 9 frames is a flash, in 6 of 9 (moving) it persists
    flash = [field(160, 90, BLUE, (60, 30, 8) if i == 4 else None) for i in range(9)]
    so_check("video flash: none", not theme.standout_accent(flash))
    persist = [field(160, 90, BLUE, (40 + 6 * i, 30, 8) if i % 3 else None) for i in range(9)]
    r = theme.standout_accent(persist)
    so_check("video persistent: red", len(r) == 1 and is_red(r[0][0]), str(r))


# ---- play-once timing defaults: nothing stored = play 0 s, wind 5 s, ease 0 (theme.toml); explicit values win
def t_check(name, ok, info=""):
    global fails
    fails += not ok
    print(f"{'ok  ' if ok else 'FAIL'} timing {name:30} {info}")


import os
import tomllib
tracked = tomllib.loads((theme.ROOT / "theme.toml").read_text())
t_check("theme.toml defaults 0 / 5 / 0", (tracked.get("replay_play_default"), tracked.get("replay_wind_default"), tracked.get("replay_ease_in")) == (0.0, 5.0, 0.0))
t_check("built-in defaults 0 / 5 / 0", (theme.PLAY_DEFAULT, theme.WIND_DEFAULT, theme.BAKE_EASE) == (0.0, 5.0, 0.0))
dp, dw = theme.timing_default()
bare = theme.norm_entry({"video": "~/v.mp4", "mode": "once", "still": ""})
t_check("no timing -> defaults", (bare.get("play"), bare.get("wind")) == (dp, dw) and "ease" not in bare, str(bare))
own = theme.norm_entry({"video": "~/v.mp4", "mode": "once", "still": "", "play": 12, "wind": 3, "ease": 0.6})
t_check("stored timing kept", (own["play"], own["wind"], own["ease"]) == (12.0, 3.0, 0.6), str(own))
full = theme.norm_entry({"video": "~/v.mp4", "mode": "once", "still": "", "play": "full"})
t_check("full length kept", full["play"] == theme.PLAY_FULL and theme.clamp_timing(full["play"], 0) == (None, 0.0), str(full))
loop = theme.norm_entry({"video": "~/v.mp4", "mode": "loop", "still": ""})
t_check("loop untouched", set(loop) == {"video", "mode", "still"}, str(loop))
with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    old_cache = os.environ.get("XDG_CACHE_HOME")
    os.environ["XDG_CACHE_HOME"] = str(d / "cache")   # stills / hold analyses of the test clips stay in the temp dir
    try:
        for name, secs in (("long", 10), ("short", 2)):
            subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-f", "lavfi", "-i", f"testsrc=size=160x90:rate=10:duration={secs}",
                            "-pix_fmt", "yuv420p", "-y", str(d / f"{name}.mp4")], check=True)
        lv, sv = str(d / "long.mp4"), str(d / "short.mp4")
        t_check("plan play 0 wind 5", theme.video_plan(lv, dp, dw) == (0.0, 5.0, 2.5), str(theme.video_plan(lv, dp, dw)))
        sp = theme.video_plan(sv, dp, dw)
        t_check("short clip: wind shortened", sp is not None and sp[0] == 0.0 and sp[1] < 5.0 and sp[2] <= 2.0, str(sp))
        e = theme.make_entry(lv, "once")
        t_check("new entry gets defaults", (e.get("play"), e.get("wind")) == (dp, dw) and e["still"].endswith("-t2500.png"), str(e))
        e = theme.make_entry(lv, "once", "full")
        t_check("--play full = full length", e.get("play") == theme.PLAY_FULL and theme.video_plan(lv, e["play"], 0) is None, str(e))
        e = theme.make_entry(lv, "once", "4", "2", "0.3")
        t_check("explicit values win", (e["play"], e["wind"], e["ease"]) == (4.0, 2.0, 0.3), str(e))
        e = theme.make_entry(lv, "loop")
        t_check("loop entry has no timing", "play" not in e and "wind" not in e, str(e))
    finally:
        if old_cache is None:
            os.environ.pop("XDG_CACHE_HOME", None)
        else:
            os.environ["XDG_CACHE_HOME"] = old_cache


# ---- analysis cache, theme-blobs (native standout pass) vs the Python reference, the instant-switch pipeline
def c_check(name, ok, info=""):
    global fails
    fails += not ok
    print(f"{'ok  ' if ok else 'FAIL'} switch {name:34} {info}")


def same_blobs(a, b):
    return [[tuple(map(repr, x[:2])) + (tuple(x[2]), x[3]) for x in f] for f in a] == \
           [[tuple(map(repr, x[:2])) + (tuple(x[2]), x[3]) for x in f] for f in b]


with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    img = d / "blob.png"
    subprocess.run(["magick", "-size", "800x450", "xc:#2a4d8f", "-fill", "#d0201c", "-draw", "circle 500,150 500,162",
                    "-fill", "#30e070", "-draw", "rectangle 200,300 204,304", str(img)], check=True)
    calls = []
    real_frame = theme.analysis_frame
    theme.analysis_frame = lambda *a, **k: calls.append(1) or real_frame(*a, **k)
    try:
        first = theme.extract(img)
        c_check("cache miss analyses", len(calls) == 1 and theme.analysis_file("img", img).exists())
        calls.clear()
        c_check("cache hit: no decode, same result", theme.extract(img) == first and not calls)
        st = img.stat()
        os.utime(img, ns=(st.st_atime_ns, st.st_mtime_ns + 10**9))
        calls.clear()
        c_check("file changed: re-analysed", theme.extract(img) == first and len(calls) == 1)
        theme.EXTRACT_VERSION += 1
        calls.clear()
        c_check("version bump: re-analysed", theme.extract(img) == first and len(calls) == 1)
        theme.EXTRACT_VERSION -= 1
    finally:
        theme.analysis_frame = real_frame
    one = real_frame([f"{img}[0]"], small=True)
    c_check("one decode = load_image's pixels", one is not None and one[1] == theme.load_image(img) and one[0] == real_frame([f"{img}[0]"]))
    vid = d / "clip.mp4"
    subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-f", "lavfi", "-i", "testsrc=size=320x180:rate=10:duration=4", "-pix_fmt", "yuv420p",
                    "-y", str(vid)], check=True)
    fr = theme.frames_analysis(str(vid))
    c_check("frames cached", fr is not None and theme.frames_analysis(str(vid), compute=False) == fr)
    os.utime(vid, ns=(vid.stat().st_atime_ns, vid.stat().st_mtime_ns + 10**9))
    c_check("frames: changed clip = miss", theme.frames_analysis(str(vid), compute=False) is None)

    # theme-blobs: bit-identical to frame_blobs (the oracle) on synthetic frames, its float primitives on random input
    frames = []
    for name, args in (("red", ["xc:#2a4d8f", "-fill", "#d0201c", "-draw", "circle 500,150 500,162"]),
                       ("tiny", ["xc:#141c33", "-fill", "#30e070", "-draw", "rectangle 500,300 503,303", "-fill", "#e02838", "-draw", "rectangle 760,420 763,423"]),
                       ("warm", ["gradient:#8a6a55-#c79a80", "-fill", "#f04a3a", "-draw", "circle 400,250 400,258"]),
                       ("plasma", ["plasma:fractal"]), ("noise", ["xc:", "+noise", "Random"])):
        f = d / f"{name}.png"
        subprocess.run(["magick", "-size", "1280x720", *args, str(f)], check=True)
        frames.append(real_frame([f"{f}[0]"]))
    frames += [field(160, 90, BLUE, (40, 30, 8)), field(320, 180, BLUE)]
    py = [theme.blob_sums(theme.frame_blobs(f)) for f in frames]
    helper = theme.blobs_helper()
    if helper:
        c_check("theme-blobs == Python frame_blobs", same_blobs(theme.frames_blobs(frames), py), f"{sum(map(len, py))} blobs")
        import math
        import random
        rnd = random.Random(5)
        cases = [("h", [rnd.uniform(-.4, .4), rnd.uniform(-.4, .4) * rnd.choice((1, 1e-6))]) for _ in range(3000)] + \
                [("d", [rnd.uniform(-.5, 1) for _ in range(6)]) for _ in range(3000)] + \
                [("s", [rnd.uniform(-.4, .4) for _ in range(rnd.randint(1, 400))]) for _ in range(300)]
        out = subprocess.run([helper, "--math"], input="".join(f"{op} {' '.join(map(repr, v))}\n" for op, v in cases),
                             capture_output=True, text=True).stdout.split()
        want = [math.hypot(*v) if op == "h" else math.dist(v[:3], v[3:]) if op == "d" else sum(v) for op, v in cases]
        c_check("theme-blobs hypot / dist / sum exact", [float(x) for x in out] == want, f"{len(cases)} cases")
    else:
        print("skip switch theme-blobs not built (theme.py build-helper): the Python analysis is in use")
    os.environ["THEME_BLOBS"] = "0"
    theme._BLOBS.clear()
    c_check("no helper: Python fallback", theme.blobs_helper() is None and same_blobs(theme.frames_blobs(frames), py))
    broken = d / "broken-blobs"
    broken.write_text(f'#!/bin/sh\n[ "$1" = --version ] && echo {theme.BLOBS_VERSION} && exit 0\nexit 3\n')
    broken.chmod(0o755)
    os.environ["THEME_BLOBS"] = str(broken)
    theme._BLOBS.clear()
    c_check("failing helper: Python fallback", theme.blobs_helper() == str(broken) and same_blobs(theme.frames_blobs(frames[:2]), py[:2]))
    os.environ.pop("THEME_BLOBS")
    theme._BLOBS.clear()

    # hyprpaper.conf -> what each output must show (desc: / connector blocks beat the catch-all)
    conf = "wallpaper {\n    monitor =\n    path = /w/a.jpg\n    fit_mode = cover\n}\n\nwallpaper {\n    monitor = desc:Example Panel B\n" \
           "    path = /w/b.jpg\n    fit_mode = cover\n}\n\nwallpaper {\n    monitor = HDMI-A-9\n    path = /w/c.jpg\n    fit_mode = cover\n}"
    mons = [{"name": "DP-9", "key": "Example Panel A"}, {"name": "DP-8", "key": "Example Panel B"}, {"name": "HDMI-A-9", "key": "Example TV"}]
    c_check("hyprpaper targets per output", theme.hyprpaper_wanted(mons, conf) == {"DP-9": ("DP-9", "/w/a.jpg"), "DP-8": ("desc:Example Panel B", "/w/b.jpg"),
                                                                                  "HDMI-A-9": ("HDMI-A-9", "/w/c.jpg")})
    # out/wallpaper.json (the shell's wallpaper layer): the same blocks, image sizes from the header, pending = not there yet
    for fmt, (w, h) in (("png", (37, 21)), ("jpg", (64, 40)), ("webp", (50, 30))):
        f = d / f"dims.{fmt}"
        subprocess.run(["magick", "-size", f"{w}x{h}", "xc:#336699", str(f)], check=True)
        c_check(f"image_dims {fmt}", theme.image_dims(f) == (w, h), str(theme.image_dims(f)))
    real_out = theme.OUT
    try:
        theme.OUT = d / "wpout"
        theme.OUT.mkdir()
        conf2 = conf.replace("/w/a.jpg", str(d / "dims.png"))
        theme.write_wallpaper_json(conf2, {"settings": {}})
        import json as _j
        wj = _j.loads((theme.OUT / "wallpaper.json").read_text())
        c_check("wallpaper.json rules", wj["backend"] == "quickshell" and [r["monitor"] for r in wj["rules"]] == ["", "desc:Example Panel B", "HDMI-A-9"]
                and wj["rules"][0] == {"monitor": "", "path": str(d / "dims.png"), "fit": "cover", "w": 37, "h": 21}
                and wj["rules"][1].get("pending") is True, str(wj["rules"][:2]))
        theme.write_wallpaper_json(conf2, {"settings": {"wallpaper_backend": "hyprpaper"}})
        c_check("wallpaper.json backend", _j.loads((theme.OUT / "wallpaper.json").read_text())["backend"] == "hyprpaper")
    finally:
        theme.OUT = real_out
    c_check("backend default / unknown -> quickshell", theme.wallpaper_backend({}) == "quickshell"
            and theme.wallpaper_backend({"settings": {"wallpaper_backend": "x"}}) == "quickshell")
    # reloads: only apps whose files changed
    ran = []
    real = {k: getattr(theme, k) for k in ("sh", "reload_nvim", "reload_zellij", "reload_gtk", "reload_kde", "reload_icons", "refresh_nautilus")}
    try:
        theme.sh = lambda cmd, timeout=10: ran.append(cmd)
        for k in real:
            if k != "sh":
                setattr(theme, k, lambda *a, _k=k, **kw: ran.append(_k))
        theme.reload_apps({}, mode_only=True, changed=set())
        nothing = not ran
        theme.reload_apps({}, mode_only=True, changed={str(theme.OUT / "kitty.conf")})
        c_check("reload skips unchanged apps", nothing and ran == ["pkill -USR1 -x kitty"], str(ran))
    finally:
        for k, v in real.items():
            setattr(theme, k, v)

    # the pipeline in a sandbox (copy of the engine, temp HOME / runtime dir, PATH shims: nothing live is touched): two
    # clicks in a row -> the second one wins everywhere; an unreadable image -> failed, the old palette stays
    root = d / "engine"
    root.mkdir()
    for n in ("theme.py", "theme.toml", "kvantum_svg.py"):
        (root / n).write_bytes((theme.ROOT / n).read_bytes())
    for n in ("templates", "default", "mpv", "bin"):
        subprocess.run(["cp", "-r", str(theme.ROOT / n), str(root / n)], check=True)
    home, run, shims = d / "home", d / "run", d / "shims"
    for x in (home / ".config", run, shims):
        x.mkdir(parents=True)
    (home / ".config" / "theme").symlink_to(root)
    log = d / "shim.log"
    (d / "mons.json").write_text('[{"name": "DP-9", "description": "Example Panel A", "width": 1920, "height": 1080, "refreshRate": 60}]')
    hyprctl = f"""#!/bin/sh
echo "hyprctl $*" >> {log}
case "$1 $2" in
  "monitors -j") cat {d}/mons.json ;;
  "hyprpaper listactive") cat {d}/active 2>/dev/null ;;
  "hyprpaper wallpaper") p=${{3#*,}}; echo "DP-9: ${{p%%,*}}" > {d}/active ;;
esac
exit 0
"""
    (shims / "hyprctl").write_text(hyprctl)
    for n in ("pkill", "gsettings", "kwriteconfig6", "plasma-apply-colorscheme", "herdr", "nautilus", "nvim", "mpvpaper", "hyprpaper"):
        (shims / n).write_text(f'#!/bin/sh\necho "{n} $*" >> {log}\nexit 0\n')
    (shims / "pgrep").write_text("#!/bin/sh\nexit 1\n")
    for f in shims.iterdir():
        f.chmod(0o755)
    env = {"HOME": str(home), "PATH": f"{shims}:/usr/bin:/bin", "XDG_RUNTIME_DIR": str(run), "LANG": "C.UTF-8", "GSETTINGS_BACKEND": "memory",
           "THEME_ANALYZE": "0", "XDG_CACHE_HOME": str(d / "cache")}
    if helper:
        env["THEME_BLOBS"] = helper
    a, b, bad = d / "a.png", d / "b.png", d / "bad.png"
    subprocess.run(["magick", "-size", "640x360", "gradient:#401010-#e04040", str(a)], check=True)
    subprocess.run(["magick", "-size", "640x360", "gradient:#102040-#40a0e0", str(b)], check=True)
    bad.write_bytes(b"not an image")
    py = [sys.executable, "-I", str(root / "theme.py"), "apply"]

    def status():
        import json
        try:
            return json.loads((run / "theme-apply" / "status.json").read_text())
        except (OSError, ValueError):
            return {}

    def settle():
        import time
        for _ in range(600):
            if status().get("state") in ("done", "failed"):
                return status()
            time.sleep(0.1)
        return status()
    subprocess.run(py + [str(a)], env=env, check=True)
    subprocess.run(py + [str(b)], env=env, check=True)
    st = settle()
    import json
    out = root / "out"
    pal = json.loads((out / "palette.json").read_text()) if (out / "palette.json").exists() else {}
    wj = json.loads((out / "wallpaper.json").read_text()) if (out / "wallpaper.json").exists() else {}
    local = (root / "theme.local.toml").read_text() if (root / "theme.local.toml").exists() else ""
    c_check("two clicks: the latest wins", st.get("state") == "done" and st.get("gen") == 2 and pal.get("wallpaper") == str(b)
            and [r["path"] for r in wj.get("rules", [])] == [str(b)] and f'wallpaper = "{b}"' in local,
            f"{st.get('state')} gen {st.get('gen')} {Path(pal.get('wallpaper', '?')).name}")
    # default backend quickshell: the state file is all; no hyprpaper call, start or restart
    c_check("quickshell backend: no hyprpaper calls", wj.get("backend") == "quickshell" and not any(
        "hyprpaper" in l for l in log.read_text().splitlines()), [l for l in log.read_text().splitlines() if "hyprpaper" in l][:2])
    # hyprpaper backend: the old live set
    (root / "theme.local.toml").write_text(local + '\n[settings]\nwallpaper_backend = "hyprpaper"\n')
    subprocess.run(py + [str(a)], env=env, check=True)
    st = settle()
    shown = (d / "active").read_text().strip() if (d / "active").exists() else ""
    c_check("hyprpaper backend: live set", st.get("state") == "done" and shown == f"DP-9: {a}"
            and json.loads((out / "wallpaper.json").read_text())["backend"] == "hyprpaper", shown)
    subprocess.run(py + [str(b)], env=env, check=True)
    settle()
    c_check("palette from the wallpaper", 200 < hue_deg(pal.get("accent", "#000000")) < 290, pal.get("accent", ""))
    subprocess.run(py + [str(bad)], env=env, check=True)
    st = settle()
    pal2 = json.loads((out / "palette.json").read_text())
    c_check("unreadable image: failed, palette kept", st.get("state") == "failed" and pal2 == pal, st.get("stage", "")[:60])
    c_check("nothing live touched", all(l.split()[0] in ("hyprctl", "pkill", "gsettings", "kwriteconfig6", "plasma-apply-colorscheme", "herdr",
                                                          "nautilus", "nvim", "mpvpaper", "hyprpaper") for l in log.read_text().splitlines()))
    # (a worker that is still running when the temp dir goes: wait for it)
    settle()

sys.exit(1 if fails else 0)
