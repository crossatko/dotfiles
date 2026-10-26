#!/usr/bin/env python3
"""Run the extractor + palette builder against nasty synthetic wallpapers and
assert the result is always usable. `python3 -I selftest.py`"""
import importlib.util
import re
import subprocess
import sys
import tempfile
from pathlib import Path

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
sys.exit(1 if fails else 0)
