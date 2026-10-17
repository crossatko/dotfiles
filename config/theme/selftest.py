#!/usr/bin/env python3
"""Run the extractor + palette builder against nasty synthetic wallpapers and
assert the result is always usable. `python3 -I selftest.py`"""
import importlib.util
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
        bad = [k for k, ok in checks.items() if not ok]
        status = "ok  " if not bad else "FAIL"
        fails += bool(bad)
        print(f"{status} {name:26} bg {bg} fg {pal['fg']} accent {pal['accent']} (found color: {base['accent'] is not None}) {bad or ''}")
sys.exit(1 if fails else 0)
