#!/usr/bin/env python3
"""Single-source theming: wallpaper -> palette -> every app's colors.

    theme.py apply [WALLPAPER]   extract palette, render templates, reload apps
    theme.py render              re-render from current theme.toml (no extraction)
    theme.py show                print the resolved palette
    theme.py default             regenerate the tracked default theme (default/), for a committer
    theme.py seed                fill out/ from default/ when it has no real render (bin/theme-seed)

theme.toml is the tracked default settings; this machine's selection (wallpaper, local settings) lives in the
git-ignored theme.local.toml, which `apply` writes. Edit theme.toml to change anything. Wallpaper-derived values can be pinned with
[overrides]; everything else follows the wallpaper. Stdlib + ImageMagick only.
"""
import colorsys
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
# Generated per-machine theme (git-ignored). THEME_OUT_DIR (absolute, or relative to this folder) redirects it for tests (render only: no links, no app reloads).
OUT = ROOT / (os.environ.get("THEME_OUT_DIR") or "out")
DEFAULT_DIR = ROOT / "default"    # tracked default theme (neutral wallpaper + its outputs), see `theme.py default`
LOCAL_TOML = ROOT / "theme.local.toml"   # git-ignored per-machine selection, merged over theme.toml
MARKER = ".default"               # out/.default: out/ holds the seeded default (bin/theme-seed), not a real render
DEFAULT_MODE = False              # True while `theme.py default` renders into DEFAULT_DIR: home-independent output
HOME = Path.home()
MODES = ("dark", "light")
MODE_FILE = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state") / "theme" / "mode"   # the chosen mode (per machine, outside the repo)


def get_mode():
    """"dark" (default) or "light": THEME_MODE, else the state file MODE_FILE. The committed default/ is always dark."""
    if DEFAULT_MODE:
        return "dark"
    if os.environ.get("THEME_MODE") in MODES:
        return os.environ["THEME_MODE"]
    try:
        m = MODE_FILE.read_text().strip()
    except OSError:
        return "dark"
    return m if m in MODES else "dark"


def set_mode(m):
    MODE_FILE.parent.mkdir(parents=True, exist_ok=True)
    write_atomic(MODE_FILE, m + "\n")


_LOCK = []


def apply_lock():
    """Serialise the commands that write the theme (render / apply / mode / per-monitor wallpaper): a wallpaper apply
    racing a light / dark switch could otherwise finish last with the other mode's or the old wallpaper's palette.
    Waits for a running one; held until this process exits."""
    if _LOCK:
        return
    import fcntl
    MODE_FILE.parent.mkdir(parents=True, exist_ok=True)
    f = open(MODE_FILE.parent / "apply.lock", "w")
    fcntl.flock(f, fcntl.LOCK_EX)
    _LOCK.append(f)


# ---------------------------------------------------------------- color utils
def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


def rgb_to_hex(rgb):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(c))) for c in rgb)


def hls(h, l, s):
    r, g, b = colorsys.hls_to_rgb(h % 1.0, max(0, min(1, l)), max(0, min(1, s)))
    return rgb_to_hex((r * 255, g * 255, b * 255))


def mix(a, b, t):
    ar, br = hex_to_rgb(a), hex_to_rgb(b)
    return rgb_to_hex(tuple(x * (1 - t) + y * t for x, y in zip(ar, br)))


def luminance(h):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (lin(c) for c in hex_to_rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def ensure_contrast(color, bg, ratio):
    """Lighten `color` (keeping hue/saturation) until it reads on `bg`; on a light `bg` darken it instead."""
    h, l, s = to_hls(color)
    if luminance(bg) > 0.4:
        while contrast(color, bg) < ratio and l > 0.03:
            l -= 0.02
            color = hls(h, l, s)
        return color
    while contrast(color, bg) < ratio and l < 0.97:
        l += 0.02
        color = hls(h, l, s)
    return color


def to_hls(h):
    r, g, b = (c / 255 for c in hex_to_rgb(h))
    return colorsys.rgb_to_hls(r, g, b)


# ----------------------------------------------------------------- extraction
def load_pixels(path):
    """Decode any ImageMagick-readable image to a flat list of sRGB tuples.
    First frame only (gif/webp/pdf), alpha flattened onto black, CMYK/16-bit/
    grey converted, EXIF-rotated, shrunk (never enlarged) for speed."""
    try:
        raw = subprocess.run(
            ["magick", f"{path}[0]", "-auto-orient", "-background", "black", "-alpha", "remove",
             "-alpha", "off", "-colorspace", "sRGB", "-resize", "240x240>", "-depth", "8", "rgb:-"],
            check=True,
            capture_output=True,
        ).stdout
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        sys.exit(f"theme: cannot read image {path}: {getattr(e, 'stderr', b'').decode()[:200] or e}")
    px = [tuple(raw[i : i + 3]) for i in range(0, len(raw) - 2, 3)]
    if not px:
        sys.exit(f"theme: {path} decoded to zero pixels")
    return px


HUE_BINS = 36


def extract(path):
    """Return {bg, fg, accent|None}. The accent is the most *chromatic* region of
    the image, not the most common color -- a greyscale piece with one red streak
    would otherwise lose its only color to averaging. None means the image has no
    meaningful color (greyscale/near-black/near-white); the caller falls back."""
    px = load_pixels(path)
    by_l = sorted(px, key=lambda p: sum(p))
    n = len(by_l)

    def avg(ps):
        return rgb_to_hex(tuple(sum(c) / len(ps) for c in zip(*ps)))

    bg = avg(by_l[: max(1, n // 3)])
    fg = avg(by_l[-max(1, n // 4) :])

    hsv = [(colorsys.rgb_to_hsv(r / 255, g / 255, b / 255), (r, g, b)) for r, g, b in px]
    # a few stray pixels is noise (jpeg fringing), a streak is signal; scaled
    # down for tiny images so a 1x1 wallpaper can still yield a color
    floor = max(min(1.5, n * 0.05), n * 0.0001)
    accent = None
    # try strict saturation first, then relax for pastel/muted/photographic images
    for min_sat in (0.25, 0.12):
        weight = [0.0] * HUE_BINS
        members = [[] for _ in range(HUE_BINS)]
        for (h, s, v), rgb in hsv:
            if s < min_sat or v < 0.20:  # near-grey or near-black: no hue to speak of
                continue
            k = int(h * HUE_BINS) % HUE_BINS
            weight[k] += s * v
            members[k].append((s * v, rgb))
        # smooth across neighbouring bins so a hue split by a bin edge still wins
        smooth = [weight[k] * 2 + weight[k - 1] + weight[(k + 1) % HUE_BINS] for k in range(HUE_BINS)]
        best = max(range(HUE_BINS), key=lambda k: smooth[k])
        if smooth[best] / 2 >= floor:
            pool = sorted(members[best] + members[best - 1] + members[(best + 1) % HUE_BINS], reverse=True)
            pool = [rgb for _, rgb in pool[: max(8, len(pool) // 2)]]  # the most vivid half
            accent = avg(pool)
            break
    return {"bg": bg, "fg": fg, "accent": accent}


# -------------------------------------------------------------------- palette
ANSI_HUES = {"red": 0.0, "yellow": 0.12, "green": 0.33, "cyan": 0.5, "blue": 0.6, "magenta": 0.83}


def hue_dist(a, b):
    d = abs(a - b) % 1.0
    return min(d, 1.0 - d)


# the neutral ramp: values that only make sense for one mode ([overrides] pins of these are ignored in light mode)
NEUTRAL_KEYS = {"bg", "bg_alt", "surface", "surface2", "overlay", "muted", "subtle", "fg_dim", "fg",
                "black", "white", "bright_black", "bright_white"}


def build_palette(base, cfg, mode="dark"):
    """The palette for `mode`. Dark: near-black tinted bg, light fg. Light: the same wallpaper-derived hues the other
    way round (a pale tint of the image's light side for bg, a deep tint of its dark side for fg); every ramp step
    (bg_alt .. overlay, muted .. fg_dim) keeps its meaning, so templates need no per-mode colour logic."""
    light = mode == "light"
    s = cfg.get("settings", {})
    if light:
        # pale, low-chroma base from the lightest part of the image; text a deep tint of its darkest part: a soft
        # near-black (about 12.5:1), not pure black, which glares on a pale page
        lh, _, ls = to_hls(base["fg"])
        bg = hls(lh, s.get("light_bg_lightness", 0.955), min(ls, 0.30))
        dh, _, ds = to_hls(base["bg"])
        fg = hls(dh, s.get("light_fg_lightness", 0.22), min(ds, 0.30))
        fg = ensure_contrast(fg, bg, 12.5)
    else:
        # keep the wallpaper's tint but force a dark, low-chroma base
        bh, bl, bs = to_hls(base["bg"])
        bg = hls(bh, min(bl, s.get("bg_max_lightness", 0.075)), min(bs, 0.15))
        fh, fl, fs = to_hls(base["fg"])
        fg = hls(fh, max(fl, 0.78), min(fs, 0.25))
        fg = ensure_contrast(fg, bg, 9.0)

    accent = base["accent"]
    if accent is None:
        accent = fg  # no color in the image: the foreground doubles as the accent
    else:
        ah, al, as_ = to_hls(accent)
        if light:   # vivid, then only as dark as the pale bg needs (a dark image accent would turn brown / maroon)
            accent = hls(ah, max(0.40, min(al, 0.50)), max(as_, 0.65))
        else:
            accent = hls(ah, max(0.42, min(al, 0.62)), max(as_, 0.55))
        accent = ensure_contrast(accent, bg, 4.6)  # also lands in an ANSI slot
    ah, _, _ = to_hls(accent)

    p = {"bg": bg, "fg": fg, "accent": accent}
    if light:
        p["bg_alt"] = mix(bg, "#ffffff", 0.5)   # views sit lighter than the window (libadwaita light)
        p["surface"] = mix(bg, fg, 0.05)
        p["surface2"] = mix(bg, fg, 0.11)
        p["overlay"] = mix(bg, fg, 0.26)
    else:
        p["bg_alt"] = mix(bg, fg, 0.03)
        p["surface"] = mix(bg, fg, 0.07)
        p["surface2"] = mix(bg, fg, 0.13)
        p["overlay"] = mix(bg, fg, 0.28)
    p["muted"] = ensure_contrast(mix(bg, fg, 0.52), bg, 4.2 if light else 3.0)   # light: hints sit on translucent glass cards, which costs contrast
    p["subtle"] = ensure_contrast(mix(bg, fg, 0.55), bg, 4.5)  # dim but always legible: line numbers, hints
    p["fg_dim"] = mix(bg, fg, 0.75)
    p["accent_soft"] = mix(bg, accent, 0.45)

    # ANSI: fixed hues, saturation capped so they sit quietly next to the
    # artwork; whichever hue is nearest the accent snaps to it exactly.
    if light:   # darker and more saturated: readable on the pale bg (contrast >= 4.5 enforced below) without going muddy
        sat = s.get("ansi_saturation_light", 0.62)
        lightness = s.get("ansi_lightness_light", 0.40)
    else:
        sat = s.get("ansi_saturation", 0.38)
        lightness = s.get("ansi_lightness", 0.64)
    nearest = min(ANSI_HUES, key=lambda k: hue_dist(ANSI_HUES[k], ah))
    for name, h in ANSI_HUES.items():
        # snap only on a near-exact hue match, so e.g. an orange accent can't
        # silently turn the terminal's red into orange
        if name == nearest and hue_dist(h, ah) < 0.05 and to_hls(accent)[2] > 0.2:
            p[name] = accent
        else:
            p[name] = hls(h, lightness, sat)
    p["orange"] = hls((ANSI_HUES["red"] + ANSI_HUES["yellow"]) / 2, lightness, sat)
    if light:
        for name in (*ANSI_HUES, "orange"):
            p[name] = ensure_contrast(p[name], bg, 4.5)
    p["accent2"] = p["blue"] if nearest != "blue" else p["cyan"]

    step = -0.09 if light else 0.09   # bright = further from the bg
    if light:   # ANSI "black" / "white" keep their meaning: a dark and a light grey
        p["black"] = p["fg_dim"]
        p["white"] = p["surface2"]
    else:
        p["black"] = p["surface2"]
        p["white"] = p["fg_dim"]
    for name in ("black", "white", *ANSI_HUES):
        h, l, sa = to_hls(p[name])
        p["bright_" + name] = hls(h, l + step, sa)
    p["bright_black"] = p["muted"]
    p["bright_white"] = p["bg_alt"] if light else fg

    # error/warn/ok semantic aliases so templates don't hard-pick ANSI names
    p["error"], p["warn"], p["ok"], p["info"] = p["red"], p["yellow"], p["green"], p["blue"]

    for k, v in cfg.get("overrides", {}).items():
        if light and k in NEUTRAL_KEYS:   # a dark-mode bg / fg / grey pin would wreck the light ramp: [overrides_light]
            continue
        p[k] = v
    if light:   # per-mode pins: [overrides_light] in theme.toml / theme.local.toml
        for k, v in cfg.get("overrides_light", {}).items():
            p[k] = v
    return p


# ------------------------------------------------------------------ templates
TOKEN = re.compile(r"\{\{\s*([a-zA-Z0-9_]+)(?:\.(hex|bare|rgb|krgb|argb))?\s*\}\}")


def render(text, pal, extra):
    def sub(m):
        key, fmt = m.group(1), m.group(2) or "hex"
        if key in extra:
            return str(extra[key])
        if key not in pal:
            raise KeyError(f"unknown palette key {key!r}")
        v = pal[key]
        if fmt == "bare":
            return v.lstrip("#")
        if fmt == "argb":  # hyprtoolkit/hyprland style 0xAARRGGBB, opaque
            return "0xff" + v.lstrip("#").upper()
        if fmt == "rgb":
            return ", ".join(str(c) for c in hex_to_rgb(v))
        if fmt == "krgb":  # KDE color schemes: r,g,b without spaces
            return ",".join(str(c) for c in hex_to_rgb(v))
        return v

    return TOKEN.sub(sub, text)


def write_atomic(path, text):
    """Readers that watch these files (quickshell) must never see a half-write."""
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, path)


# GTK4 / libadwaita glass (templates/gtk4.css). The window glass behind a GTK window is drawn by the compositor with
# the SAME tint / darkening / saturation as the shell's glass cards (Settings > Glass, glass.json; measured: identical
# pixels for the same fill), so the CSS never repeats them: it only paints the shell's card fill (Theme.bg at
# Theme.cardFill) and theme.toml adds per-part offsets on top. Tint / darkening changes then reach running GTK apps
# live, through the compositor. libadwaita paints sidebars, views and headerbars ON TOP of the window background
# (chrome), so each layer's own alpha is what is left to reach its target: 1 - (1 - effective) / (1 - chrome).
GTK_GLASS_DEFAULTS = {"chrome": 0.0, "header": 0.05, "sidebar": 0.05, "view": 0.15, "popover": 0.5, "dialog": 0.55}
# Glass knobs kept per light / dark mode: dark reads them from [settings], light ONLY from [settings_light] (never from
# [settings]), so tweaking one mode never changes the other. Missing light keys fall back to LIGHT_GLASS_DEFAULTS.
#   card_fill       base fill of shell cards / GTK / Qt windows on a solid_glass host (Theme.qml cardFill)
#   plain_fill_min  without solid_glass: floor of the bar / card / window fill (nothing lightens a plain blur)
GLASS_KEYS = ("card_fill", "plain_fill_min", "bar_opacity", "gtk_glass", "gtk_glass_fill", "gtk_glass_chrome",
              "gtk_glass_header", "gtk_glass_sidebar", "gtk_glass_view", "gtk_glass_popover", "gtk_glass_dialog",
              "gtk_glass_control", "brave_glass_alpha")
LIGHT_GLASS_DEFAULTS = {"card_fill": 0.72, "plain_fill_min": 0.88}


def mode_cfg(cfg, mode):
    """cfg with [settings] resolved for `mode` (GLASS_KEYS from [settings] in dark, from [settings_light] in light)."""
    if mode != "light":
        return cfg
    s = {k: v for k, v in cfg.get("settings", {}).items() if k not in GLASS_KEYS}
    s.update(LIGHT_GLASS_DEFAULTS)
    s.update({k: v for k, v in cfg.get("settings_light", {}).items() if k in GLASS_KEYS})
    return {**cfg, "settings": s}
GTK_GLASS_CONTROL = 0.07   # pathbar / entries / buttons in bars: fg at this alpha, like the shell's Btn (hover x2)


def hypr_solid_glass():
    """Same test as Quickshell's Theme.glass: blur enabled and decoration:blur:variant == solid_glass (11)."""
    try:
        r = subprocess.run(["hyprctl", "-j", "--batch", "getoption decoration:blur:enabled ; getoption decoration:blur:variant"],
                           capture_output=True, text=True, timeout=3)
        en = re.search(r'"decoration:blur:enabled",\s*"(?:int|bool)":\s*(\w+)', r.stdout)
        va = re.search(r'"decoration:blur:variant",\s*"int":\s*(\d+)', r.stdout)
        return bool(en and en.group(1) in ("1", "true") and va and va.group(1) == "11")
    except (OSError, subprocess.SubprocessError):
        return False


def gtk_glass_alphas(s, glass=None, mode=None):
    clamp = lambda x: min(1.0, max(0.0, float(x)))
    if glass is None:
        glass = hypr_solid_glass()
    # Base fill (window / chrome). solid_glass host: the shell card fill (Theme.qml cardFill 0.3), the compositor glass
    # does the tint / darkening. Plain blur (stock Hyprland): the shell's card fill there is bar_opacity + 0.3 = 0.85,
    # which plus the offsets made Nautilus' file view fully opaque (0.85 + 0.15) and the rest near-opaque, so plain
    # blur uses the bar's own alpha (bar_opacity: the bar sits on the same blur). theme.toml gtk_glass_fill overrides.
    if "gtk_glass_fill" in s:
        card = clamp(s["gtk_glass_fill"])
    else:
        if glass:   # `s` is already resolved for the mode (mode_cfg): card_fill is that mode's
            card = clamp(s.get("card_fill", 0.3))
        else:   # plain_fill_min: light mode's floor (no glass tint lightens a plain blur, the pale fill has to cover it)
            card = max(clamp(s.get("bar_opacity", 0.55)), clamp(s.get("plain_fill_min", 0)))
    eff = {k: clamp(card + float(s.get(f"gtk_glass_{k}", d))) for k, d in GTK_GLASS_DEFAULTS.items()}
    on = bool(s.get("gtk_glass", True))
    if not on:
        eff = {k: 1.0 for k in eff}
    base = eff["chrome"]
    layer = lambda e: 1.0 if base >= 1 else clamp(1 - (1 - e) / (1 - base))
    a = {"window": base, "header": layer(eff["header"]), "sidebar": layer(eff["sidebar"]),
         "view": layer(eff["view"]), "popover": eff["popover"], "dialog": eff["dialog"]}
    out = {f"gtk_a_{k}": f"{v:.3f}" for k, v in a.items()}
    out["gtk_eff_header"] = f"{eff['header']:.3f}"   # single layer (Brave's frame in Wall-Glass)
    # Brave's tab strip (Wall-Glass headerbar): the effective header alpha; theme.toml brave_glass_alpha overrides.
    out["brave_frame_alpha"] = out["gtk_eff_header"]
    if on and "brave_glass_alpha" in s:
        out["brave_frame_alpha"] = f"{clamp(s['brave_glass_alpha']):.3f}"
    # Kvantum (templates/kvantum.kvconfig): background opacity reductions in %, layer alphas as Qt #AA hex
    out["kv_window_reduce"] = str(round((1 - a["window"]) * 100))
    out["kv_menu_reduce"] = str(round((1 - a["popover"]) * 100))
    out["kv_view_alpha"] = f"{round(a['view'] * 255):02x}"
    out["kv_control_alpha"] = f"{round(min(1.0, clamp(s.get('gtk_glass_control', GTK_GLASS_CONTROL))) * 255):02x}"
    ctl = clamp(s.get("gtk_glass_control", GTK_GLASS_CONTROL))
    out["gtk_a_control"], out["gtk_a_control_hover"] = f"{ctl:.3f}", f"{min(1.0, ctl * 2):.3f}"
    # GTK >= 4.22 creates an ext-background-effect object for every surface and leaves its blur region EMPTY,
    # which tells Hyprland "do not blur me"; a CSS backdrop-filter blur makes GTK send the surface box instead.
    out["gtk_backdrop"] = "blur(12px)" if on else "none"
    return out


# Outputs whose alphas depend on the RUNNING compositor (gtk_glass_alphas: solid_glass or not), so they differ per host.
# They go to out/host/ (git-ignored), not out/: committed, a render on the glass host (card fill 0.3) reached the other
# hosts with every pull and left GTK / Qt windows nearly see-through over plain blur until the next local render.
HOST_OUT = OUT / "host"
HOST_TEMPLATES = {"gtk3.css", "gtk4.css", "kvantum.kvconfig", "brave-glass.css"}


# ------------------------------------------------------- per-monitor wallpapers
# State owned by theme.py (written only here; Settings > Wallpaper & theme calls `apply --monitor` / `primary` /
# `clear`): ${XDG_STATE_HOME:-~/.local/state}/theme/wallpapers.json (THEME_WALLPAPERS_FILE overrides), host-local,
# not in the repo:  {"version": 1, "primary": "<monitor key>", "monitors": {"<monitor key>": "<image>"}}.
# The monitor key is the one the other per-monitor settings use (Appearance.monitorKey() / managed.monitor_key()):
# the description exactly as Hyprland reports it, else the connector name. The PRIMARY monitor is the theme source:
# its wallpaper is `wallpaper` in theme.toml (palette, templates, every app as before) and it never has an entry of
# its own. Every other monitor with an entry shows that image (hyprpaper only, no theme change); one without an
# entry shows the primary's. Entries of unplugged monitors are kept. No file / no entries = one wallpaper
# everywhere, exactly the old behaviour.
# VIDEO wallpapers (mpvpaper on top of hyprpaper, see "video wallpapers" below): an entry may instead be
# {"video": "<file>", "mode": "once"|"loop", "still": "<extracted frame>"}; the primary's lives in the top-level
# "primary_video" (its still is `wallpaper` in theme.toml, so palette / templates stay image-driven). `primary` unset = the connected monitor at 0,0 (the same "main display" rule
# as the launcher), else the first one.
KEY_MAX = 96


def wallpapers_file():
    env = os.environ.get("THEME_WALLPAPERS_FILE")
    if env:
        return Path(env)
    return Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state") / "theme" / "wallpapers.json"


def valid_key(k):
    return isinstance(k, str) and 0 < len(k) <= KEY_MAX and k.isascii() and k.isprintable() and '"' not in k and "\\" not in k


def norm_entry(v):
    """A state entry: an image path (str), or a video dict {video, mode, still}; None when unusable."""
    if isinstance(v, str) and v:
        return v
    if isinstance(v, dict) and isinstance(v.get("video"), str) and v["video"]:
        e = {"video": v["video"], "mode": "loop" if v.get("mode") == "loop" else "once", "still": str(v.get("still") or "")}
        if e["mode"] == "once":   # optional timing of a play-once clip: see video_plan()
            play, wind = clamp_timing(v.get("play"), v.get("wind"))
            if play is not None:   # no key = full length (also every entry written before play 0 became literal)
                e["play"], e["wind"] = play, wind
            tr = clamp_ease(v.get("ease"))
            if tr is not None:   # no key = the theme.toml default
                e["ease"] = tr
        return e
    return None


def entry_image(v):
    """The image hyprpaper / the palette use for an entry: the path itself, or a video's still (re-extracted when the
    cache was cleared)."""
    if isinstance(v, str):
        return os.path.expanduser(v)
    return str(video_still(os.path.expanduser(v["video"]), v["mode"], v.get("play"), v.get("wind", 0)) or "")


def load_wp_state():
    st = {"primary": "", "monitors": {}, "primary_video": None, "optimize": True, "optimize_speed": "background", "links": []}
    try:
        d = json.loads(wallpapers_file().read_text())
    except (OSError, ValueError):
        return st
    if isinstance(d, dict):
        if valid_key(d.get("primary")):
            st["primary"] = d["primary"]
        m = d.get("monitors")
        if isinstance(m, dict):
            st["monitors"] = {k: n for k, v in m.items() if valid_key(k) and (n := norm_entry(v))}
        st["optimize"] = d.get("optimize") is not False   # default on
        if d.get("optimize_speed") in OPT_SPEEDS:
            st["optimize_speed"] = d["optimize_speed"]
        st["links"] = norm_links(d.get("links"))
        pv = norm_entry(d.get("primary_video"))
        st["primary_video"] = pv if isinstance(pv, dict) else None
    return st


def save_wp_state(st):
    f = wallpapers_file()
    f.parent.mkdir(parents=True, exist_ok=True)
    out = {k: v for k, v in st.items() if v is not None and not (k == "links" and not v) and not (k == "optimize_speed" and v == OPT_SPEEDS[0])}   # no links / default speed = key absent (old files stay byte-compatible)
    write_atomic(f, json.dumps({"version": 1, **out}, indent=2) + "\n")


def norm_links(v):
    """Monitor links: [[keyA, keyB], ...] (edges; linked monitors form groups by chaining). Bad / duplicate pairs dropped."""
    res = []
    for p in v if isinstance(v, list) else []:
        if isinstance(p, list) and len(p) == 2 and all(valid_key(k) for k in p) and p[0] != p[1] \
                and not any(set(p) == set(q) for q in res):
            res.append([p[0], p[1]])
    return res


def link_group(st, key):
    """Every key linked to `key` (directly or through a chain), `key` first, then in the order the links name them."""
    group, todo = [key], [key]
    while todo:
        k = todo.pop(0)
        for a, b in st["links"]:
            for o in ((b,) if a == k else (a,) if b == k else ()):
                if o not in group:
                    group.append(o)
                    todo.append(o)
    return group


def connected_monitors():
    """[{name, key, x, y, w, h, hz, tf}] (w/h = physical mode, hz = refresh, tf = transform) from hyprctl, [] when Hyprland does not answer."""
    try:
        out = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=5).stdout
        ms = json.loads(out)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return []
    res = []
    for m in ms:
        name, desc = m.get("name", ""), m.get("description", "")
        key = desc if valid_key(desc) else name if valid_key(name) else ""
        if key:
            res.append({"name": name, "key": key, "x": m.get("x", 0), "y": m.get("y", 0), "w": int(m.get("width") or 0),
                        "h": int(m.get("height") or 0), "hz": float(m.get("refreshRate") or 0), "tf": int(m.get("transform") or 0)})
    return res


def primary_key(st, mons):
    if st["primary"] and (not mons or any(m["key"] == st["primary"] for m in mons)):
        return st["primary"]
    if not mons:
        return st["primary"]
    return next((m["key"] for m in mons if m["x"] == 0 and m["y"] == 0), mons[0]["key"])


def tilde(path):
    p = str(Path(path).expanduser().absolute())
    return "~" + p[len(str(HOME)):] if p.startswith(str(HOME) + "/") else p


def monitor_entries(st=None, mons=None):
    """[(selector, connector or None, absolute image)] for every non-primary entry whose image exists."""
    st = st or load_wp_state()
    if not st["monitors"]:
        return []
    mons = connected_monitors() if mons is None else mons
    prim = primary_key(st, mons)
    res = []
    for key, ent in st["monitors"].items():
        path = entry_image(ent)
        if key == prim or not path or not os.path.exists(path):
            continue
        conn = next((m["name"] for m in mons if m["key"] == key), None)
        sel = key if any(m["name"] == key for m in mons) else "desc:" + key
        res.append((sel, conn, path))
    return res


def static_blocks(cfg, extra):
    """[vars] static_blocks (theme.local.toml): this machine's own hyprpaper blocks (per-monitor wallpapers keyed by
    description / connector; the serials live only there). May use {{wallpaper_t}} / {{tv_wallpaper_t}}."""
    sb = str(cfg.get("vars", {}).get("static_blocks", "")).strip("\n")
    return "\n\n" + render(sb, {}, extra) if sb.strip() else ""


def monitor_extras():
    """Template vars for templates/hyprpaper.conf: the per-monitor blocks ('' without entries; hyprpaper 0.8 needs no preload)."""
    ents = monitor_entries()
    return {"monitor_blocks": "".join(
                f"\n\nwallpaper {{\n    monitor = {s}\n    path = {tilde(p)}\n    fit_mode = cover\n}}" for s, _, p in ents)}


def restart_hyprpaper():
    # wait for the old process to fully exit or the new one loses the race for
    # the layer surface and silently leaves the previous wallpaper up
    sh("pkill -x hyprpaper; while pgrep -x hyprpaper >/dev/null; do sleep 0.1; done; "
       "sleep 0.3; setsid hyprpaper >/dev/null 2>&1 &")
    if video_wanted():   # the new hyprpaper surface maps above the old players: restart them once it is up
        sh(f"setsid python3 -I '{ROOT / 'theme.py'}' video restart >/dev/null 2>&1 </dev/null &")


def hyprpaper_active():
    """{connector: image} from `hyprctl hyprpaper listactive` ({} when hyprpaper does not answer)."""
    try:
        out = subprocess.run(["hyprctl", "hyprpaper", "listactive"], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return {}
    return {k.strip(): v.strip() for k, _, v in (l.partition(": ") for l in out.splitlines()) if v}


def live_set_wallpaper(key, conn, path):
    """Change one output's wallpaper in the running hyprpaper, then CHECK it took (listactive); if not, restart it
    (it reads the freshly rendered out/hyprpaper.conf). The selector must be the one the config block uses:
    hyprpaper ignores `<connector>,...` for an output that a `desc:` rule matches (seen live: exit 0, nothing
    changed), so a description key goes as `desc:<key>`, a connector-name key as the connector."""
    if not conn or not path:
        return
    sel = conn if key == conn else "desc:" + key
    sh(f"hyprctl hyprpaper wallpaper '{sel},{path},cover'")
    want = os.path.realpath(path)
    for _ in range(20):   # decoding a big image takes a moment
        cur = hyprpaper_active().get(conn)
        if cur and os.path.realpath(cur) == want:
            return
        time.sleep(0.15)
    print(f"theme: hyprpaper did not switch {conn} to {Path(path).name}, restarting it", file=sys.stderr)
    restart_hyprpaper()


# ------------------------------------------------------------ video wallpapers
# mpvpaper (one process per output, on the wlr-layer-shell background layer) plays the video ABOVE hyprpaper, which
# keeps showing a still of it: the extracted LAST frame for mode "once" (the clip plays, then holds that frame:
# mpv `keep-open`, the surface keeps its last buffer; if the player ever vanishes the identical still is beneath),
# a middle frame for "loop". The still is also what the palette and hyprpaper use, so login never shows black.
# Players: one pid file per connector in $XDG_RUNTIME_DIR/theme-video/<connector>.json ({pid, video, mode}); they
# are only ever killed by that exact pid after /proc/<pid>/comm says mpvpaper (never by name). A monitor without an
# own entry follows the primary's video, like it follows the primary's image.
VIDEO_EXTS = (".mp4", ".webm", ".mkv")
MPV_OPTS = {"once": "keep-open=yes loop-file=no no-audio load-scripts=no hwdec=auto-safe panscan=1.0",
            "loop": "loop-file=inf no-audio load-scripts=no hwdec=auto-safe panscan=1.0"}


def is_video(path):
    return str(path).lower().endswith(VIDEO_EXTS)


def video_dirs(cfg):
    """video_dirs in theme.toml; unset = <xdg VIDEOS dir, else ~/Videos>/wallpapers."""
    d = cfg.get("video_dirs")
    if d is None:
        try:
            base = subprocess.run(["xdg-user-dir", "VIDEOS"], capture_output=True, text=True, timeout=3).stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            base = ""
        # xdg-user-dir answers $HOME when VIDEOS is not configured: that is "unset" too
        d = [str((Path(base) if base and Path(base) != HOME else HOME / "Videos") / "wallpapers")]
    return [os.path.expanduser(x) for x in d]


def video_cache():
    d = Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache") / "theme" / "video"
    d.mkdir(parents=True, exist_ok=True)
    return d


_PROBE = {}


def _memo(fn):
    """Per-process cache of a probe keyed by file (mtime, size) + args: the encode runner re-evaluates what is wanted
    often (a cancelled job must die within ~0.5 s) and must not re-run ffprobe each time."""
    def wrapper(path, *a):
        try:
            st = os.stat(path)
        except OSError:
            return fn(path, *a)
        k = (fn.__name__, path, st.st_mtime_ns, st.st_size) + a
        if k not in _PROBE:
            _PROBE[k] = fn(path, *a)
        return _PROBE[k]
    return wrapper


@_memo
def video_duration(path):
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                             capture_output=True, text=True, timeout=20).stdout.strip()
        return max(0.0, float(out))
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return 0.0


def _frame(src, dest, pre, post=()):
    """ffmpeg one frame of src into dest (written under a temp name, then renamed); True when dest exists."""
    tmp = dest.with_name(".tmp-" + dest.name)
    try:
        subprocess.run(["ffmpeg", "-v", "error", "-y", *pre, "-i", src, "-an", *post, "-update", "1", str(tmp)],
                       stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    except (OSError, subprocess.TimeoutExpired):
        pass
    if tmp.exists() and tmp.stat().st_size:
        os.replace(tmp, dest)
    tmp.unlink(missing_ok=True)
    return dest.exists()


def _stamp(path, tag):
    import hashlib
    st = os.stat(path)
    return f"{Path(path).stem[:40]}-{tag}-{hashlib.sha1(f'{path}|{st.st_mtime_ns}|{st.st_size}'.encode()).hexdigest()[:12]}"


# Hold point of a play-once video: where mpv stops (`end=`) and the still is taken. Videos that END in black (or
# fade out to it) would hold a black wallpaper and give a black palette, so the tail is scanned with blackdetect
# (160 px wide, ~0.1 s for a 4K file): a frame is black when 98 % of its pixels have luma < 10 % (pix_th/pic_th),
# the run must last >= 0.05 s and reach the end of the file (a black flash in the middle is not a tail). The hold
# is then HOLD_MARGIN before the black starts; a fade is cut where it drops under 10 % luma. None = no black tail,
# the clip just plays to its true last frame. Scans 5 s, then 30 s, then the whole file when the tail is all black.
HOLD_MARGIN = 0.15
HOLD_SCAN = (5.0, 30.0, 0.0)


def _black_tail(path, dur, span):
    """Start (seconds) of the black run that reaches the end, within the last `span` s (0 = all); None = none."""
    start = max(0.0, dur - span) if span else 0.0
    cmd = ["ffmpeg", "-hide_banner", "-nostats", "-an"] + (["-ss", f"{start:.3f}"] if start else []) + [
        "-i", path, "-vf", "scale=160:-2,blackdetect=d=0.05:pix_th=0.10:pic_th=0.98", "-f", "null", "-"]
    try:
        err = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=120).stderr
    except (OSError, subprocess.TimeoutExpired):
        return None
    import re
    runs = [(float(a) + start, float(b) + start) for a, b in
            re.findall(r"black_start:([\d.]+) black_end:([\d.]+)", err)]
    runs = [r for r in runs if r[1] >= dur - 0.25]
    return min(r[0] for r in runs) if runs else None


def video_hold(path):
    """Hold time for mode "once" (see above) or None; cached next to the still."""
    if not os.path.exists(path):
        return None
    f = video_cache() / (_stamp(path, "once2") + ".json")
    try:
        return json.loads(f.read_text())["hold"]
    except (OSError, ValueError, KeyError, TypeError):
        pass
    dur, hold = video_duration(path), None
    if dur > 0.5:
        for span in HOLD_SCAN:
            b = _black_tail(path, dur, span)
            if b is None:
                break
            if span == 0 or b > max(0.0, dur - span) + 0.1:   # the run began inside the window: found its start
                hold = max(0.0, b - HOLD_MARGIN)
                break
    write_atomic(f, json.dumps({"hold": hold}))
    return hold


# Timed play-once ("play for S s, then wind down over W s, then stay still"): an entry may carry play / wind
# (seconds, 0-PLAY_MAX / 0-WIND_MAX; play 0 = unset = the whole clip up to the black-tail hold). Inside mpv,
# mpv/winddown.lua holds speed 1 for `play`, then eases it with s(u) = (1 + cos(pi*u)) / 2 over `wind`; the media
# time covered by the wind is wind / 2, so the clip stops at t_stop = play + wind / 2. That time is known up front:
# it is mpv's `end=` and the time the still (hyprpaper underlay, palette) is extracted at, so the frame held on
# screen is the still. Clamped to the black-tail hold / the clip end (the wind is shortened to fit).
PLAY_MAX, WIND_MAX = 600.0, 120.0   # absurd-value caps only: the real limit is the clip (see clamp_timing)
WIND_AVG = 0.5   # mean of the wind curve (1 + cos(pi u)) / 2 over [0, 1]: the wind consumes wind * WIND_AVG s of media.
# mpv/winddown.lua and the Settings sliders (SettingsWallpaper.qml, via `video thumbs`) use the same number.
WINDDOWN_LUA = ROOT / "mpv" / "winddown.lua"
WINDDOWN_SMOOTH = True   # display-resample + interpolation during the wind only: see AGENTS.md > Wallpapers (per monitor, videos, links)
# Smoothing needs mpv's display-fps-override to equal the output's real refresh (else the wind runs at callback rate /
# override times too fast: 6x on a 360 Hz output with 60), so theme.py passes the connector's refresh as winddown-fps; it
# also costs a render per vsync, so above this rate (~7 GPU points / 5 W per 360 Hz output with a glass layer, measured)
# the wind stays a plain speed ramp. (Only the runtime fallback: the baked file needs no smoothing.)
WINDDOWN_SMOOTH_MAX_HZ = 145.0


def clamp_timing(play, wind, usable=None):
    """(play, wind) of a play-once entry. play None = FULL LENGTH (no timing: the clip up to the hold point, wind 0); a
    number is literal seconds of full-speed play, 0 = start winding down at once. `usable` = whole seconds of the
    clip (video_usable): play reaching it means full length, and the wind may only consume what is left:
    play + wind * WIND_AVG <= usable, i.e. wind <= (usable - play) / WIND_AVG."""
    def num(x, hi):
        try:
            x = float(x)
        except (TypeError, ValueError):
            return None
        return round(min(hi, max(0.0, x)), 2) if x == x else None
    play = num(play, PLAY_MAX)
    if play is None or (usable is not None and play >= usable):
        return None, 0.0
    wmax = WIND_MAX if usable is None else min(WIND_MAX, (usable - play) / WIND_AVG)
    wind = num(wind, wmax)
    return play, (wind or 0.0)


EASE_MAX = 1.0   # seconds, the longest replay ease-in / fade


def clamp_ease(ease, usable=None):
    """Seconds of an entry's replay ease-in (also the length of the fade when no frame matches): None = the theme.toml
    default (replay_ease_in); 0 = off; at most
    EASE_MAX and the usable length of the clip (`usable`, whole seconds)."""
    try:
        v = float(ease)
    except (TypeError, ValueError):
        return None
    if v != v:
        return None
    v = min(EASE_MAX, max(0.0, v))
    return round(min(v, float(usable)) if usable is not None else v, 2)


def video_limit(path):
    """Seconds of the clip that may play: up to the black-tail hold point, else the clip end (a hair short of it)."""
    hold = video_hold(path)
    return hold if hold is not None else video_duration(path) - 0.05


def video_usable(path):
    """video_limit rounded down to whole seconds: the length the Play for / Wind down sliders share."""
    return max(0, int(video_limit(path))) if os.path.exists(path) else 0


def video_plan(path, play, wind):
    """(play, wind, t_stop) effective for a timed play-once clip, or None = play the whole clip (no timing, or the
    requested play time reaches the hold point / clip end)."""
    play, wind = clamp_timing(play, wind)
    if play is None or not os.path.exists(path):
        return None
    limit = video_limit(path)
    if limit <= 0.1 or play >= limit:
        return None
    if play + wind * WIND_AVG > limit:   # not enough clip left for the whole wind: shorten it, same curve
        wind = (limit - play) / WIND_AVG
    wind = round(wind, 3) if wind >= 0.1 else 0.0
    return play, wind, max(round(play + wind * WIND_AVG, 3), 0.1)


def video_still(path, mode, play=None, wind=0):
    """Cached full-size still of a video: the hold frame ("once": the last non-black frame, or t_stop of a timed
    clip) or the middle frame ("loop"). None when ffmpeg fails."""
    if not os.path.exists(path):
        return None
    plan = video_plan(path, play, wind) if mode == "once" else None
    out = video_cache() / (_stamp(path, "once2" if mode == "once" else mode) + (f"-t{round(plan[2] * 1000)}" if plan else "") + ".png")
    if out.exists():
        return out
    if mode == "once":
        hold = plan[2] if plan else video_hold(path)
        if hold is not None:   # same timestamp mpv stops at (`end=`)
            # mpv's end= is exclusive: it holds the last frame BEFORE `hold`, so take that one
            ss = max(0.0, hold - 1.0)
            ok = _frame(path, out, ["-ss", f"{ss:.3f}"], ["-t", f"{max(hold - ss, 0.04):.3f}"])
        else:
            # decode only the tail; every frame overwrites the same file, the last one stays
            ok = _frame(path, out, ["-sseof", "-0.5"]) or _frame(path, out, [])
    else:
        ok = _frame(path, out, ["-ss", f"{video_duration(path) / 2:.2f}"], ["-frames:v", "1"]) or _frame(path, out, [], ["-frames:v", "1"])
    return out if ok else None


def video_thumb(path):
    """Small cached still (JPEG, 640 wide, middle frame) for the Settings grid."""
    if not os.path.exists(path):
        return None
    out = video_cache() / (_stamp(path, "thumb") + ".jpg")
    if out.exists():
        return out
    ok = _frame(path, out, ["-ss", f"{video_duration(path) / 2:.2f}"], ["-frames:v", "1", "-vf", "scale=640:-2", "-q:v", "4"])
    return out if ok else None


def make_entry(path, mode, play=None, wind=0, ease=None):
    """Entry for a picked file: the image path, or a video dict (extracts the still)."""
    path = str(Path(path).expanduser().absolute())
    if not is_video(path):
        return tilde(path)
    mode = "loop" if mode == "loop" else "once"
    play, wind = clamp_timing(play, wind, video_usable(path)) if mode == "once" else (None, 0.0)
    still = video_still(path, mode, play, wind)
    if not still:
        sys.exit(f"theme: ffmpeg could not extract a frame from {path}")
    ent = {"video": tilde(path), "mode": mode, "still": tilde(still)}
    if play is not None:
        ent["play"], ent["wind"] = play, wind
    tr = clamp_ease(ease, video_usable(path)) if mode == "once" else None
    if tr is not None:
        ent["ease"] = tr
    return ent


# ---- per-monitor optimized copies ("Optimize for monitor", on by default) ----
# A 4K / 60 fps wallpaper on a 1440p monitor costs decode + scaling for nothing. For every (video, monitor) pair a copy
# is transcoded once into $XDG_CACHE_HOME/theme/video/opt/: scaled to COVER the monitor's physical pixels
# (lanczos, centre-crop, so mpv needs no scaling or panscan), frame rate = the largest of OPT_FPS that is <= the
# source and divides the monitor's refresh rate (frames are only dropped, never invented or blended), H.264 through
# VA-API (CQP, closed GOP, no B-frames) on the GPU, libx264 as the fallback. Timestamps stay those of the source
# (no trim), so the hold point, t_stop and stills stay valid. Players start on the copy when it exists, else on the
# original; a background runner (one at a time, nice / ionice) encodes missing copies and tells the running players to
# `swap` (mpv/winddown.lua: loop at the wrap, once while it plays or at the next replay). Stills / palette still come
# from the original (one still serves every monitor the entry is shown on).
OPT_FPS = (25, 30, 40, 45, 50, 60)
OPT_VERSION = "o1"
OPT_QP = 20
OPT_CACHE_MB = 4096
VAAPI_DEVICES = ("/dev/dri/renderD128", "/dev/dri/renderD129")


@_memo
def video_probe(path):
    """(width, height, fps) of the first video stream, or None."""
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                              "stream=width,height,avg_frame_rate,r_frame_rate", "-of", "json", path],
                             capture_output=True, text=True, timeout=20).stdout
        s = json.loads(out)["streams"][0]
        def rate(x):
            a, _, b = x.partition("/")
            return float(a) / float(b or 1) if float(b or 1) else 0.0
        fps = rate(s.get("avg_frame_rate", "0/1")) or rate(s.get("r_frame_rate", "0/1"))
        return int(s["width"]), int(s["height"]), fps
    except (OSError, ValueError, KeyError, IndexError, subprocess.TimeoutExpired):
        return None


@_memo
def video_codec(path):
    """(codec_name, profile, bit depth) of the first video stream, or None."""
    try:
        s = json.loads(subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_name,profile,pix_fmt,bits_per_raw_sample",
                                      "-of", "json", path], capture_output=True, text=True, timeout=20).stdout)["streams"][0]
        pf = s.get("pix_fmt", "")
        depth = 10 if ("10" in pf or "12" in pf) else 8
        return s.get("codec_name", ""), s.get("profile", ""), depth
    except (OSError, ValueError, KeyError, IndexError, subprocess.TimeoutExpired):
        return None


VA_PROFILES = {   # codec -> {bit depth: VA profile names, any of which is enough}
    "h264": {8: ("VAProfileH264High", "VAProfileH264Main", "VAProfileH264ConstrainedBaseline")},
    "hevc": {8: ("VAProfileHEVCMain",), 10: ("VAProfileHEVCMain10",)},
    "av1": {8: ("VAProfileAV1Profile0",), 10: ("VAProfileAV1Profile0",)},
    "vp9": {8: ("VAProfileVP9Profile0",), 10: ("VAProfileVP9Profile2",)},
}


def hwdec_ok(path):
    """Can this machine decode the video's codec / profile in HARDWARE? See hwdec_codec_ok."""
    c = video_codec(path)
    if not c or not c[0]:
        return False
    return hwdec_codec_ok(c[0], c[2])


def hwdec_codec_ok(codec, depth=8):
    """Hardware decode of `codec` at `depth` bits here? Probed (vainfo on the VA-API node: `<profile>: VAEntrypointVLD`, or
    nvidia-smi for NVDEC), cached per codec and node; anything unknown = False (never assumed). $THEME_FORCE_NO_HWDEC = comma
    list of codec names (av1,hevc,...) that count as not decodable, `all` = nothing (tests)."""
    force = [x.strip() for x in os.environ.get("THEME_FORCE_NO_HWDEC", "").split(",") if x.strip()]
    if "all" in force or codec in force:
        return False
    profiles = VA_PROFILES.get(codec, {}).get(depth)
    if not profiles:
        return False
    dev = opt_vaapi_device()

    def run():
        if dev and shutil.which("vainfo"):
            out = subprocess.run(["vainfo", "--display", "drm", "--device", dev], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=20).stdout
            if any(re.search(re.escape(pr) + r"\s*:\s*VAEntrypointVLD", out) for pr in profiles):
                return True
        if shutil.which("nvidia-smi"):   # NVDEC: h264 / hevc / vp9 on every supported card, av1 from the RTX 30 series on (name check)
            r = subprocess.run(["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10).stdout
            if r.strip():
                if codec != "av1":
                    return True
                return any(int(m) >= 30 for m in re.findall(r"RTX\s+(?:A|PRO\s+)?(\d{2})\d{2}", r))
        return False
    return probe_cached(f"hwdec-{codec}{depth}-{dev or 'none'}", run)


def fps120(src_fps, refresh):
    """120 fps is allowed only when the source itself is 120 fps (rounded >= 119) AND the refresh is a whole multiple of 120 (within
    the usual 1.5 %: the 360 Hz panel, not the 60 Hz one). 60 fps sources never go above 60."""
    if round(src_fps) < 119 or refresh <= 0:
        return False
    r = refresh / 120
    return round(r) >= 1 and abs(r - round(r)) <= 0.015 * round(r)


def opt_fps(src_fps, refresh):
    """Target fps: the largest of OPT_FPS that is <= the source (0.5 % slack: 29.97 -> 30 is the same rate) and divides
    the refresh rate evenly (refresh / fps within 1.5 % of an integer: 59.95 Hz, 143.98 Hz). None = keep the source
    rate: nothing dividing fits (24p on 60 Hz stays 24p: a lower rate would stutter, a higher one needs invented
    frames), or the refresh is unknown."""
    if src_fps <= 0 or refresh <= 0:
        return None
    if fps120(src_fps, refresh):
        return 120
    for f in sorted(OPT_FPS, reverse=True):
        if f <= src_fps * 1.005:
            r = refresh / f
            if round(r) >= 1 and abs(r - round(r)) <= 0.015 * round(r):
                return f
    return None


def opt_plan(path, mon):
    """{w, h, fps, scale} for the monitor, or None when a copy would gain nothing (source already at most monitor
    size and at a fitting rate)."""
    if not mon or not mon.get("w") or not mon.get("h"):
        return None
    pr = video_probe(path)
    if not pr:
        return None
    sw, sh, sfps = pr
    mw, mh = (mon["h"], mon["w"]) if mon.get("tf", 0) % 2 else (mon["w"], mon["h"])   # 90 / 270 degree transforms swap
    scale = max(mw / sw, mh / sh) < 0.999   # the source is bigger than the monitor even after covering it
    fps = opt_fps(sfps, mon.get("hz", 0))
    if fps is not None and abs(fps - sfps) <= sfps * 0.005:
        fps = None   # same rate: keep the source timestamps
    w, h = (mw - mw % 2, mh - mh % 2) if scale else (sw, sh)
    cap = enc_fps_cap(w, h, fps or sfps)   # the codec's level: an H.264 4K copy cannot be 120 fps
    if cap is not None and cap < (fps or sfps) * 0.995:
        fps = cap
    if not scale and fps is None and hwdec_ok(path):
        return None
    return {"w": w, "h": h, "fps": fps, "scale": scale, "src_fps": sfps}   # (a source the GPU cannot decode gets a copy in the output codec anyway)


def opt_path(path, plan):
    import hashlib
    st = os.stat(path)
    key = f"{path}|{st.st_mtime_ns}|{st.st_size}|{plan['w']}x{plan['h']}|{plan['fps']}|{plan['scale']}|{out_codec()}|{OPT_QP_HEVC if out_codec() == 'hevc' else OPT_QP}|{OPT_VERSION}"
    return video_cache() / "opt" / f"{Path(path).stem[:40]}-{plan['w']}x{plan['h']}-{plan['fps'] or 'src'}-{hashlib.sha1(key.encode()).hexdigest()[:10]}.mp4"


def opt_cached(video, mon):
    """The monitor's optimized copy when it is already encoded (touched for the LRU), else None. Never encodes."""
    try:
        if not os.path.exists(video):
            return None
        plan = opt_plan(video, mon)
        if plan:
            dest = opt_path(video, plan)
            if dest.exists() and dest.stat().st_size:
                os.utime(dest)
                return dest
    except OSError:
        pass
    return None


def opt_vaapi_device():
    for d in [os.environ.get("THEME_VAAPI_DEVICE", "")] + list(VAAPI_DEVICES):
        if d and os.path.exists(d):
            return d
    return None


def opt_status(**kw):
    """Progress for the Settings page: $XDG_RUNTIME_DIR/theme-video/optimize.json."""
    kw.setdefault("pid", os.getpid())   # the runner's pid: a reader treats a dead pid as idle (a killed runner cannot say so itself)
    write_atomic(vp_dir() / "optimize.json", json.dumps(kw))


# Encode runner bookkeeping (video_optimize_run): the job being encoded, a cancel flag, every ffmpeg we started.
# A state change pokes the runner (SIGUSR1 -> `poked`); the encode loops then re-evaluate what is wanted and kill the
# process groups of a stale job (exact pid, /proc/<pid>/comm checked) and raise JobCancelled.
class JobCancelled(Exception):
    pass


_RUN = {"poked": False, "cancel": False, "dest": None, "procs": [], "lock": threading.Lock()}


def job_stale():
    """True once the running job's file is no longer wanted. Cheap unless the runner was poked."""
    if _RUN.pop("repri", False):
        try:
            opt_speed_refresh()
        except Exception:   # noqa: BLE001 - a failed re-prioritization must not kill a good job
            pass
    with _RUN["lock"]:
        if _RUN["cancel"]:
            return True
        if not _RUN["poked"] or _RUN["dest"] is None:
            return False
        _RUN["poked"] = False
        dest = _RUN["dest"]
    try:
        keep = dest in opt_wanted()
    except Exception:   # noqa: BLE001 - a failed re-evaluation must not kill a good job
        return False
    if not keep:
        with _RUN["lock"]:
            _RUN["cancel"] = True
    return not keep


def proc_kill(pr, hard=False):
    """Kill the process group of a child we started (new session = group of its own): SIGKILL at once when hard (a
    cancelled job's output is thrown away anyway), else SIGTERM and SIGKILL after 0.3 s. Only while the Popen is
    unreaped (so the pid is still ours) and /proc/<pid>/comm is one of our tools."""
    import signal
    for sig, wait in (((signal.SIGKILL, 1.0),) if hard else ((signal.SIGTERM, 0.3), (signal.SIGKILL, 1.0))):
        if pr.poll() is not None:
            break
        try:
            comm = Path(f"/proc/{pr.pid}/comm").read_text().strip()
        except OSError:
            break
        if not comm.startswith(PRIO_COMMS):
            return
        try:
            os.killpg(pr.pid, sig)
        except OSError:
            break
        end = time.time() + wait
        while time.time() < end and pr.poll() is None:
            time.sleep(0.005)
    try:
        pr.wait(timeout=1)
    except subprocess.TimeoutExpired:
        pass


def procs_kill(procs):
    """Hard-kill several children at once (signal all, then reap)."""
    import signal
    for pr in procs:
        try:
            if pr.poll() is None and Path(f"/proc/{pr.pid}/comm").read_text().strip().startswith(PRIO_COMMS):
                os.killpg(pr.pid, signal.SIGKILL)
        except OSError:
            pass
    for pr in procs:
        try:
            pr.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass


def job_spawn(cmd, **kw):
    kw.setdefault("stdin", subprocess.DEVNULL)
    pr = subprocess.Popen(cmd, start_new_session=True, **kw)
    with _RUN["lock"]:
        _RUN["procs"].append(pr)
    return pr


def job_reap(pr):
    with _RUN["lock"]:
        if pr in _RUN["procs"]:
            _RUN["procs"].remove(pr)


# Optimize speed (Settings > Wallpaper > Videos "Speed", `theme.py video optimize-speed background|balanced|fast`,
# wallpapers.json `optimize_speed`, absent = background). Only the COST changes, never the output (same encoders / QP /
# filters; decoder / filter thread counts and the number of parallel chunks / RIFE processes do not change the result):
#   background (default): every encode / decode / RIFE process at SCHED_IDLE (runs only on otherwise idle CPU time) + nice 19
#     + ionice idle, decoders limited to BG_DEC_THREADS threads, BG_FILTER_THREADS filter threads, a quarter of the cores as
#     parallel chunk workers, one RIFE process, one PNG decoder.
#   balanced: about BALANCED_FRAC (60 %) of the machine: decoder / filter threads, chunk workers, PNG decoders and the RIFE
#     count fast would use, each x 0.6 (at least 1, threads at least 2); SCHED_BATCH + nice 19 + ionice best-effort 7.
#     SCHED_BATCH (not IDLE) so the encode still progresses at a small guaranteed share while the desktop is busy (nice 19 =
#     weight 15 vs 1024 for a nice-0 desktop thread, and BATCH never preempts a waking interactive thread); IDLE would stall
#     it completely whenever the desktop uses the CPU, which is background's job. No cgroup CPUQuota: a quota per spawned
#     process does not add up to a job-wide cap, and a runner-wide scope would need its own unit plus `set-property` on
#     every switch; the thread / worker limits already bound it, and the priority keeps the desktop first.
#   fast: the old behaviour (nice BAKE_NICE, ffmpeg ionice best-effort 4, every core, VRAM-sized RIFE worker count).
# GPU: not throttled in any mode beyond the RIFE worker count (1 RIFE process alone keeps the GPU ~93 % busy; amdgpu has no
# userland priority for another process's Vulkan compute, and RIFE tiling would change the output).
# A switch while the runner works (SIGUSR1 poke) re-prioritizes the RUNNING processes at once (opt_prio_apply: scheduler
# policy + nice of every thread, ionice of the process group); thread / worker counts change with the next process spawned.
OPT_SPEEDS = ("background", "balanced", "fast")
BG_DEC_THREADS = 2
BG_FILTER_THREADS = 2
BALANCED_FRAC = 0.6
PRIO_COMMS = ("ffmpeg", "nice", "ionice", "chrt", "rife")


def opt_speed():
    """"background" | "balanced" | "fast": the runner's current value (refreshed on a poke), else the state file's."""
    return _RUN.get("speed") or load_wp_state()["optimize_speed"]


def ncpu():
    """Cores this process may use (cgroup / affinity aware)."""
    try:
        return len(os.sched_getaffinity(0))
    except (AttributeError, OSError):
        return os.cpu_count() or 4


def speed_scale(n_fast, bg):
    """A parallelism count for the current speed: fast = n_fast, balanced = BALANCED_FRAC of it, background = bg (all >= 1)."""
    sp = opt_speed()
    return max(1, n_fast if sp == "fast" else round(n_fast * BALANCED_FRAC) if sp == "balanced" else bg)


def speed_prio(speed=None):
    """(scheduler policy or None, nice, ionice args) of a speed."""
    sp = speed or opt_speed()
    if sp == "background":
        return getattr(os, "SCHED_IDLE", None), 19, ["-c3"]
    if sp == "balanced":
        return getattr(os, "SCHED_BATCH", None), 19, ["-c2", "-n", "7"]
    return os.SCHED_OTHER, BAKE_NICE, ["-c2", "-n", "4"]


def job_prio(ff=False, nice=None):
    """Command prefix that sets a spawned encode / decode / RIFE process's priority for the current speed (ff = an ffmpeg
    encode: fast mode also gives it ionice best-effort 4, as before)."""
    sp = opt_speed()
    io = shutil.which("ionice")
    if sp in ("background", "balanced"):
        _, nv, ia = speed_prio(sp)
        return (["chrt", "-i" if sp == "background" else "-b", "0"] if shutil.which("chrt") else []) + ["nice", "-n", str(nv)] + (["ionice", *ia] if io else [])
    return ["nice", "-n", str(BAKE_NICE if nice is None else nice)] + (["ionice", "-c2", "-n", "4"] if ff and io else [])


def bg_threads(opt="-threads", n=BG_DEC_THREADS):
    """[opt, n] (an ffmpeg thread limit placed before an input / as a global option): background n, balanced
    BALANCED_FRAC of the cores (at least 2), fast [] (ffmpeg's own automatic count)."""
    sp = opt_speed()
    if sp == "background":
        return [opt, str(n)]
    if sp == "balanced":
        return [opt, str(max(2, round(ncpu() * BALANCED_FRAC)))]
    return []


def opt_prio_apply():
    """Re-prioritize every process the runner started (and their threads, and anything else in their process groups) for
    the current speed. Lowering is always allowed; raising back (fast) needs RLIMIT_NICE >= 20 - BAKE_NICE (failures ignored)."""
    pol, nice, ia = speed_prio()
    with _RUN["lock"]:
        groups = {pr.pid for pr in _RUN["procs"] if pr.poll() is None}
    if not groups:
        return
    for d in Path("/proc").iterdir():
        if not d.name.isdigit():
            continue
        try:
            stat = (d / "stat").read_text()
            if int(stat.rsplit(")", 1)[1].split()[2]) not in groups or not (d / "comm").read_text().strip().startswith(PRIO_COMMS):
                continue
            tids = [int(t.name) for t in (d / "task").iterdir()]
        except (OSError, ValueError, IndexError):
            continue
        for tid in tids:
            try:
                if pol is not None:
                    os.sched_setscheduler(tid, pol, os.sched_param(0))
                os.setpriority(os.PRIO_PROCESS, tid, nice)
            except OSError:
                pass
    if shutil.which("ionice"):
        for g in groups:   # IOPRIO_WHO_PGRP: every thread of every process in the group
            subprocess.run(["ionice", *ia, "-P", str(g)], stdin=subprocess.DEVNULL, capture_output=True)


def opt_speed_refresh():
    """Runner side of a poke: re-read the speed; when it changed, re-prioritize the running processes."""
    new = load_wp_state()["optimize_speed"]
    if new != _RUN.get("speed"):
        _RUN["speed"] = new
        print(f"theme: optimize speed {new}", flush=True)
        opt_prio_apply()


# Output codec of the optimized copies and the bakes: HEVC Main (8-bit) when this machine both DECODES it in hardware (the
# players) and can ENCODE it (hevc_vaapi -> hevc_nvenc -> hevc_qsv -> libx265, probed), else H.264 High (the old chain).
# HEVC levels by luma sample rate: 5.1 <= 534,773,760 samples/s (4K60, 1440p120), 5.2 <= 1,069,547,520 (4K120), max
# 8,912,896 samples per frame; H.264 is always level 5.2 (2,073,600 macroblocks/s, 36,864 per frame). Every part of one file
# is encoded with the same encoder / profile / level (enc_job sets the level per job) so the stream-copy concat stays valid.
ENC_LEVEL = "5.2"   # H.264 level of every encode (max 2,073,600 macroblocks/s, 36,864 per frame): hardware decoders reject more
H264_MBS, H264_MBS_FRAME = 2073600, 36864
HEVC_LEVELS = (("5.1", 534773760), ("5.2", 1069547520))
HEVC_PS_MAX = 8912896
OPT_QP_HEVC = 16    # hevc_vaapi CQP: "visually lossless" target p5 PSNR >= 50 dB and p5 SSIM >= 0.995 vs the lanczos-scaled source and vs raw RIFE output; 16 is the highest QP meeting it (18 fails: SSIM p5 0.9926 on raycast), measured, see AGENTS.md > Wallpapers (per monitor, videos, links)
_ENC = {"level": None}


def h264_fps_cap(w, h, fps):
    """The frame rate `fps` limited so that w x h fits H.264 level 5.2 (None = the size alone does not fit)."""
    mb = ((w + 15) // 16) * ((h + 15) // 16)
    if mb > H264_MBS_FRAME:
        return None
    if mb * fps <= H264_MBS:
        return fps
    for f in (60, 50, 30, 25, 24):
        if f < fps and mb * f <= H264_MBS:
            return f
    return H264_MBS // mb


def hevc_fps_cap(w, h, fps):
    """`fps` limited so that w x h fits HEVC level 5.2 (None = the size alone does not fit)."""
    ps = w * h
    if ps > HEVC_PS_MAX:
        return None
    top = HEVC_LEVELS[-1][1]
    if ps * fps <= top:
        return fps
    for f in (60, 50, 30, 25, 24):
        if f < fps and ps * f <= top:
            return f
    return top // ps


def enc_fps_cap(w, h, fps):
    """The output codec's level cap of `fps` at w x h (see h264_fps_cap / hevc_fps_cap)."""
    return (hevc_fps_cap if out_codec() == "hevc" else h264_fps_cap)(w, h, fps)


def hevc_level(w, h, fps):
    return next((n for n, r in HEVC_LEVELS if w * h * fps <= r), HEVC_LEVELS[-1][0])


def enc_job(w, h, fps):
    """Set the level of the next encodes from the file's size and HIGHEST frame rate (one level for all its parts)."""
    _ENC["level"] = hevc_level(w, h, fps) if out_codec() == "hevc" else ENC_LEVEL


def enc_level():
    return _ENC["level"] or ("5.1" if out_codec() == "hevc" else ENC_LEVEL)


_OUT = {}


def out_codec():
    """"hevc" or "h264" for this machine (cached per process): HEVC needs a hardware HEVC Main decoder AND a working HEVC encoder.
    $THEME_OUT_CODEC = h264 | hevc forces (tests)."""
    if "c" not in _OUT:
        force = os.environ.get("THEME_OUT_CODEC", "")
        if force in ("h264", "hevc"):
            _OUT["c"] = force
        else:
            ok = hwdec_codec_ok("hevc", 8) and any(enc_probe(n, sp) for n, sp in ff_enc_specs(["scale=iw:ih"], "hevc").items())
            _OUT["c"] = "hevc" if ok else "h264"
    return _OUT["c"]


def ff_enc_specs(vf, codec=None):
    """{encoder: (pre-input args, -vf string, codec args)} of every encoder of `codec` (default: out_codec()) we know, in preference
    order: VA-API, NVENC, QuickSync, then the software one. Which of them work on this machine is enc_probe's business."""
    codec = codec or out_codec()
    dev = opt_vaapi_device()
    specs = {}
    if codec == "hevc":
        lv = enc_level() if _OUT.get("c") == "hevc" else "5.1"   # (out_codec() itself probes these specs: no recursion)
        tag = ["-tag:v", "hvc1"]
        if dev:
            specs["hevc_vaapi"] = (["-init_hw_device", f"vaapi=va:{dev}", "-filter_hw_device", "va"], ",".join(vf + ["format=nv12", "hwupload"]),
                                   ["-c:v", "hevc_vaapi", "-qp", str(OPT_QP_HEVC), "-profile:v", "main", "-tier", "main", "-level", lv, "-bf", "0", "-g", "120", "-flags", "+cgop",
                                    "-bsf:v", "extract_extradata", *tag])   # hvc1 + the driver's default header (init_qp 26) = undecodable at other QPs (slice_qp out of range); the bsf puts the real parameter sets into hvcC
        specs["hevc_nvenc"] = ([], ",".join(vf + ["format=yuv420p"]), ["-c:v", "hevc_nvenc", "-preset", "p5", "-rc", "constqp", "-qp", str(OPT_QP_HEVC), "-profile:v", "main",
                                                                       "-level", lv, "-bf", "0", "-g", "120", *tag])
        specs["hevc_qsv"] = (["-init_hw_device", "qsv=hw", "-filter_hw_device", "hw"], ",".join(vf + ["format=nv12", "hwupload=extra_hw_frames=64"]),
                             ["-c:v", "hevc_qsv", "-global_quality", str(OPT_QP_HEVC), "-profile:v", "main", "-bf", "0", "-g", "120", *tag])
        specs["libx265"] = ([], ",".join(vf + ["format=yuv420p"]), ["-c:v", "libx265", "-preset", "fast", "-crf", "14", "-profile:v", "main",
                                                                    "-x265-params", f"level-idc={lv}:keyint=120:min-keyint=120:bframes=0:log-level=error", *tag])
        return specs
    lv = ["-level", ENC_LEVEL]
    if dev:
        specs["h264_vaapi"] = (["-init_hw_device", f"vaapi=va:{dev}", "-filter_hw_device", "va"], ",".join(vf + ["format=nv12", "hwupload"]),
                               ["-c:v", "h264_vaapi", "-qp", str(OPT_QP), "-profile:v", "high", "-bf", "0", "-g", "120", "-flags", "+cgop", *lv])
    specs["h264_nvenc"] = ([], ",".join(vf + ["format=yuv420p"]), ["-c:v", "h264_nvenc", "-preset", "p5", "-rc", "constqp", "-qp", str(OPT_QP), "-profile:v", "high", "-bf", "0", "-g", "120", *lv])
    specs["h264_qsv"] = (["-init_hw_device", "qsv=hw", "-filter_hw_device", "hw"], ",".join(vf + ["format=nv12", "hwupload=extra_hw_frames=64"]),
                         ["-c:v", "h264_qsv", "-global_quality", str(OPT_QP), "-profile:v", "high", "-bf", "0", "-g", "120", *lv])
    specs["libx264"] = ([], ",".join(vf + ["format=yuv420p"]), ["-c:v", "libx264", "-preset", "slow", "-crf", "17", "-g", "120", "-bf", "0", "-threads", "4", *lv])
    return specs


_PROBE_MEM = {}


def probe_cached(key, fn):
    """yes / no probe result cached in memory and as $XDG_RUNTIME_DIR/theme-video/probe-<key> (delete the file to probe again)."""
    if key in _PROBE_MEM:
        return _PROBE_MEM[key]
    f = vp_dir() / ("probe-" + re.sub(r"[^\w.-]", "_", key))
    try:
        v = f.read_text().strip()
    except OSError:
        v = ""
    if v not in ("yes", "no"):
        try:
            v = "yes" if fn() else "no"
        except Exception:   # noqa: BLE001 - a failing probe = unsupported
            v = "no"
        try:
            write_atomic(f, v)
        except OSError:
            pass
    _PROBE_MEM[key] = v == "yes"
    return _PROBE_MEM[key]


def enc_probe(name, spec):
    """Does ffmpeg encode with `name` on this machine? One tiny test encode (720p, 3 frames) of the real argument set, cached per
    encoder and VA-API node. libx264 is always assumed to work."""
    if name == "libx264":
        return True
    def run():
        pre, vfs, codec = spec
        r = subprocess.run(["ffmpeg", "-hide_banner", "-v", "error", *pre, "-f", "lavfi", "-i", "testsrc2=s=1280x720:r=30:d=0.2", "-vf", vfs, *codec,
                            "-frames:v", "3", "-f", "null", "-"], stdin=subprocess.DEVNULL, capture_output=True, timeout=60)
        return r.returncode == 0
    return probe_cached(f"enc-{name}-{opt_vaapi_device() or 'none'}", run)


def ff_tries(vf):
    """[(pre-input args, -vf string, codec args)] to try in order: the working hardware encoders of the output codec (VA-API,
    NVENC, QuickSync, probed once per machine), then the software one (libx265 / libx264, also the runtime fallback when a
    hardware encoder exits at startup). $THEME_FORCE_ENCODER = one encoder name (tests)."""
    specs = ff_enc_specs(vf)
    soft = "libx265" if "libx265" in specs else "libx264"
    force = os.environ.get("THEME_FORCE_ENCODER", "")
    if force in specs:
        return [specs[force]] + ([specs[soft]] if force != soft else [])
    probe = ff_enc_specs(["scale=iw:ih"])
    return [sp for n, sp in specs.items() if n == "libx264" or enc_probe(n, probe[n])]


def ff_encode(in_args, vf, dest, total, label, pct=(0, 99), out_args=(), cfr=True, prog=None, nice=None, fc=None):
    """Run ffmpeg on `in_args` (everything up to and including the -i's) with the filters `vf` (list) into dest as
    H.264 (VA-API, libx264 fallback). Progress: prog(fraction of `total` s) or optimize.json mapped into pct. True on
    success; raises JobCancelled (partial output deleted) when the runner's job went stale."""
    import select
    tries = ff_tries(vf)
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_name(".tmp-" + dest.name)
    if prog is None:
        def prog(f):
            opt_status(state="encoding", label=label, pct=min(pct[1], round(pct[0] + f * (pct[1] - pct[0]))))
    for pre, vfs, codec in tries:
        # fc = a filter_complex up to its single output (the hwupload / format tail is appended); else a plain -vf chain
        graph = ["-filter_complex", f"{fc},{vfs}"] if fc else ["-map", "0:v:0", "-vf", vfs]
        cmd = job_prio(ff=True, nice=nice) + [
            "ffmpeg", "-hide_banner", "-v", "error", "-nostats", "-progress", "pipe:1", "-y", *bg_threads("-filter_threads", BG_FILTER_THREADS), *(bg_threads("-filter_complex_threads", BG_FILTER_THREADS) if fc else []), *pre, *bg_threads(), *in_args, *graph, "-an", *([] if cfr else ["-fps_mode", "passthrough"]), *out_args, *codec, "-video_track_timescale", "90000",
            "-movflags", "+faststart", "-f", "mp4", str(tmp)]   # one timescale for every part: the stream-copy concat mangles mixed ones
        errf = tempfile.TemporaryFile("w+")
        try:
            pr = job_spawn(cmd, stdout=subprocess.PIPE, stderr=errf, text=True)
        except OSError:
            continue
        try:
            while True:
                if job_stale():
                    proc_kill(pr, hard=True)
                    tmp.unlink(missing_ok=True)
                    raise JobCancelled()
                if select.select([pr.stdout], [], [], 0.1)[0]:
                    line = pr.stdout.readline()
                    if not line:
                        break
                    if line.startswith("out_time_us="):
                        try:
                            prog(min(1.0, max(0.0, int(line.split("=")[1]) / 1e6 / (total or 1.0))))
                        except ValueError:
                            pass
                elif pr.poll() is not None:
                    break
            pr.wait()
        finally:
            job_reap(pr)
        if pr.returncode == 0 and tmp.exists() and tmp.stat().st_size:
            os.replace(tmp, dest)
            return True
        errf.seek(0)
        print(f"theme: ffmpeg failed ({codec[1]}): {errf.read()[-400:].strip()}", flush=True)
        tmp.unlink(missing_ok=True)
    return False


def opt_encode(src, plan, dest, label):
    """Transcode src -> dest for `plan`; progress goes to optimize.json. True on success."""
    vf = []
    if plan["scale"]:
        vf += [f"scale={plan['w']}:{plan['h']}:flags=lanczos:force_original_aspect_ratio=increase", f"crop={plan['w']}:{plan['h']}"]
    if plan["fps"]:
        vf.append(f"fps={plan['fps']}")
    enc_job(plan["w"], plan["h"], plan["fps"] or plan.get("src_fps") or 60)
    return ff_encode(["-i", src], vf, dest, video_duration(src) or 1.0, label, cfr=bool(plan["fps"]))


# ---- baked wind-down (play-once clips with a wind) ----
# The runtime wind (mpv `speed` ramp, mpv/winddown.lua) steps through SOURCE frames, so at 0.3x a 25-60 fps clip shows
# 7-18 distinct frames per second and looks choppy; above WINDDOWN_SMOOTH_MAX_HZ runtime interpolation is too costly.
# So the wind is baked ahead of time into the monitor's copy: `play part` (source frames before `play`, source
# timestamps, the optimized scale / fps) + `wind part` (the source range [play, t_stop] retimed along the wind curve to
# the wall-clock wind, at a constant BAKE fps F, in-between frames synthesized by motion interpolation). mpv then plays
# the file at speed 1 (plain decode, no script timer, no `end=`; keep-open holds the last frame = the still).
# Retiming: wind curve speed s(x) = (1 + cos(pi x)) / 2, x = w / W, media offset m(w) = play + (last - play) * 2 mu(x),
# mu(x) = x / 2 + sin(pi x) / (2 pi) (mu(1) = 1/2). `last` = the source frame before t_stop (what mpv's end= held and
# the still shows), so the file's final frame is exactly the still. W is rounded up to a whole number of output frames.
# Interpolators (BAKE_INTERP / $THEME_BAKE_INTERP): "minterpolate" (ffmpeg mci/aobmc), "rife" (rife-ncnn-vulkan, used by
# "auto" when the binary exists), "blend" (ffmpeg blend, cheap). Source frames are fed with their timestamps WARPED onto
# the wall clock (a piecewise-linear setpts), so minterpolate's fps=F grid lands on the wanted fractional source times.
BAKE_VERSION = "b6"
BAKE_SEGS = 64          # linear pieces of the warp (speed is constant inside one)
BAKE_FPS_MAX = 60       # F = largest of OPT_FPS <= this that divides the refresh (30 when none / unknown)
BAKE = os.environ.get("THEME_BAKE") != "0"   # bake the wind into the monitor's copy (needs "Optimize for monitor" on); THEME_BAKE=0 = runtime wind only (tests)
BAKE_CHUNKS = 16        # wind part pieces (interpolated by up to cores / 2 parallel ffmpegs when the machine is idle)
BAKE_CTX = 0            # source frames of context before each chunk (0 = the chunk's first frame has no predecessor)
BAKE_NICE = 5           # nice of every encode / RIFE process: full parallelism, the desktop stays responsive (no throttling: bakes are never run while gaming)
RIFE_ARGS = ["-j", "2:1:2"]   # extra rife-ncnn-vulkan arguments (thread counts load:proc:save): ONE proc thread per process, every proc thread holds ~1.1 GB of VRAM at 1440p
RIFE_GPU = 0            # rife-ncnn-vulkan -g: device 0 is the RX 9070 XT here (`rife-ncnn-vulkan -l`; 1 = the iGPU)
RIFE_OOM_TEST = int(os.environ.get("THEME_BAKE_RIFE_OOM_ABOVE", "0") or 0)   # tests: a RIFE process started while more than N may run fails
RIFE_WORKERS = 4        # long-lived rife processes at most (they share one GPU; ~1.2 GB VRAM each at 1440p with ONE proc thread; the free VRAM decides, see rife_worker_count). Knee measured on whole bakes (raycast 4K120 AV1 -> 1440p60, 16 bursts, RX 9070 XT, -j 2:1:2): 1 worker 114.8 s, 2 106.0 s, 3 98.4 s, 4 95.0 s, 6 91.3 s; 4 workers x 2:4:4 (13.7 GB) thrash VRAM: 290.8 s
BAKE_INTERP = "auto"    # auto = RIFE when installed (measured better than minterpolate: AGENTS.md > Wallpapers (per monitor, videos, links)), else minterpolate
BAKE_MI = {"minterpolate": "mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1", "blend": "mi_mode=blend", "dup": "mi_mode=dup"}   # dup = plain frame stepping (what the runtime speed ramp shows; tests only)


def rife_bin():
    return shutil.which("rife-ncnn-vulkan")


RIFE_DIR = "/usr/share/rife-ncnn-vulkan"
RIFE_MODELS = ("rife-v4.14", "rife-v4.25", "rife-v4.6")   # preference; v4.x models take arbitrary time steps (-s)


def rife_pick():
    """(name, dir) of the RIFE model to use, or None. $THEME_RIFE_MODEL = a model name under RIFE_DIR or a directory."""
    want = os.environ.get("THEME_RIFE_MODEL", "")
    for c in ([want] if want else []) + list(RIFE_MODELS):
        d = c if os.path.isabs(c) else f"{RIFE_DIR}/{c}"
        if os.path.isdir(d):
            return Path(d).name, d
    return None


def bake_interp():
    """Interpolator of new bakes: "rife:<model>" when rife-ncnn-vulkan and a model exist (auto / rife), else minterpolate."""
    want = os.environ.get("THEME_BAKE_INTERP") or BAKE_INTERP
    if want in ("auto", "rife"):
        pick = rife_pick() if rife_bin() else None
        return f"rife:{pick[0]}" if pick else "minterpolate"
    return want if want in BAKE_MI else "minterpolate"


@_memo
def bake_last_pts(path, t_stop):
    """pts of the last source frame before t_stop (what mpv's exclusive end= holds), or None."""
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-read_intervals", f"{max(0.0, t_stop - 1.0):.3f}%{t_stop + 0.2:.3f}",
                              "-show_entries", "packet=pts_time", "-of", "csv=p=0", path], capture_output=True, text=True, timeout=30).stdout   # packets: no decoding
        ts = [float(x.strip().strip(",")) for x in out.split() if x.strip().strip(",")]
        ts = [t for t in ts if t < t_stop - 1e-6]
        return max(ts) if ts else None
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None


BAKE_EASE = 0.5        # seconds, theme.toml replay_ease_in: every replay burst starts from rest and reaches speed 1 in this time (0 = at once)


def bake_ease_default():
    """theme.toml replay_ease_in (seconds), the ease-in of entries without an own `ease`."""
    try:
        v = clamp_ease(load_cfg().get("replay_ease_in", BAKE_EASE))
    except (OSError, tomllib.TOMLDecodeError):
        v = None
    return BAKE_EASE if v is None else v


def bake_ease_s(ease=None):
    e = clamp_ease(ease)
    return bake_ease_default() if e is None else e


def bake_plan_base(video, mon, play, wind, ease=None):
    """The plan dict (geometry, fps, timing, interpolator) of a baked once file, or None when the probes fail."""
    import math
    vp = video_plan(video, play, wind)
    pr = video_probe(video)
    if not pr or pr[2] <= 0:
        return None
    hold = video_hold(video)
    clip_end = hold if hold is not None else video_duration(video) + 1.0   # the usable clip: up to the black-tail hold / its end
    if vp:
        pl, wd, ts = vp
    else:   # full length
        pl, wd, ts = None, 0.0, clip_end
    p = opt_plan(video, mon)
    last = bake_last_pts(video, ts)
    last_clip = bake_last_pts(video, clip_end)
    if last is None or last_clip is None or (wd > 0 and last <= pl):
        return None
    hz = (mon or {}).get("hz", 0)
    F = 120 if fps120(pr[2], hz) else (opt_fps(BAKE_FPS_MAX, hz) if hz > 0 else None) or 30   # 120 only for a 120 fps source on a 120 n Hz output
    w_out, h_out = (p["w"], p["h"]) if p else (pr[0] - pr[0] % 2, pr[1] - pr[1] % 2)
    cap = enc_fps_cap(w_out, h_out, F)
    f_cap = cap is not None and cap < F
    if f_cap:
        F = cap   # H.264 level 5.2 limit (max macroblocks per second): e.g. 3840x2160 cannot be 120 fps
    return {"w": p["w"] if p else pr[0] - pr[0] % 2, "h": p["h"] if p else pr[1] - pr[1] % 2, "scale": bool(p and p["scale"]),
            "fps": p["fps"] if p else None, "F": F, "f_cap": f_cap, "play": pl if wd > 0 else ts, "wind": wd, "t_stop": ts, "last": last, "last_clip": last_clip, "sfps": pr[2],
            "N": max(2, math.ceil(wd * F - 1e-9)) if wd > 0 else 0, "ease": bake_ease_s(ease), "interp": bake_interp()}


def bake_plan(video, mon, play, wind, ease=None):
    """Plan of the baked once file for this monitor: [first play: F0 ... play ... wind ... H][replay burst 0][burst 1] ...
    (bake_bursts). None when the probes fail."""
    return bake_plan_base(video, mon, play, wind, ease)


def bake_path(path, bp):
    st = os.stat(path)
    key = (f"{path}|{st.st_mtime_ns}|{st.st_size}|{bp['w']}x{bp['h']}|{bp['fps']}|{bp['scale']}|{bp['F']}|{bp['play']}|{bp['wind']}|"
           f"{bp['t_stop']}|{bp['last']}|{bp['interp']}|{bp['ease']}|{BURST_VERSION}|{BURST_MIN}|{KMAX}|{KMAX_MIN}|{BURST_RIFE_BUDGET}|{RIFE_G}|{RIFE_NEAREST}|{CUT_ABS}|{CUT_RATIO}|{LOOP_WRAP_RATIO}|{LOOP_WRAP_ABS}|{BAKE_SEGS}|{BAKE_MI.get(bp['interp'], '')}|{out_codec()}|{OPT_QP_HEVC if out_codec() == 'hevc' else OPT_QP}|{BAKE_VERSION}")
    return video_cache() / "opt" / f"{Path(path).stem[:40]}-{bp['w']}x{bp['h']}-bake-p{bp['play']:g}w{bp['wind']:g}-{hash_hex(key)}.mp4"


def hash_hex(key):
    import hashlib
    return hashlib.sha1(key.encode()).hexdigest()[:10]


def bursts_arg(side):
    """winddown-bursts / swap argument: "t0/t1/.../tK" = the start of every replay burst, then the end of the file."""
    b = side.get("bursts") or []
    return "/".join([f"{x['start']:.4f}" for x in b] + [f"{b[-1]['end']:.4f}"]) if b else ""


def bake_side(dest):
    """Sidecar of a baked file: {t2 (where burst 0 starts = the end of the first play), bursts [{start, end, i_s, n, fade}], cycle_from,
    d, text, loop, tag}."""
    try:
        return json.loads(dest.with_suffix(".json").read_text())
    except (OSError, ValueError):
        return {}


def bake_cached(video, mon, play, wind, ease=None):
    """(file, plan) of the baked once file when it is already encoded (touched for the LRU), else None. Never encodes.
    The plan carries `t2` (start of the replay segment) from the sidecar."""
    try:
        bp = bake_plan(video, mon, play, wind, ease) if os.path.exists(video) else None
        if bp:
            dest = bake_path(video, bp)
            if dest.exists() and dest.stat().st_size:
                os.utime(dest)
                side = bake_side(dest)
                return dest, dict(bp, t2=float(side.get("t2", 0.0)), side=side)
    except OSError:
        pass
    return None


def bake_geometry(bp):
    return ([f"scale={bp['w']}:{bp['h']}:flags=lanczos:force_original_aspect_ratio=increase", f"crop={bp['w']}:{bp['h']}"] if bp["scale"] else [])


def bake_breaks(bp):
    """Breakpoints [(media s, wall s since the segment start)] of the retiming curve (BAKE_SEGS linear pieces): the wind
    s(x) = (1 + cos(pi x)) / 2 from `play` to `last`, or (bp["curve"] == "in", the replay's ease-in) the mirrored
    (1 - cos(pi x)) / 2 from rest to speed 1. Both consume half of their wall time in media."""
    import math
    wp = bp["N"] / bp["F"]
    pts = []
    for i in range(BAKE_SEGS + 1):
        x = i / BAKE_SEGS
        mu = x / 2 + (-1 if bp.get("curve") == "in" else 1) * math.sin(math.pi * x) / (2 * math.pi)
        pts.append((bp["play"] + (bp["last"] - bp["play"]) * 2 * mu, x * wp))
    return pts


def bake_w_of_m(pts, m):
    """Wall time of media time m on the piecewise-linear warp (speed 1 before the wind and after the still)."""
    if m <= pts[0][0]:
        return pts[0][1] + (m - pts[0][0])
    if m >= pts[-1][0]:
        return pts[-1][1] + (m - pts[-1][0])
    for (m0, w0), (m1, w1) in zip(pts, pts[1:]):
        if m <= m1:
            return w0 + (w1 - w0) * (m - m0) / (m1 - m0) if m1 > m0 else w0
    return pts[-1][1]


def bake_m_of_w(pts, w):
    for (m0, w0), (m1, w1) in zip(pts, pts[1:]):
        if w <= w1:
            return m0 + (m1 - m0) * (w - w0) / (w1 - w0) if w1 > w0 else m0
    return pts[-1][0]


def bake_chunks(bp, n):
    """Split the wind part into <= n chunks of output frames [k_a, k_b), k = 0..N, each starting on a source frame
    boundary (so no interpolation is wasted on context): [(k_a, k_b, first source index, last source index)]."""
    import math
    pts, sfps, F, N = bake_breaks(bp), bp["sfps"], bp["F"], bp["N"]
    last_i = round(bp["last"] * sfps)
    idx = [min(int(math.floor(bake_m_of_w(pts, k / F) * sfps + 1e-6)), last_i) for k in range(N + 1)]
    starts = [0]
    for c in range(1, max(1, n)):
        k = round(c * (N + 1) / n)
        while k <= N and idx[k] == idx[k - 1]:
            k += 1
        if k <= N and k > starts[-1]:
            starts.append(k)
    while len(starts) > 1 and idx[starts[-1]] == last_i:
        starts.pop()   # the still's own pair stays in the previous chunk (a chunk of the clone pair alone emits nothing)
    k_end = bp.get("k_end", N + 1)   # an ease-in stops one frame short of its last (that frame belongs to what follows)
    starts = [k for k in starts if k < k_end]
    ends = starts[1:] + [k_end]
    return [(a, b, idx[a], min(idx[b - 1] + 1, last_i)) for a, b in zip(starts, ends)]


def bake_chunk_filters(bp, ch):
    """(input args, filters, total seconds) for one chunk. The chunk's source frames get timestamps WARPED onto the wall
    clock of the wind, minus a grid-aligned base, so minterpolate's uniform fps=F grid (anchored at its first input
    pts, 0) lands on the global output frames: a clone of the first frame is prepended at pts 0 (the real first frame
    sits 1-2 grid steps later), three clones are appended (minterpolate only emits up to the third-last input frame; the third keeps a frame that lands on the last real pts from being lost to timestamp rounding)."""
    import math
    k_a, k_b, i_s, i_e = ch
    F, sfps = bp["F"], bp["sfps"]
    pts = bake_breaks(bp)
    i_s = max(0, i_s - BAKE_CTX)   # context frames before the chunk (their interpolated frames are discarded)
    a0 = i_s / sfps
    c_idx = math.floor(bake_w_of_m(pts, a0) * F - 1e-6) - 1
    off = 0.001 if a0 > 0 else 0.0   # -ss lands a hair before a0 so the frame AT a0 is not dropped
    play, m_last = bp["play"], pts[-1][0]
    terms = [f"min(ld(0)-{play:.9f},0)", f"max(0,ld(0)-{m_last:.9f})"]
    for (m0, w0), (m1, w1) in zip(pts, pts[1:]):
        if m1 - m0 > 1e-9:
            terms.append(f"{(w1 - w0) / (m1 - m0):.9f}*clip(ld(0)-{m0:.9f},0,{m1 - m0:.9f})")
    expr = f"st(0,T-{1 / sfps + off - a0:.9f});" + "+".join(terms) + f"-{c_idx / F:.9f}"
    vf = bake_geometry(bp) + ["format=yuv420p", "tpad=start=1:start_mode=clone:stop=3:stop_mode=clone", f"setpts='if(eq(N,0),0,{expr})/TB'",
                              f"minterpolate=fps={F}:{BAKE_MI[bp['interp']]}",
                              f"select='between(n,{k_a - c_idx},{k_b - c_idx - 1})'", "setpts=PTS-STARTPTS"]   # by frame index: trim's end counts frame durations
    ins = (["-ss", f"{a0 - off:.6f}"] if a0 > 0 else []) + ["-t", f"{(i_e - i_s) / sfps + off + 0.5 / sfps:.6f}", "-i", bp["video"]]
    return ins, vf, (k_b - k_a) / F


# ---- adaptive load: how many chunks are interpolated at once
def bake_workers(own_pids=()):
    """(parallel chunk workers, nice): every core the process may use (cgroup / affinity aware) at BAKE_NICE; no throttling by load
    or by a running game (bakes are not run while gaming). $THEME_BAKE_LOAD = <n workers> forces the count (tests)."""
    force = os.environ.get("THEME_BAKE_LOAD", "")
    if force.isdigit():
        return max(1, int(force)), BAKE_NICE
    n = ncpu()
    return speed_scale(n, n // 4), BAKE_NICE   # (re-evaluated every second: a speed switch changes the count of the chunks started next)


def mem_available():
    """MemAvailable in bytes (0 when unknown)."""
    try:
        for ln in open("/proc/meminfo"):
            if ln.startswith("MemAvailable:"):
                return int(ln.split()[1]) * 1024
    except (OSError, ValueError):
        pass
    return 0


def ram_cleanup():
    """Remove this process's /dev/shm work directory (a cancelled / killed runner must not leave its PNGs in RAM)."""
    shutil.rmtree(Path("/dev/shm") / f"theme-video-{os.getuid()}" / str(os.getpid()), ignore_errors=True)


def bake_ram_dir(need):
    """A scratch directory for roughly `need` bytes of PNGs: /dev/shm (RAM) when `need` is at most 40 % of MemAvailable and fits,
    else None (the caller uses the disk). Stale directories of dead processes are removed on the way."""
    base = Path("/dev/shm") / f"theme-video-{os.getuid()}"
    try:
        base.mkdir(parents=True, exist_ok=True)
        for d in base.iterdir():
            try:
                if d.name.isdigit() and not Path(f"/proc/{d.name}").exists():
                    shutil.rmtree(d, ignore_errors=True)
            except OSError:
                pass
        free = shutil.disk_usage(base).free
        if need > 0.4 * mem_available() or need > 0.8 * free:
            return None
        d = base / str(os.getpid())
        d.mkdir(exist_ok=True)
        return d
    except OSError:
        return None


_RIFE_DEV = {}


def rife_devices():
    """{index: name} from `rife-ncnn-vulkan -l` (cached)."""
    if not _RIFE_DEV and rife_bin():
        r = subprocess.run([rife_bin(), "-l"], stdin=subprocess.DEVNULL, capture_output=True, text=True)
        for m in re.finditer(r"^\[(\d+) (.+?)\]\s+(?:queue|bug|fp16|subgroup)", r.stdout + "\n" + r.stderr, re.M):
            _RIFE_DEV.setdefault(int(m.group(1)), m.group(2))
        _RIFE_DEV.setdefault(-1, "")
    return _RIFE_DEV


def gpu_vram():
    """(total, free) VRAM in bytes of the GPU RIFE uses (device RIFE_GPU), or None when it is not a known discrete GPU.
    amdgpu: sysfs mem_info_vram_* of the card with the most VRAM (the iGPU has little), nvidia: nvidia-smi, anything else
    (intel / unknown / cpu) = None (conservative: one worker). $THEME_BAKE_VRAM_GB (total) and $THEME_BAKE_VRAM_FREE_GB override
    the numbers (tests: simulate an 8 GB card)."""
    GB = 1 << 30
    name = rife_devices().get(RIFE_GPU, "")
    tot = free = None
    if os.environ.get("THEME_BAKE_VRAM_GB"):
        try:
            tot = float(os.environ["THEME_BAKE_VRAM_GB"]) * GB
            free = float(os.environ.get("THEME_BAKE_VRAM_FREE_GB", tot / GB)) * GB
            return tot, free
        except ValueError:
            pass
    low = name.lower()
    try:
        if "nvidia" in low:
            r = subprocess.run(["nvidia-smi", "--query-gpu=memory.total,memory.used", "--format=csv,noheader,nounits"], stdin=subprocess.DEVNULL,
                               capture_output=True, text=True, timeout=5)
            rows = [x.split(",") for x in r.stdout.strip().splitlines() if "," in x]
            if rows:
                a, u = max(((float(x[0]), float(x[1])) for x in rows), key=lambda v: v[0])
                return a * (1 << 20), (a - u) * (1 << 20)
        elif "amd" in low or "radeon" in low:
            best = None
            for d in Path("/sys/class/drm").glob("card?/device"):
                try:
                    a, u = int((d / "mem_info_vram_total").read_text()), int((d / "mem_info_vram_used").read_text())
                except (OSError, ValueError):
                    continue
                if best is None or a > best[0]:
                    best = (a, a - u)
            return best
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    return None


def rife_worker_count(bp):
    """(workers, text): long-lived RIFE processes to run at once = floor((free VRAM - margin) / estimate), 1..RIFE_WORKERS. Estimate =
    1.3 GB per process at 2560x1440 (one proc thread, RIFE_ARGS: measured 1.16 GB for v4.14; every further proc thread adds as much),
    scaled by the pixel count; margin = max(1.5 GB, 10 % of the VRAM). A process that fails anyway (out of memory) halves the count.
    $THEME_RIFE_WORKERS = n forces exactly n (manual testing).
    No known discrete GPU or less than 3 GB of VRAM = 1."""
    forced = os.environ.get("THEME_RIFE_WORKERS", "")
    if forced.isdigit() and int(forced) > 0:   # manual testing: exactly this many (the out-of-memory halving still applies)
        return int(forced), f"RIFE workers {int(forced)} (forced by THEME_RIFE_WORKERS)"
    if opt_speed() == "background":
        return 1, "RIFE workers 1 (background speed)"
    n, why = rife_worker_count_fast(bp)
    if opt_speed() == "balanced":
        return speed_scale(n, 1), f"RIFE workers {speed_scale(n, 1)} (balanced: {BALANCED_FRAC:.0%} of {why})"
    return n, why


def rife_worker_count_fast(bp):
    """rife_worker_count at full speed: the VRAM-sized count."""
    GB = float(1 << 30)
    v = gpu_vram()
    per = max(0.4, 1.3 * bp["w"] * bp["h"] / (2560 * 1440))
    if not v or v[0] < 3 * GB:
        return 1, "RIFE workers 1 (" + ("VRAM unknown" if not v else f"VRAM {v[0] / GB:.1f} GB") + ")"
    margin = max(1.5, 0.1 * v[0] / GB)
    n = max(1, min(RIFE_WORKERS, int((v[1] / GB - margin) // per)))
    return n, f"RIFE workers {n} (free VRAM {v[1] / GB:.1f} of {v[0] / GB:.1f} GB, est {per:.1f} GB each, margin {margin:.1f} GB)"


def bake_wind_minterp(video, bp, tmpd, label):
    """Wind part through ffmpeg: chunks interpolated by parallel processes (count follows the load, re-evaluated every
    second), each into its own H.264 part; returns the parts in order. JobCancelled when the job goes stale."""
    chunks = bake_chunks(bp, min(BAKE_CHUNKS, max(1, (bp["N"] + 1) // 24)))
    bp = dict(bp, video=video)
    done, frac, errs, threads, running = {}, {}, [], {}, set()
    total = sum(c[1] - c[0] for c in chunks)
    nice_now = [BAKE_NICE]

    def work(i, ch, nice):
        ins, vf, secs = bake_chunk_filters(bp, ch)
        part = tmpd / f"w{i:03d}.mp4"
        try:
            ok = ff_encode(ins, vf, part, secs, label, prog=lambda f, i=i: frac.__setitem__(i, f), nice=nice, cfr=False)   # passthrough: cfr rounding dropped a frame next to a source pts
        except JobCancelled:
            ok = None
        done[i] = part if ok else ok

    pending = list(range(len(chunks)))
    last_eval = 0.0
    want = 1
    while pending or threads:
        if job_stale():
            break
        for i, t in list(threads.items()):
            if not t.is_alive():
                t.join()
                del threads[i]
        if any(v is False or v is None for v in done.values()):
            break
        now = time.time()
        if now - last_eval >= 1.0:
            last_eval = now
            with _RUN["lock"]:
                pids = [p.pid for p in _RUN["procs"]]
            want, nice_now[0] = bake_workers(pids)
        while pending and len(threads) < want:
            i = pending.pop(0)
            threads[i] = threading.Thread(target=work, args=(i, chunks[i], nice_now[0]), daemon=True)
            threads[i].start()
        lo, hi = bp.get("pct", (10, 99))
        pct = lo + (hi - lo) * sum(frac.get(i, 1.0 if isinstance(done.get(i), Path) else 0.0) * (chunks[i][1] - chunks[i][0]) for i in range(len(chunks))) / total
        opt_status(state="encoding", label=label, pct=min(99, round(pct)), kind="bake")
        time.sleep(0.05)
    stale = job_stale()
    if stale or any(v is False or v is None for v in done.values()):
        with _RUN["lock"]:
            procs = list(_RUN["procs"])
        procs_kill(procs)
    for t in threads.values():
        t.join()
    if stale:
        raise JobCancelled()
    if len(done) != len(chunks) or not all(isinstance(v, Path) for v in done.values()):
        return None
    return [done[i] for i in range(len(chunks))]


@_memo
def video_color(path):
    """{color_space, color_primaries, color_transfer, color_range} tags of the first video stream ({} when untagged)."""
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                              "stream=color_space,color_primaries,color_transfer,color_range", "-of", "json", path],
                             capture_output=True, text=True, timeout=20).stdout
        s = json.loads(out)["streams"][0]
        return {k: v for k, v in s.items() if v not in ("unknown", "", None)}
    except (OSError, ValueError, KeyError, IndexError, subprocess.TimeoutExpired):
        return {}


# yuv -> rgb for the PNGs RIFE reads: an explicit full-range, accurate conversion; the default one came back 1.7 levels
# DARKER through the round trip (measured, a luma step at every seam between interpolated and direct frames)
RGB_UP = "scale=flags=accurate_rnd+full_chroma_int:out_range=pc"


def bake_rgb_down(video):
    """(scale filter, colour tag args) turning RGB frames back into yuv with the SOURCE's matrix, range and tags."""
    col = video_color(video)
    mtx = {"bt709": "bt709", "smpte170m": "smpte170m", "bt470bg": "bt470", "bt2020nc": "bt2020"}.get(col.get("color_space", ""))
    sc = (f"scale=in_range=pc:out_range={'pc' if col.get('color_range') == 'pc' else 'tv'}:flags=accurate_rnd+full_chroma_int"
          + (f":out_color_matrix={mtx}" if mtx else ""))
    tags = [x for k, o in (("color_space", "-colorspace"), ("color_primaries", "-color_primaries"), ("color_transfer", "-color_trc"), ("color_range", "-color_range"))
            if k in col for x in (o, col[k])]
    return sc, tags


def rife_frames(bp):
    """[(i, j)] per output frame k = 0..N of a curve part: the source pair (i, i + 1) at the time step j / RIFE_G (j = 0: source
    frame i itself, no RIFE). Where the output steps RIFE_NEAREST or more source frames per frame (full speed / the fast end of a
    curve: nothing to invent) the nearest source frame is shown instead. Timing error: <= 1 / (2 RIFE_G) source frame where
    interpolated, <= 1/2 source frame where stepped."""
    import math
    pts = bake_breaks(bp)
    sfps, F, N = bp["sfps"], bp["F"], bp["N"]
    last_i = round(bp["last"] * sfps)
    f = [bake_m_of_w(pts, k / F) * sfps for k in range(N + 1)]
    out = []
    for k in range(N + 1):
        k0, k1 = max(0, k - 1), min(N, k + 1)
        step = (f[k1] - f[k0]) / max(1, k1 - k0)
        if step >= RIFE_NEAREST:
            i, j = int(math.floor(f[k] + 0.5)), 0
        else:
            i = int(math.floor(f[k] + 1e-6))
            j = round((f[k] - i) * RIFE_G)
            if j >= RIFE_G:
                i, j = i + 1, 0
        if i >= last_i:
            i, j = last_i, 0
        out.append((i, j))
    return out


def rife_part_frames(pbp):
    """[(a, b, j)] per output frame k < k_end of a curve part, as ORIGINAL source frame indices: pbp["orig"] = (offset, loop
    frames) maps the part's own index x (a burst's source clip starts at 0) to (offset + x) % loop frames; None = the same."""
    off, wrap = pbp.get("orig") or (0, 0)
    o = (lambda x: (off + x) % wrap) if wrap else (lambda x: off + x)
    return [(o(i), o(i + 1), j) for i, j in rife_frames(pbp)[:pbp.get("k_end", pbp["N"] + 1)]]


def png_dummy(dest, size=64):
    """A black size x size rgb PNG (the filler pair of unused RIFE outputs)."""
    import struct
    import zlib

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + bytes(size * 3) for _ in range(size))
    dest.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


# ---- the RIFE stage of a bake: few long-lived rife-ncnn-vulkan processes ----
# One rife-ncnn-vulkan process per pair (the old way) reloads the model and rebuilds the Vulkan pipelines for every frame: the
# GPU idled at ~10 %. Its directory mode keeps one process (model loaded once, load / proc / save threads) but only makes
# uniformly spaced frames: output i of `-i dir -n T` (N files, sorted names) is RIFE(L[x], L[x + 1], fx - x), fx = i N / T,
# x = floor(fx) (verified bit-identical to the single-pair `-s` runs). The trick: N / T = (2G + 1) / G puts output i = qG + j
# on slot x = 2i + q at step j / G, so every output has a slot pair of its own; the list is HARD links (symlinks crash the tool)
# to the wanted source PNGs, bucket j fixes the step. So one process renders arbitrary (a, b, step) frames at step precision
# 1 / G. Unused outputs get a 64x64 dummy pair (~1.5 ms each); j = 0 outputs are plain copies (no GPU). C = outputs per bucket
# and run is kept at RIFE_C so i * N stays below 2^24 (the tool's float index math is exact there).
# RifeStore plans every interpolated frame of the whole bake up front (in the order the encoders consume the parts), and a
# producer thread renders them in RAM-bounded batches (source PNGs decoded once per batch, RIFE by `workers` processes) while
# the encoders consume the previous batch: the GPU is busy for the whole RIFE stage.
RIFE_G = 64            # time steps are multiples of 1/64 source frame (max timing error 1/128 frame)
RIFE_C = 40            # outputs per step bucket in one run: G * C = 2560 outputs, i * N < 2^24
RIFE_NEAREST = 1.0     # output frames that step >= this many source frames per frame show the nearest source frame (no RIFE)
RIFE_BATCH = 320       # RIFE frames per batch at most (small batches: the encoders follow closely, a short tail after the GPU)
RIFE_DEC_RUN = 240     # source frames per decoder process (parallel decoders; each seeks to its start)
RIFE_PNG_EST = 0.5     # first guess of a PNG's size as a fraction of w * h * 3 (replaced by the measured mean)
BAKE_HWDEC = os.environ.get("THEME_BAKE_HWDEC", "0") == "1"   # decode the bake's source PNGs with VA-API (measured 2.3x SLOWER than dav1d here: off)


class RifeStore:
    def __init__(self, video, bp, parts, label=""):
        """parts = [(part id, [(a, b, j)] per output frame)] in the order the encoders will ask for them; video / bp = the source and
        plan whose geometry the source PNGs get (frame indices are that video's)."""
        self.video, self.bp, self.label = video, bp, label
        self.parts = dict(parts)
        self.order = [p for p, _ in parts]
        self.cv = threading.Condition()
        self.ready, self.batch_of, self.batches = {}, {}, []
        self.resident = 0
        self.closed = False
        self.procs = []
        self.items_total = max(1, sum(len({x for x in fr if x[2]}) for _, fr in parts))
        self.items_done = 0
        self.pct = 0
        self.png_bytes = RIFE_PNG_EST * bp["w"] * bp["h"] * 3
        self.sizes = []
        self.disk = video_cache() / "opt" / f".rife-{os.getpid()}-{id(self)}"
        self.dirs = []
        self.stats = {"rife_s": 0.0, "extract_s": 0.0, "busy": [], "items": 0, "outputs": 0, "span": [None, None]}
        self.t0 = time.time()
        pick = rife_pick()
        self.exe, self.model = rife_bin(), (pick[1] if pick else None)
        self.workers, why = rife_worker_count(bp)
        print("theme: " + why, flush=True)
        free = 0
        try:
            base = Path("/dev/shm")
            free = shutil.disk_usage(base).free
        except OSError:
            pass
        self.budget = max(1 << 30, min(0.4 * mem_available(), 0.8 * free) / 3)   # bytes per batch (three batches live at once)
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    # -- consumer side
    def wait(self, pid, label="", pct=0):
        """The PNG paths of part `pid`'s output frames in order (waits, cancel-aware), or None when the RIFE stage failed."""
        if pid not in self.parts:
            return None
        while True:
            if job_stale():
                raise JobCancelled()
            with self.cv:
                if pid in self.ready:
                    b = self.batch_of.get(pid)
                    for ob in range(b if b is not None else 0):   # parts are consumed in order: everything before is done
                        self._free(ob)
                    return self.ready[pid]
                self.cv.wait(0.2)
            p = max(self.pct, pct, min(98, round(99 * self.items_done / self.items_total)))
            if p != self.pct:
                self.pct = p
                opt_status(state="encoding", label=label or self.label, pct=p, kind="bake")

    def done(self, pid):
        """Part `pid` is encoded: its batch is freed once all of its parts are."""
        with self.cv:
            b = self.batch_of.get(pid)
            if b is None:
                return
            self.batches[b]["left"].discard(pid)
            if not self.batches[b]["left"]:
                self._free(b)

    def _free(self, b):   # (cv held)
        bt = self.batches[b] if b < len(self.batches) else None
        if bt and not bt["freed"]:
            bt["freed"] = True
            shutil.rmtree(bt["dir"], ignore_errors=True)
            self.resident -= 1
            self.cv.notify_all()

    def close(self):
        """Stop the producer (its processes are killed) and remove every file."""
        with self.cv:
            self.closed = True
            self.cv.notify_all()
        procs_kill(list(self.procs))
        for pr in list(self.procs):
            job_reap(pr)
        self.thread.join(timeout=10)
        for d in self.dirs:
            shutil.rmtree(d, ignore_errors=True)

    def summary(self):
        b = self.stats["busy"]
        return (f"RIFE stage: {self.stats['items']} frames in {self.stats['rife_s']:.1f} s ({self.stats['items'] / max(0.1, self.stats['rife_s']):.1f}/s, "
                f"{self.workers} workers, GPU busy {sum(b) / len(b):.0f} %" if b else "") + f"), source PNGs {self.stats['extract_s']:.1f} s (overlapped), GPU from {self.stats['span'][0] or 0:.1f} to {self.stats['span'][1] or 0:.1f} s"

    # -- producer side
    def _need(self, pid):
        fr = self.parts[pid]
        srcs = {a for a, _, _ in fr} | {b for _, b, j in fr if j}
        return (len(srcs) + len({x for x in fr if x[2]})) * self.png_bytes

    def _run(self):
        """Batches in order: the source PNGs of batch k + 1 are decoded while batch k is on the GPU; at most three batches live
        (the encoders', the GPU's, the decoder's), each within a third of the RAM budget. The first batch is small (the GPU
        starts early)."""
        i = [0]

        def take(first=False):
            pids, need, cnt = [], 0.0, 0
            cap, ccap = (self.budget / 8, RIFE_BATCH // 4) if first else (self.budget, RIFE_BATCH)
            while i[0] < len(self.order):
                n = self._need(self.order[i[0]])
                c = len({x for x in self.parts[self.order[i[0]]] if x[2]})
                if pids and (need + n > cap or cnt + c > ccap):
                    break
                pids.append(self.order[i[0]])
                need += n
                cnt += c
                i[0] += 1
            return (pids, need) if pids else None

        def prep(b, res):
            try:
                res.append(self._prep(*b))
            except JobCancelled:
                res.append(None)
            except Exception as e:   # noqa: BLE001
                print(f"theme: RIFE stage: decoding failed: {e!r}", flush=True)
                res.append(None)
        try:
            b = take(first=True)
            cur = self._prep(*b) if b else None
            while cur:
                with self.cv:
                    while self.resident >= 2 and not self.closed:
                        self.cv.wait(0.2)
                    if self.closed:
                        return
                nb, res, th = take(), [], None
                if nb:
                    th = threading.Thread(target=prep, args=(nb, res), daemon=True)
                    th.start()
                ok = self._render(cur)
                if th:
                    th.join()
                if not ok:
                    break
                cur = res[0] if res else None
                if nb and cur is None:
                    break
        except JobCancelled:
            pass
        except Exception as e:   # noqa: BLE001 - a broken RIFE stage falls back to minterpolate, it must not hang the encoders
            print(f"theme: RIFE stage failed: {e!r}", flush=True)
        finally:
            with self.cv:
                for pid in self.order:
                    self.ready.setdefault(pid, None)
                self.cv.notify_all()

    def _spawn(self, cmd):
        pr = job_spawn(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.procs.append(pr)
        return pr

    def _reap(self, pr):
        job_reap(pr)
        if pr in self.procs:
            self.procs.remove(pr)

    def _check(self):
        if self.closed or job_stale():
            raise JobCancelled()

    def _prep(self, pids, need):
        """Decode the source PNGs of a batch: (pids, dir, frames, {index: path}, items) or None."""
        with self.cv:
            n = self.nbatch = getattr(self, "nbatch", -1) + 1
        base = bake_ram_dir(need) or self.disk
        d = base / f"rife-{n}"
        shutil.rmtree(d, ignore_errors=True)
        d.mkdir(parents=True)
        with self.cv:
            self.dirs.append(d)
        frames = [x for p in pids for x in self.parts[p]]
        srcs = sorted({a for a, _, _ in frames} | {b for _, b, j in frames if j})
        items = sorted({x for x in frames if x[2]}, key=lambda x: (x[2], x[0]))
        t0 = time.time()
        sp = self._extract(srcs, d / "src")
        self.stats["extract_s"] += time.time() - t0
        if sp is None:
            return None
        try:
            self.sizes += [os.path.getsize(sp[a]) for a in srcs[:: max(1, len(srcs) // 16)]]
            self.png_bytes = max(self.png_bytes * 0.25, sum(self.sizes) / len(self.sizes) * 1.3)   # rife's own PNGs are a bit bigger
        except OSError:
            pass
        return pids, d, sp, items

    def _render(self, cur):
        """RIFE a decoded batch and hand it to the encoders. True on success."""
        pids, d, sp, items = cur
        outs = self._rife(items, sp, d) if items else {}
        if outs is None:
            return False
        with self.cv:
            b = len(self.batches)
            self.batches.append({"dir": d, "left": set(pids), "freed": False})
            self.resident += 1
            for p in pids:
                self.batch_of[p] = b
                self.ready[p] = [outs[x] if x[2] else sp[x[0]] for x in self.parts[p]]
            self.cv.notify_all()
        return True

    def _extract(self, srcs, d):
        """Decode the source frames `srcs` (indices) as rgb PNGs at the output size: one ffmpeg per run of nearby indices, a few
        at once. {index: path} or None."""
        d.mkdir(parents=True, exist_ok=True)
        sfps = self.bp["sfps"]
        runs = []
        for x in srcs:   # runs of nearby frames, at most RIFE_DEC_RUN long (a few decoders at once)
            if runs and x - runs[-1][1] <= 6 and x - runs[-1][0] < RIFE_DEC_RUN:
                runs[-1][1] = x
            else:
                runs.append([x, x])
        hw = BAKE_HWDEC and hwdec_ok(self.video) and opt_vaapi_device()
        vf = ",".join(bake_geometry(self.bp) + [RGB_UP, "format=rgb24"])

        def cmd(lo, hi, hwdec):
            return (job_prio() + ["ffmpeg", "-hide_banner", "-v", "error", "-y"] + bg_threads()
                    + (["-hwaccel", "vaapi", "-hwaccel_device", hwdec] if hwdec else [])
                    + (["-ss", f"{(lo - 0.5) / sfps:.6f}"] if lo > 0 else []) + ["-i", self.video, "-map", "0:v:0", "-an", "-vf", vf, "-fps_mode", "passthrough",
                                                                                  "-compression_level", "1", "-frames:v", str(hi - lo + 1), "-start_number", str(lo), str(d / "%06d.png")])
        par = speed_scale(max(1, min(4, (os.cpu_count() or 4) // 4)), 1)
        want = set(srcs)
        queue = [(lo, hi, hw) for lo, hi in runs]
        active = []
        while queue or active:
            self._check()
            while queue and len(active) < par:
                lo, hi, h = queue.pop(0)
                active.append((self._spawn(cmd(lo, hi, h)), lo, hi, h))
            for t in list(active):
                pr, lo, hi, h = t
                if pr.poll() is None:
                    continue
                self._reap(pr)
                active.remove(t)
                if not all((d / f"{x:06d}.png").exists() for x in range(lo, hi + 1) if x in want):
                    if h:   # VA-API decode failed: software
                        queue.append((lo, hi, None))
                        continue
                    print(f"theme: decoding source frames {lo}-{hi} failed", flush=True)
                    return None
            time.sleep(0.02)
        for f in d.iterdir():   # the frames between wanted ones (stepped parts) are not needed
            try:
                if int(f.stem) not in want:
                    f.unlink()
            except ValueError:
                pass
        return {x: d / f"{x:06d}.png" for x in srcs}

    def _rife(self, items, sp, d):
        """RIFE every (a, b, j) of `items` with the long-lived processes. {item: output path} or None."""
        G = RIFE_G
        dummy = d / "dummy.png"
        png_dummy(dummy)
        P = max(1, self.workers)
        runs = []
        for w in range(P):   # items are sorted by step bucket: dealing them out keeps every worker's buckets even
            mine = items[w::P]
            if not mine:
                continue
            bk = {}
            for x in mine:
                bk.setdefault(x[2], []).append(x)
            for r in range((max(len(v) for v in bk.values()) + RIFE_C - 1) // RIFE_C):
                runs.append({j: v[r * RIFE_C:(r + 1) * RIFE_C] for j, v in bk.items() if v[r * RIFE_C:(r + 1) * RIFE_C]})
        out = {}
        if self.stats["span"][0] is None:
            self.stats["span"][0] = time.time() - self.t0
        limit = len(runs) and min(P, len(runs))
        queue = list(range(len(runs)))
        fails = {}
        active = {}   # run index -> (Popen, run dir, {output path: item})
        t0 = time.time()
        busy_f = rife_busy_file()
        last_count = 0.0

        def start(r):
            rd = d / f"r{r}-{fails.get(r, 0)}"
            shutil.rmtree(rd, ignore_errors=True)
            (rd / "in").mkdir(parents=True)
            (rd / "out").mkdir()
            run = runs[r]
            C = max(len(v) for v in run.values())
            T, N = G * C, (2 * G + 1) * C
            lst = [dummy] * N
            omap = {}
            for j, v in run.items():
                for q, (a, b, _) in enumerate(v):
                    i = q * G + j
                    s = 2 * i + q
                    lst[s], lst[s + 1] = sp[a], sp[b]
                    omap[rd / "out" / f"{i + 1:08d}.png"] = (a, b, j)
            for k, f in enumerate(lst):
                os.link(f, rd / "in" / f"{k:08d}.png")
            cmd = job_prio() + [self.exe, "-i", str(rd / "in"), "-o", str(rd / "out"), "-n", str(T), "-m", self.model, "-g", str(RIFE_GPU), *RIFE_ARGS]
            if RIFE_OOM_TEST and limit > RIFE_OOM_TEST:   # test hook: more than N at once "runs out of memory"
                cmd = ["false"]
            active[r] = (self._spawn(cmd), rd, omap)

        while queue or active:
            self._check()
            while queue and len(active) < limit:
                start(queue.pop(0))
            for r, (pr, rd, omap) in list(active.items()):
                if pr.poll() is None:
                    continue
                self._reap(pr)
                del active[r]
                if pr.returncode != 0 or not all(p.exists() for p in omap):
                    # most likely a Vulkan out-of-memory: fewer processes at once, this run again; a run failing alone twice = give up
                    fails[r] = fails.get(r, 0) + 1
                    shutil.rmtree(rd, ignore_errors=True)
                    if limit == 1 and fails[r] >= 2:
                        print("theme: RIFE failed", flush=True)
                        return None
                    if limit > 1:
                        limit = self.workers = max(1, limit // 2)   # (the later batches too)
                        print(f"theme: a RIFE process failed, now {limit} at once", flush=True)
                    queue.insert(0, r)
                    continue
                for p, x in omap.items():
                    out[x] = p
                shutil.rmtree(rd / "in", ignore_errors=True)
                self.stats["outputs"] += G * max(len(v) for v in runs[r].values())
            if busy_f:
                try:
                    self.stats["busy"].append(int(Path(busy_f).read_text()))
                except (OSError, ValueError):
                    pass
            if time.time() - last_count > 1.0:   # progress: outputs written so far
                last_count = time.time()
                n = sum(1 for _, rd, om in active.values() for p in om if p.exists())
                self.items_done = self.stats["items"] + len(out) + n
            time.sleep(0.1)
        self.stats["rife_s"] += time.time() - t0
        self.stats["span"][1] = time.time() - self.t0
        self.stats["items"] += len(items)
        self.items_done = self.stats["items"]
        return out


def rife_busy_file():
    """sysfs gpu_busy_percent of the GPU RIFE uses (amdgpu: the card with the most VRAM), or None (stats only)."""
    best = None
    for d in Path("/sys/class/drm").glob("card?/device"):
        try:
            a = int((d / "mem_info_vram_total").read_text())
        except (OSError, ValueError):
            continue
        if (d / "gpu_busy_percent").exists() and (best is None or a > best[0]):
            best = (a, d / "gpu_busy_percent")
    return best[1] if best else None


def rife_encode(paths, spec_video, label, part, lo, hi, F, keep=None):
    """Encode the PNGs `paths` (in order, at F fps) into `part`: ONE encoder fed over a pipe, rgb back to yuv with the matrix and
    tags of `spec_video` (bake_rgb_down). keep = a directory: no encoder, the frames are copied there as `<k>.png` (k from 0) for a
    later blend (bake_fade); [] is returned. [part] or None."""
    if keep is not None:
        keep.mkdir(parents=True, exist_ok=True)
        for k, p in enumerate(paths):
            shutil.copyfile(p, keep / f"{k:05d}.png")
        return []
    tmp = part.with_name(".tmp-" + part.name)
    sc, tags = bake_rgb_down(spec_video)
    pre, vfs, codec = ff_tries([sc])[0]
    cmd = job_prio() + ["ffmpeg", "-hide_banner", "-v", "error", "-y", *bg_threads("-filter_threads", BG_FILTER_THREADS), *pre, "-threads", "4", "-f", "image2pipe", "-c:v", "png", "-framerate", str(F), "-i", "-",
           "-vf", vfs, "-an", *tags, "-fps_mode", "passthrough", *codec, "-video_track_timescale", "90000", "-movflags", "+faststart", "-f", "mp4", str(tmp)]
    enc = job_spawn(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ok = False
    try:
        for k, p in enumerate(paths):
            if k % 8 == 0:
                if job_stale():
                    raise JobCancelled()
                opt_status(state="encoding", label=label, pct=min(98, round(lo + (hi - lo) * k / max(1, len(paths)))), kind="bake")
            if enc.poll() is not None:
                return None
            try:
                enc.stdin.write(Path(p).read_bytes())
            except (OSError, ValueError):
                return None
        enc.stdin.close()
        enc.wait()
        ok = enc.returncode == 0 and tmp.exists() and tmp.stat().st_size > 0
        if ok:
            os.replace(tmp, part)
        return [part] if ok else None
    finally:
        if not ok:
            procs_kill([enc])
        job_reap(enc)
        tmp.unlink(missing_ok=True)


# ---- replays: short bursts along the loop ----
# After the first play holds on H (media t_stop), every replay is a short baked BURST: an ease-in from rest (speed 0 -> 1 over
# `ease`) immediately followed by the cosine wind-down (1 -> 0 over `wind`), no full-speed part in between, so the clip
# advances d = ease / 2 + wind / 2 media seconds per switch and holds on the new frame (the next burst starts on it).
# The positions ("stations") S_i = S_0 + i d, S_0 = t_stop. A seamless-LOOP clip (loop_wrap) wraps around (frame 0 follows the
# last frame): K = round(L / d) bursts cover exactly one loop (d = L / K), only K segments are baked and the cycle repeats
# (a burst that crosses the wrap just continues through frame 0). A NON-loop clip advances until the next burst would cross
# its end, then starts over from S_0: when the jump back is small a clean cut (the burst from S_0 again), else a burst whose
# ease-in part is a FADE from the held frame into the burst (the clip already moves under it; the rest of the burst is the
# same encoded part as burst 0's). K is capped (bake cost: every burst is RIFE-interpolated) at burst_kmax: as many bursts as
# BURST_RIFE_BUDGET RIFE frames allow, KMAX_MIN..KMAX (a 60 Hz monitor walks a 2 min clip in ~64 bursts, the 120 fps bake of a
# 360 Hz one needs ~4x the frames per burst and gets ~19). A loop that would need more bursts is walked over the cap's short
# bursts like a non-loop clip (it restarts from S_0 with the cut / fade rule), never with
# long full-speed stretches. A burst is never shorter than BURST_MIN on screen (ease + wind lengthened; both zero = one
# plain second).
BURST_MIN = 1.0
KMAX = 64
KMAX_MIN = 16
BURST_RIFE_BUDGET = 8000   # RIFE frames of all bursts together (~6 min at the ~21 frames/s of an RX 9070 XT at 1440p)
BURST_VERSION = "s2"
# The cut-or-fade decision is made on the ACTUAL jump: cut = mean absolute luma difference (640 px, 0-255) between the held
# frame and the frame the next burst starts on, compared with the clip's typical frame-to-frame change over the first second
# after it. Clean only if invisible in absolute terms (<= CUT_ABS) or not much more than a normal step (<= CUT_RATIO x it).
CUT_ABS = 0.6
CUT_RATIO = 10.0
# Wallpaper videos are mostly authored as seamless loops. A clip is a loop when its last -> first frame step is like a
# normal step: cut <= LOOP_WRAP_RATIO x the median step (both ends) or invisible (<= LOOP_WRAP_ABS). Of the user's 13 clips
# 11 are (ratios 0.9-8.5, the abs rule takes 10221), nier (15.5), A8B4 (22) and frieren-and-fern (161) are not.
LOOP_WRAP_RATIO = 6.0
LOOP_WRAP_ABS = 0.3
LOOP_DUP = 0.02   # last == first (identical): the loop drops one of them


def loop_yavg(args):
    r = subprocess.run(args, stdin=subprocess.DEVNULL, capture_output=True, text=True)
    return [float(x) for x in re.findall(r"YAVG=([\d.]+)", r.stdout)]


def loop_png(video, ss, dest):
    """One frame (first at / after ss) as a 640 px gray PNG."""
    subprocess.run(["ffmpeg", "-hide_banner", "-v", "error", "-y", *(["-ss", f"{max(0.0, ss):.6f}"] if ss > 0 else []), "-i", video, "-frames:v", "1",
                    "-vf", "scale=640:-2:flags=area,format=gray", str(dest)], stdin=subprocess.DEVNULL, capture_output=True)
    return dest.exists()


def loop_diff(a, b):
    """Mean absolute luma difference of two 640 px gray PNGs (0-255)."""
    v = loop_yavg(["ffmpeg", "-hide_banner", "-v", "error", "-i", str(a), "-i", str(b), "-lavfi",
                   "[0:v][1:v]blend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-", "-f", "null", "-"])
    return v[0] if v else 99.0


def loop_typ(video, ss, dur):
    """Median consecutive-frame change (mean absolute luma difference, 640 px, duplicates ignored) over video[ss, ss + dur)."""
    v = [x for x in loop_yavg(["ffmpeg", "-hide_banner", "-v", "error", *(["-ss", f"{max(0.0, ss):.6f}"] if ss > 0 else []), "-t", f"{dur:.3f}", "-i", video, "-vf",
                               "scale=640:-2:flags=area,format=gray,tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-",
                               "-f", "null", "-"]) if x > 0.003]
    return max(0.01, sorted(v)[len(v) // 2]) if v else 0.01


def loop_cut(video, last, t, sfps, td):
    """(cut, typ) of the jump from H (the frame at `last`) to the replay entry frame at media time t."""
    h, k = td / "cH.png", td / "cK.png"
    if not loop_png(video, max(0.0, last - 0.2 / sfps), h) or not loop_png(video, max(0.0, t - 0.5 / sfps) if t > 0 else 0.0, k):
        return 99.0, 0.01
    return loop_diff(h, k), loop_typ(video, t, 1.0)


def loop_wrap(video, last_clip, sfps):
    """Is the clip a seamless loop? {cut (last -> first), typ (median step at both ends), ratio, loop, dup}; cached."""
    import tempfile
    f = video_cache() / (_stamp(video, "wrap") + f"-{round(last_clip * 1000)}-w1.json")
    try:
        return json.loads(f.read_text())
    except (OSError, ValueError):
        pass
    with tempfile.TemporaryDirectory(dir=str(video_cache()), prefix=".wrap-") as td:
        td = Path(td)
        a, b = td / "L.png", td / "F.png"
        if not loop_png(video, max(0.0, last_clip - 0.2 / sfps), a) or not loop_png(video, 0.0, b):
            return {"cut": 99.0, "typ": 0.01, "ratio": 99.0, "loop": False, "dup": False}
        cut = loop_diff(a, b)
        typ = max(loop_typ(video, max(0.0, last_clip - 1.0), 1.0 + 0.5 / sfps), loop_typ(video, 0.0, 1.0))
    res = {"cut": round(cut, 4), "typ": round(typ, 4), "ratio": round(cut / typ, 2), "loop": cut <= LOOP_WRAP_ABS or cut / typ <= LOOP_WRAP_RATIO, "dup": cut <= LOOP_DUP}
    write_atomic(f, json.dumps(res))
    return res


def bake_png(video, bp, ss, dest):
    """One source frame (the first at / after `ss` s) as a PNG at the output size, rgb24."""
    r = subprocess.run(["ffmpeg", "-hide_banner", "-v", "error", "-y", *(["-ss", f"{ss:.6f}"] if ss > 0 else []), "-i", video, "-map", "0:v:0", "-an",
                        "-vf", ",".join(bake_geometry(bp) + [RGB_UP, "format=rgb24"]), "-frames:v", "1", str(dest)], stdin=subprocess.DEVNULL, capture_output=True)
    return r.returncode == 0 and dest.exists()


def bake_psnr(a, b):
    """PSNR (dB) between two PNGs, 99 when identical."""
    r = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(a), "-i", str(b), "-lavfi", "psnr", "-f", "null", "-"], stdin=subprocess.DEVNULL, capture_output=True, text=True)
    m = re.search(r"average:([\d.]+|inf)", r.stderr)
    return 99.0 if not m or m.group(1) == "inf" else float(m.group(1))


def bake_bursts(video, bp):
    """The replay plan: the burst segments (see "replays: short bursts along the loop"). Returns {loop, d (media s per
    burst), K, segs [{i_s (first source frame), n (frames), E, W, P (seconds: ease-in, wind-down, full-speed stretch), fade
    (source frame of the held frame the burst fades in from, or None)}], cycle_from (index the cycle continues at after
    the last segment), text}."""
    import math
    import tempfile
    sfps = bp["sfps"]
    wrap = loop_wrap(video, bp["last_clip"], sfps)
    loop = wrap["loop"]
    i_H, i_end = round(bp["last"] * sfps), round(bp["last_clip"] * sfps)
    L_f = i_end + (0 if wrap["dup"] and loop else 1)   # the loop's frames (an identical last frame is dropped)
    E0, W0 = bp["ease"], bp["wind"]

    def shape(E, W):
        E = E if E >= 0.2 else 0.0
        plain_s = 0.0
        if E + W < BURST_MIN:
            if E + W <= 0:
                plain_s = BURST_MIN
            else:
                W = BURST_MIN - E
        return E, W, plain_s, max(2, round(((E + W) / 2 + plain_s) * sfps))

    E, W, plain_s, d_f = shape(E0, W0)
    kmax = burst_kmax(bp, E, W, plain_s, d_f)
    # a loop whose K = L / d would need more than KMAX bursts is NOT covered round and round (that would need long full-speed
    # stretches in each burst, or an hour of baking): it is walked like a non-loop clip over KMAX short bursts and then restarts
    loop = loop and max(1, round(L_f / d_f)) <= kmax
    if not loop:
        E, W, plain_s, d_f = shape(max(E0, 0.4), W0)   # a fade-in of a restart needs motion under it

    def seg(i_s, n, fade=None):
        media = n / sfps
        base = (E + W) / 2
        if plain_s:
            return {"i_s": i_s, "n": n, "E": 0.0, "W": 0.0, "P": media, "fade": fade}
        f = min(1.0, media / base) if base > 0 else 1.0
        return {"i_s": i_s, "n": n, "E": E * f, "W": W * f, "P": max(0.0, media - base), "fade": fade}

    segs, cyc = [], 0
    if loop:
        K = max(1, min(kmax, round(L_f / d_f)))
        S = [(i_H + round(i * L_f / K)) % L_f for i in range(K + 1)]
        for i in range(K):
            segs.append(seg(S[i], ((S[i + 1] - S[i]) % L_f) or L_f))
        d = L_f / K / sfps
        text = f"each switch advances ~{d:.1f} s ({K} steps per loop)"
    else:
        jump = {}

        def big(frm, to):   # is the jump from the held frame `frm` to the frame `to` visible?
            if (frm, to) not in jump:
                with tempfile.TemporaryDirectory(dir=str(video_cache()), prefix=".cut-") as td:
                    c, t = loop_cut(video, frm / sfps, to / sfps, sfps, Path(td))
                jump[(frm, to)] = not (c <= CUT_ABS or c / t <= CUT_RATIO)
            return jump[(frm, to)]
        m = min(kmax, (i_end - i_H) // d_f)
        if m >= 1:   # stations from S_0 = H: the first replay continues exactly where the first play held
            S = [i_H + j * d_f for j in range(m + 1)]
            segs = [seg(S[j], d_f) for j in range(m)]
            if big(S[m], i_H):
                segs.append(seg(i_H, d_f, fade=S[m]))
                cyc = 1
        else:   # H is within one burst of the end: the stations restart from frame 0
            m = max(1, min(kmax, i_end // d_f))
            n = max(2, i_end // m) if i_end // d_f < 1 else d_f
            S = [j * n for j in range(m + 1)]
            segs = [seg(0, n, fade=i_H if big(i_H, 0) else None)] + [seg(S[j], n) for j in range(1, m)]
            if big(S[m], 0):
                segs.append(seg(0, n, fade=S[m]))
                cyc = 1
        d = d_f / sfps
        text = f"each switch advances ~{d:.1f} s ({m} steps, then back to the start" + (" with a fade)" if cyc else ")")
    return {"loop": loop, "d": d, "K": len(segs), "segs": segs, "cycle_from": cyc, "text": text, "L_f": L_f, "i_end": i_end, "dup": wrap["dup"]}


def burst_kmax(bp, E, W, plain_s, d_f):
    """Most bursts a bake gets: BURST_RIFE_BUDGET / the RIFE frames of one burst (its ease-in + wind-down at this F / source fps),
    KMAX_MIN..KMAX; KMAX_MIN without RIFE (minterpolate runs on the CPU)."""
    if os.environ.get("THEME_BAKE_KMAX", "").isdigit():   # tests: a fixed cap
        return max(1, int(os.environ["THEME_BAKE_KMAX"]))
    if not bp["interp"].startswith("rife") or plain_s:
        return KMAX_MIN
    sfps = bp["sfps"]
    sg = {"i_s": 0, "n": d_f, "E": E, "W": W, "P": 0.0, "fade": None}
    _, _, _, _, bi, bw = burst_plans(bp, {"L_f": 1 << 30}, sg)
    per = sum(1 for x in (bi, bw) if x for _, _, j in rife_part_frames(x) if j)
    return max(KMAX_MIN, min(KMAX, BURST_RIFE_BUDGET // max(1, per)))


def bake_src_clip(video, bp, i_s, n, rp, dest):
    """Frames i_s .. i_s + n (inclusive, wrapping through frame 0 on a loop) of `video` at the output size as a lossless NUT
    with exact CFR timestamps (frame j at j / sfps) and the source's colour tags: the burst's own source, so its retiming
    works on plain virtual times from 0 whatever the wrap. True on success."""
    sfps, L_f = bp["sfps"], rp["L_f"]
    col = video_color(video)
    tags = [x for k, o in (("color_space", "-colorspace"), ("color_primaries", "-color_primaries"), ("color_transfer", "-color_trc"), ("color_range", "-color_range"))
            if k in col for x in (o, col[k])]
    n_a = min(n + 1, L_f - i_s)
    pieces = [(i_s, n_a)] + ([(0, n + 1 - n_a)] if n_a < n + 1 else [])
    files = []
    for j, (a, cnt) in enumerate(pieces):
        f = dest.with_name(f"{dest.stem}-{j}.nut")
        r = subprocess.run([*job_prio(), "ffmpeg", "-hide_banner", "-v", "error", "-y", *bg_threads(), *(["-ss", f"{max(0.0, a / sfps - 0.5 / sfps):.6f}"] if a > 0 else []), "-i", video,
                            "-map", "0:v:0", "-an", "-vf", ",".join(bake_geometry(bp) + [f"setpts=N/({sfps:.9f}*TB)"]), "-frames:v", str(cnt), "-c:v", "ffv1",
                            "-fps_mode", "passthrough", *tags, str(f)], stdin=subprocess.DEVNULL, capture_output=True)
        if r.returncode != 0 or not f.exists():
            return False
        files.append(f)
    if len(files) == 1:
        os.replace(files[0], dest)
        return True
    lst = dest.with_name(dest.stem + "-list.txt")
    lst.write_text("".join(f"file '{f}'\n" for f in files))
    r = subprocess.run(["ffmpeg", "-hide_banner", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(lst), "-map", "0:v:0", "-c", "copy", str(dest)],
                       stdin=subprocess.DEVNULL, capture_output=True)
    for f in files + [lst]:
        f.unlink(missing_ok=True)
    return r.returncode == 0 and dest.exists()


def burst_plans(bp, rp, sg):
    """(n_e, n_p, n_w, bb, bp_in, bw) of a burst segment: source frames of the ease-in / full-speed stretch / wind-down, the plan of
    its plain stretch and the curve plans of the ease-in and the wind-down (None when absent), on the burst's own source clip
    (frame 0 = source frame i_s; "orig" maps back to the original's frames, for the bake's RIFE stage)."""
    sfps, F = bp["sfps"], bp["F"]
    n_e = round(sg["E"] / 2 * sfps) if sg["E"] >= 0.2 else 0
    n_w = round(sg["W"] / 2 * sfps) if sg["W"] > 0 else 0
    n_p = max(0, sg["n"] - n_e - n_w)
    bb = dict(bp, scale=False, fps=(bp["F"] if bp.get("f_cap") else None), curve=None, orig=(sg["i_s"], rp["L_f"]))   # (the plain stretch obeys the level 5.2 cap too)
    bp_in = bw = None
    if n_e:
        n_in = max(2, round(2 * n_e / sfps * F))
        bp_in = dict(bb, curve="in", play=0.0, last=n_e / sfps, N=n_in, k_end=n_in, n_in=n_in, rife_part=("e", sg["i_s"], sg["n"]))
    if n_w:
        bw = dict(bb, play=(n_e + n_p) / sfps, last=sg["n"] / sfps, N=max(2, round(2 * n_w / sfps * F)), wind=sg["W"], rife_part=("w", sg["i_s"], sg["n"]))
    return n_e, n_p, n_w, bb, bp_in, bw


def bake_rife_plan(bp, rp, segs, wind):
    """[(part id, frames)] of every RIFE curve part of a bake, in the order bake_encode encodes them: the first wind, per new burst
    its ease-in and wind-down, the ease-in again for every fade (bake_fade_part)."""
    plan, seen = [], set()
    if wind:
        plan.append(("w1", rife_part_frames(bp)))
    for j, sg in enumerate(segs):
        _, _, _, _, bi, bw = burst_plans(bp, rp, sg)
        if (sg["i_s"], sg["n"]) not in seen:
            seen.add((sg["i_s"], sg["n"]))
            plan += [(x["rife_part"], rife_part_frames(x)) for x in (bi, bw) if x]
        if sg["fade"] is not None and bi:
            plan.append((("f", j), rife_part_frames(bi)))
    return plan


def bake_burst_parts(video, bp, rp, sg, tmpd, label, lo, hi):
    """Encode one burst (ease-in, full-speed stretch, wind-down): {ease [parts], plain [part], wind [parts], src (its source NUT,
    made only when something reads it), bp_in (the ease-in plan, for the fade's PNGs)}. None on failure."""
    sfps, F = bp["sfps"], bp["F"]
    tmpd.mkdir(parents=True, exist_ok=True)
    src = tmpd / "src.nut"

    def src_fn():   # the burst's lossless source clip: the plain stretch, minterpolate and the fallback of a failed RIFE stage read it
        if not src.exists() and not bake_src_clip(video, bp, sg["i_s"], sg["n"], rp, src):
            return None
        return str(src)
    n_e, n_p, n_w, bb, bp_in, bw = burst_plans(bp, rp, sg)
    if not bp.get("store") and not src_fn():
        return None
    out = {"ease": [], "plain": [], "wind": [], "src": src, "bp_in": None, "src_fn": src_fn}
    w = [0.0 if not n_e else 2 * n_e / sfps * F, n_p / sfps * 4, 0.0 if not n_w else 2 * n_w / sfps * F]
    tot = sum(w) or 1.0
    cuts = [lo, lo + (hi - lo) * w[0] / tot, lo + (hi - lo) * (w[0] + w[1]) / tot, hi]
    if bp_in:
        out["bp_in"] = dict(bp_in, src_fn=src_fn)
        out["ease"] = bake_wind_for(str(src), dict(out["bp_in"], pct=(round(cuts[0]), round(cuts[1]))), tmpd / "ease", label)
        if not out["ease"]:
            return None
    if n_p:
        part = tmpd / "plain.mp4"
        if not src_fn():
            return None
        if bake_part_a(str(src), bb, n_e, (n_e + n_p) / sfps, part, label, round(cuts[1]), round(cuts[2])):
            out["plain"] = [part]
    if bw:
        out["wind"] = bake_wind_for(str(src), dict(bw, src_fn=src_fn, pct=(round(cuts[2]), round(cuts[3]))), tmpd / "wind", label)
        if not out["wind"]:
            return None
    return out


def bake_fade_part(video, bp, base, sg, tmpd, label, lo, hi, j=None):
    """The fade-in of a burst that follows a jump: frame i = the held frame sg["fade"] blended with the burst's own ease-in
    frame i (the clip is already moving under the fade, so it ends without a pause), eased weight (1 - cos(pi i / n)) / 2
    (frame 0 = the held frame exactly). [part] or None."""
    F, sfps = bp["F"], bp["sfps"]
    bi = base["bp_in"]
    if not bi:
        return None
    n_in = bi["n_in"]
    td = tmpd / "fade"
    (td / "u").mkdir(parents=True)
    epng = td / "e"
    if not bake_pngs(str(base["src"]), dict(bi, pct=(lo, lo), rife_part=("f", j)), epng):
        return None
    h = td / "H.png"
    if not bake_png(video, bp, max(0.0, sg["fade"] / sfps - 0.5 / sfps), h):
        return None
    for i in range(n_in):
        os.symlink(epng / f"{i:05d}.png", td / "u" / f"{i + 1:05d}.png")
    w = f"(0.5-0.5*cos(PI*N/{n_in}))"
    sc, tags = bake_rgb_down(video)
    fc = f"[0:v][1:v]blend=all_expr='A*(1-{w})+B*{w}',{sc}"
    ins = ["-loop", "1", "-framerate", str(F), "-i", str(h), "-framerate", str(F), "-i", str(td / "u" / "%05d.png")]
    part = tmpd / "fade.mp4"
    ok = ff_encode(ins, [], part, n_in / F, label, pct=(lo, hi), out_args=["-frames:v", str(n_in), *tags], cfr=False, fc=fc)
    return [part] if ok else None


def bake_wind_rife(video, bp, tmpd, label):
    """Curve part through RIFE: output frame k = RIFE(source i, i + 1, step j / RIFE_G) or a plain source frame (rife_frames), so
    the last frame is exactly the still. The frames come from the bake's RifeStore (bp["store"], part bp["rife_part"]); a part
    without one gets a store of its own on `video`. None on failure."""
    store, pid = bp.get("store"), bp.get("rife_part")
    lo, hi = bp.get("pct", (10, 99))
    own = None
    if store is None or pid not in store.parts:
        if bp.get("src_fn"):
            video = bp["src_fn"]()
            if not video:
                return None
        pid = "own"
        own = store = RifeStore(video, bp, [(pid, rife_part_frames(dict(bp, orig=None)))], label)
    try:
        paths = store.wait(pid, label, lo)
        if not paths:
            return None
        return rife_encode(paths, store.video, label, tmpd / "w000.mp4", lo, hi, bp["F"], keep=bp.get("keep"))
    finally:
        if own:
            own.close()
        else:
            store.done(pid)


def bake_pngs(video, bp, dest):
    """The frames of a curve part (the replay's ease-in) as PNGs `dest/<k>.png` (k from 0, at the output size, rgb) instead of an
    encode, for the fade that blends them with H. True on success."""
    dest.mkdir(parents=True, exist_ok=True)
    bp = dict(bp, keep=dest)
    if bp["interp"].startswith("rife"):
        wd = dest.parent / (dest.name + "-w")
        wd.mkdir(parents=True, exist_ok=True)
        return bake_wind_rife(video, bp, wd, "") is not None   # keep mode returns [] on success
    ch = bake_chunks(bp, 1)[0]
    ins, vf, _ = bake_chunk_filters(dict(bp, video=video), ch)
    r = subprocess.run(["ffmpeg", "-hide_banner", "-v", "error", "-y", *ins, "-vf", ",".join(vf + [RGB_UP, "format=rgb24"]), "-an", "-fps_mode", "passthrough",
                        "-start_number", "0", str(dest / "%05d.png")], stdin=subprocess.DEVNULL, capture_output=True)
    return r.returncode == 0 and (dest / "00000.png").exists()


def bake_wind_for(video, bp, tmpd, label):
    """Wind-curve part of a plan (the wind, or the replay's ease-in with bp["curve"] == "in") by the plan's interpolator;
    RIFE falls back to minterpolate for the same file. [parts] or None."""
    tmpd.mkdir(parents=True, exist_ok=True)
    parts = (bake_wind_rife if bp["interp"].startswith("rife") else bake_wind_minterp)(video, bp, tmpd, label)
    if not parts and bp["interp"].startswith("rife"):
        print("theme: RIFE failed, falling back to minterpolate", flush=True)
        shutil.rmtree(tmpd, ignore_errors=True)
        tmpd.mkdir(parents=True)
        if bp.get("src_fn"):   # a burst's source clip is only made when something reads it
            video = bp["src_fn"]()
            if not video:
                return None
        parts = bake_wind_minterp(video, dict(bp, interp="minterpolate"), tmpd, label)
    return parts


def bake_part_a(video, bp, start_i, end_t, part, label, lo, hi):
    """Plain part: source frames from index start_i up to media time end_t, the optimized scale / fps. True when written
    or there is nothing to write (None-length part)."""
    sfps = bp["sfps"]
    a0 = start_i / sfps
    if end_t - a0 <= 0.5 / sfps:
        return None
    ins = (["-ss", f"{a0 - 0.5 / sfps:.6f}"] if start_i > 0 else []) + ["-t", f"{end_t - (a0 - 0.5 / sfps if start_i > 0 else 0):.4f}", "-i", video]
    a_vf = bake_geometry(bp) + ([f"fps={bp['fps']}"] if bp["fps"] else [])
    return ff_encode(ins, a_vf, part, end_t - a0, label, pct=(lo, hi), cfr=bool(bp["fps"]))


def bake_dur(path):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)], capture_output=True, text=True)
    try:
        return float(r.stdout.strip())
    except ValueError:
        return 0.0


def bake_encode(video, bp, dest, label):
    """[first play: A1 + wind][burst 0][burst 1] ... -> dest (concat demuxer, stream copy), sidecar {t2, bursts [{start, end,
    ...}], cycle_from, ...}. Every burst starts on the source frame the previous one held (the same frame, a different encode)
    so a replay is seamless; segments with a fade (non-loop restart) reuse the plain / wind parts of the burst they fade into.
    True on success; JobCancelled when stale."""
    tmpd = dest.parent / (".bake-" + dest.stem)
    shutil.rmtree(tmpd, ignore_errors=True)
    tmpd.mkdir(parents=True)
    store = None
    t_start = time.time()
    enc_job(bp["w"], bp["h"], max(bp["F"], bp["fps"] or bp["sfps"]))   # one level for every part (the play part runs at the source / copy rate)
    try:
        sfps, F = bp["sfps"], bp["F"]
        wind = bp["wind"] > 0
        rp = bake_bursts(video, bp)
        segs = rp["segs"]
        if bp["interp"].startswith("rife") and rife_bin() and rife_pick():   # every RIFE frame of the bake, rendered ahead of the encoders
            store = RifeStore(video, bp, bake_rife_plan(bp, rp, segs, wind), label)
            bp = dict(bp, store=store)
        keys = []
        for sg in segs:
            if (sg["i_s"], sg["n"]) not in keys:
                keys.append((sg["i_s"], sg["n"]))
        # progress shares (the interpolated frames dominate)
        cost = lambda sg: (sg["E"] + sg["W"]) * F + sg["P"] * sfps * 0.1
        stages = [("a1", 4.0 if bp["play"] > 1e-6 else 0), ("w1", bp["N"] + 1 if wind else 0)] + [(k, cost(next(g for g in segs if (g["i_s"], g["n"]) == k)) + 1) for k in keys]
        stages += [("fade", 0.0)]
        tot = sum(w for _, w in stages) or 1.0
        rng, acc = {}, 0.0
        for name, w in stages:
            rng[name] = (round(99 * acc / tot), round(99 * (acc + w) / tot))
            acc += w
        seg1 = []
        a1 = tmpd / "a1.mp4"
        if (wind and bp["play"] > 1e-6) or not wind:
            if bake_part_a(video, bp, 0, bp["play"], a1, label, *rng["a1"]):
                seg1.append(a1)
            elif not wind:
                return False
        if wind:
            w1 = bake_wind_for(video, dict(bp, pct=rng["w1"], rife_part="w1"), tmpd / "w1", label)
            if not w1:
                return False
            seg1 += w1
        bases, seg_parts = {}, []
        for j, sg in enumerate(segs):
            key = (sg["i_s"], sg["n"])
            if key not in bases:
                bases[key] = bake_burst_parts(video, bp, rp, sg, tmpd / f"b{len(bases)}", label, *rng[key])
                if bases[key] is None:
                    return False
            b = bases[key]
            if sg["fade"] is None:
                parts = b["ease"] + b["plain"] + b["wind"]
            else:
                fp = bake_fade_part(video, bp, b, sg, tmpd / f"f{j}", label, *rng["fade"], j=j)
                if not fp:
                    return False
                parts = fp + b["plain"] + b["wind"]
            seg_parts.append(parts)
            if not any(g["fade"] is not None and (g["i_s"], g["n"]) == key for g in segs[j + 1:]):
                Path(b["src"]).unlink(missing_ok=True)   # the burst's lossless source is only needed until its last fade
        files = seg1 + [p for ps in seg_parts for p in ps]
        if not seg1 or not seg_parts:
            return False
        t2 = sum(bake_dur(p) for p in seg1)
        starts, cur = [], t2
        for ps in seg_parts:
            starts.append(cur)
            cur += sum(bake_dur(p) for p in ps)
        (tmpd / "list.txt").write_text("".join(f"file '{p}'\n" for p in files))
        out = tmpd / "out.mp4"
        r = subprocess.run(["ffmpeg", "-hide_banner", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(tmpd / "list.txt"), "-map", "0:v:0", "-c", "copy",
                            "-video_track_timescale", "90000", "-movflags", "+faststart", "-f", "mp4", str(out)], stdin=subprocess.DEVNULL, capture_output=True)
        if r.returncode != 0 or not out.exists() or not out.stat().st_size:
            return False
        os.replace(out, dest)
        bursts = [{"start": round(starts[i], 4), "end": round(starts[i + 1] if i + 1 < len(starts) else cur, 4), "i_s": sg["i_s"], "n": sg["n"], "fade": sg["fade"]}
                  for i, sg in enumerate(segs)]
        write_atomic(dest.with_suffix(".json"), json.dumps({"t2": round(t2, 4), "bursts": bursts, "cycle_from": rp["cycle_from"], "d": round(rp["d"], 3), "text": rp["text"],
                                                          "loop": rp["loop"], "tag": dest.stem[-10:]}))
        print(f"theme: replay bursts of {Path(video).name}: {rp['text']} [{len(segs)} segments, {cur - t2:.0f} s of slow motion, {'loop' if rp['loop'] else 'non-loop'}"
              + (f", cycle restarts at {rp['cycle_from']}" if rp["cycle_from"] else "") + "]", flush=True)
        if bp.get("f_cap"):
            print(f"theme: {bp['w']}x{bp['h']} at the source rate exceeds {out_codec().upper()} level {enc_level()}: baked at {F} fps", flush=True)
        if store:
            print(f"theme: {store.summary()} (from the RIFE plan at {store.t0 - t_start:.1f} s), whole bake {time.time() - t_start:.1f} s", flush=True)
        try:
            lv = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=profile,level", "-of", "csv=p=0", str(dest)],
                                capture_output=True, text=True, timeout=20).stdout.strip()
            print(f"theme: {dest.name}: {out_codec().upper()} profile,level {lv}", flush=True)
        except (OSError, subprocess.TimeoutExpired):
            pass
        return True
    finally:
        if store:
            store.close()
        shutil.rmtree(tmpd, ignore_errors=True)


def prio_read():
    try:
        d = json.loads((vp_dir() / "optimize.prio").read_text())
        return [c for c in d if isinstance(c, str)] if isinstance(d, list) else []
    except (OSError, ValueError):
        return []


def prio_push(conns):
    """Monitors whose entry just changed go first in the encode queue (most recent first)."""
    cur = [c for c in prio_read() if c not in conns]
    write_atomic(vp_dir() / "optimize.prio", json.dumps((list(conns) + cur)[:8]))


def opt_job_list(st=None, mons=None, pending=True):
    """[{dest, video, plan, conns, kind, pw}] for what the monitors play now: the plain optimized copies (quick), then
    the baked wind-downs (kind "bake", slow). pending=True: only those still to encode. Jobs of the monitors changed most
    recently come first. pw = the (play, wind) of the entry, so a finished bake only reaches players that still run it."""
    st = st or load_wp_state()
    if not st["optimize"]:
        return []
    mons = connected_monitors() if mons is None else mons
    jobs = {}
    def add(dest, video, plan, conn, kind, pw):
        if pending and (dest.exists() and dest.stat().st_size or dest.with_suffix(".fail").exists()):
            return
        j = jobs.setdefault(dest, {"dest": dest, "video": video, "plan": plan, "conns": [], "kind": kind, "pw": pw})
        j["conns"].append(conn)
    for conn, (video, mode, play, wind, ease) in video_wanted(st, mons).items():
        mon = next((m for m in mons if m["name"] == conn), None)
        bp = bake_plan(video, mon, play, wind, ease) if BAKE and mode == "once" else None
        plan = opt_plan(video, mon)
        if pending and bp and bake_path(video, bp).exists():
            continue   # the player starts on the baked file: the plain copy would never be used for this entry
        if plan:
            add(opt_path(video, plan), video, plan, conn, "opt", (play, wind, ease))
        if bp:
            add(bake_path(video, bp), video, bp, conn, "bake", (play, wind, ease))
    prio = prio_read()
    rank = lambda j: min((prio.index(c) for c in j["conns"] if c in prio), default=99)
    return sorted(jobs.values(), key=lambda j: (rank(j), j["kind"] == "bake"))


def opt_jobs(st=None, mons=None):
    return opt_job_list(st, mons, pending=True)


def opt_wanted(st=None, mons=None):
    """{dest: job} of every file the monitors want right now (existing or not): what a running encode is checked against."""
    return {j["dest"]: j for j in opt_job_list(st, mons, pending=False)}


def opt_trim():
    """Keep the opt cache under OPT_CACHE_MB: delete the least recently used copies first."""
    d = video_cache() / "opt"
    for stale in list(d.glob(".bake-*")) + list(d.glob(".rife-*")) + list(d.glob(".tmp-*")) if d.exists() else []:
        try:   # leftovers of an interrupted encode (older than a day: a runner may be writing the fresh ones)
            if time.time() - stale.stat().st_mtime > 86400:
                shutil.rmtree(stale, ignore_errors=True) if stale.is_dir() else stale.unlink(missing_ok=True)
        except OSError:
            pass
    files = sorted((f for f in d.glob("*.mp4")), key=lambda f: f.stat().st_mtime) if d.exists() else []
    total = sum(f.stat().st_size for f in files)
    cap = OPT_CACHE_MB * 1024 * 1024
    while files and total > cap:
        f = files.pop(0)
        total -= f.stat().st_size
        f.unlink(missing_ok=True)


def opt_runner_pid():
    """Pid of the running encode runner (pid file + /proc cmdline check), or None."""
    try:
        pid = int((vp_dir() / "optimize.pid").read_text())
        return pid if b"optimize-run" in Path(f"/proc/{pid}/cmdline").read_bytes() else None
    except (OSError, ValueError):
        return None


def video_optimize_run():
    """Encode the missing copies, one at a time (a flock keeps a second runner out), tell running players to swap. A
    state change pokes it (SIGUSR1): a running job whose file is no longer wanted is killed at once (JobCancelled),
    and the next job (the changed monitor's first) starts."""
    import fcntl
    import signal
    with open(vp_dir() / "optimize.lock", "w") as lk:
        try:
            fcntl.flock(lk, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return
        _RUN["speed"] = load_wp_state()["optimize_speed"]
        signal.signal(signal.SIGUSR1, lambda *_: _RUN.update(poked=True, repri=True))   # before the pid is published

        def die(*_):   # stopped (logout, restart of the shell session): take our ffmpegs with us, no orphans
            with _RUN["lock"]:
                procs = list(_RUN["procs"])
            procs_kill(procs)
            ram_cleanup()
            (vp_dir() / "optimize.pid").unlink(missing_ok=True)
            try:
                opt_status(state="idle", pct=0, pid=0)
            except OSError:
                pass
            os._exit(0)
        signal.signal(signal.SIGTERM, die)
        signal.signal(signal.SIGINT, die)
        write_atomic(vp_dir() / "optimize.pid", str(os.getpid()))
        done = 0
        while load_wp_state()["optimize"]:
            if _RUN.pop("repri", False):
                opt_speed_refresh()
            jobs = opt_jobs()
            if not jobs:
                break
            job = jobs[0]
            dest, video, plan, conns, kind = job["dest"], job["video"], job["plan"], job["conns"], job["kind"]
            what = ("wind-down + replay " if plan["wind"] > 0 else "replay ") if kind == "bake" else ""
            label = f"{Path(video).name} {what}for {', '.join(conns)}"
            if any(not (vp_read(vp_dir() / f"{c}.json") and vp_alive((vp_read(vp_dir() / f"{c}.json") or {}).get("pid", -1))) for c in conns):
                label += " (playback starts when ready)"   # nothing plays on those monitors yet: the original cannot be decoded in hardware
            opt_status(state="encoding", label=label, pct=0, kind=kind)
            with _RUN["lock"]:
                _RUN.update(dest=dest, cancel=False)
            t0 = time.time()
            try:
                ok = bake_encode(video, plan, dest, label) if kind == "bake" else opt_encode(video, plan, dest, label)
            except JobCancelled:
                print(f"theme: cancelled {label}: no longer wanted (killed after {time.time() - t0:.1f} s)", flush=True)
                continue
            finally:
                with _RUN["lock"]:
                    _RUN.update(dest=None)
            if not ok:
                dest.with_suffix(".fail").write_text("encode failed\n")
                continue
            done += 1
            print(f"theme: optimized {label}: {dest.name} {dest.stat().st_size / 1e6:.1f} MB in {time.time() - t0:.1f} s", flush=True)
            try:
                still = opt_wanted().get(dest)   # re-check the key: a finished stale job must never swap in
            except Exception:   # noqa: BLE001
                still = None
            for conn in (still["conns"] if still else []):
                d = vp_read(vp_dir() / f"{conn}.json")
                if not (d and vp_alive(d.get("pid", -1))):   # waiting for its copy (video_wait_for_copy): start the player now
                    video_sync(only=conn)
                    continue
                if d and d.get("video") == video and vp_alive(d["pid"]) and d.get("file") != str(dest) \
                        and ((kind == "opt" and not d.get("baked")) or (kind == "bake" and (d.get("play"), d.get("wind", 0), d.get("ease")) == job["pw"])):
                    vp_ipc(conn, "script-message", "swap", str(dest), *(["baked", bursts_arg(bake_side(dest)), str(bake_side(dest).get("cycle_from", 0)), str(bake_side(dest).get("tag", "")),
                                                                         str(vp_dir() / (conn + ".station"))] if kind == "bake" else []))
                    d["file"] = str(dest)
                    d["baked"] = kind == "bake"
                    d["t2"] = bake_side(dest).get("t2", 0.0) if kind == "bake" else 0.0
                    write_atomic(vp_dir() / f"{conn}.json", json.dumps(d))
        (vp_dir() / "optimize.prio").unlink(missing_ok=True)
        (vp_dir() / "optimize.pid").unlink(missing_ok=True)
        opt_status(state="idle", pct=100 if done else 0)
        opt_trim()


def video_optimize_poke():
    """An entry changed (state saved, players not yet restarted): the monitors whose player runs something else go first
    in the queue, and a running encode is told to re-check what is wanted (it kills a stale job within ~0.5 s)."""
    import signal
    try:
        st, mons = load_wp_state(), connected_monitors()
        changed = []
        for conn, spec in video_wanted(st, mons).items():
            d = vp_read(vp_dir() / f"{conn}.json")
            if not d or (d.get("video"), d.get("mode"), d.get("play"), d.get("wind", 0), d.get("ease")) != spec:
                changed.append(conn)
        if changed:
            prio_push(changed)
        pid = opt_runner_pid()
        if pid:
            os.kill(pid, signal.SIGUSR1)
        else:
            video_optimize_kick()
    except OSError:
        pass


def opt_reap_stale():
    """A killed runner (SIGKILL, crash) leaves optimize.json on "encoding" and a stale priority list: with no runner alive, say idle."""
    try:
        if opt_runner_pid():
            return
        d = json.loads((vp_dir() / "optimize.json").read_text())
        if d.get("state") != "idle":
            opt_status(state="idle", pct=0, pid=0)
        (vp_dir() / "optimize.prio").unlink(missing_ok=True)
        (vp_dir() / "optimize.pid").unlink(missing_ok=True)
    except (OSError, ValueError):
        pass


def video_optimize_kick():
    """Start the background runner (detached) when copies are missing and none runs."""
    opt_reap_stale()
    try:
        if not load_wp_state()["optimize"] or opt_runner_pid() or not opt_jobs():
            return
        log = open(vp_dir() / "optimize.log", "a")
        subprocess.Popen([sys.executable, "-I", str(Path(__file__).resolve()), "video", "optimize-run"], stdin=subprocess.DEVNULL,
                         stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    except OSError:
        pass


def vp_dir():
    d = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/theme-{os.getuid()}") / "theme-video"
    d.mkdir(parents=True, exist_ok=True)
    return d


def vp_alive(pid):
    try:
        return Path(f"/proc/{pid}/comm").read_text().strip() == "mpvpaper"
    except (OSError, ValueError):
        return False


def vp_read(f):
    try:
        d = json.loads(f.read_text())
        return d if isinstance(d, dict) and isinstance(d.get("pid"), int) else None
    except (OSError, ValueError):
        return None


def vp_stop(f):
    """Stop the player of one pid file: SIGTERM the recorded pid (only if it is still an mpvpaper), SIGKILL after 2 s."""
    import signal
    d = vp_read(f)
    f.unlink(missing_ok=True)
    if not d or not vp_alive(d["pid"]):
        return
    for sig, wait in ((signal.SIGTERM, 2.0), (signal.SIGKILL, 1.0)):
        try:
            os.kill(d["pid"], sig)
        except OSError:
            return
        end = time.time() + wait
        while time.time() < end and vp_alive(d["pid"]):
            time.sleep(0.05)
        if not vp_alive(d["pid"]):
            return


def vp_start(conn, video, mode, play=None, wind=0, src=None, baked=None, ease=None):
    """`video` = the wanted file (what the pid file records), `src` = the file to play (the monitor's optimized copy
    when it exists, else the same). `baked` = the plan (+ `t2`) of the baked once file `src` is: its first segment is the
    first play (mpv `end=t2` holds its last frame), the second one (from t2) the replay."""
    f = vp_dir() / f"{conn}.json"
    log = open(vp_dir() / f"mpvpaper-{conn}.log", "w")
    opts = MPV_OPTS[mode]
    plan = video_plan(video, play, wind) if mode == "once" else None
    # control socket (replay, file swap) + the script (wind-down, replay, swap); mpvpaper splits the options on spaces
    if " " not in str(WINDDOWN_LUA) and " " not in str(vp_dir()) and WINDDOWN_LUA.exists():
        opts += f" input-ipc-server={vp_dir() / (conn + '.sock')} scripts={WINDDOWN_LUA}"
        # baked: the file itself holds the wind (speed 1, no timer, no end=); the script only handles replay / swap
        timed = bool(plan) and not baked
        opts += f" script-opts=winddown-timed={'yes' if timed else 'no'},winddown-play={plan[0] if plan else 0:g}," \
                f"winddown-wind={plan[1] if plan else 0:g},winddown-stop={plan[2] if plan else 0:g}"
        side = baked.get("side", {}) if baked else {}
        if side.get("bursts"):   # the replay bursts: where they start, the cycle, the station file, the file's tag
            opts += f",winddown-bursts={bursts_arg(side)},winddown-cyc={side.get('cycle_from', 0)},winddown-station={vp_dir() / (conn + '.station')},winddown-tag={side.get('tag', '')}"
        if WINDDOWN_SMOOTH and timed and plan[1] > 0:
            hz = next((m["hz"] for m in connected_monitors() if m["name"] == conn), 0.0)
            if 24 <= hz <= WINDDOWN_SMOOTH_MAX_HZ:
                opts += f",winddown-smooth=yes,winddown-fps={round(hz)}"
        opts += ",winddown-loop=yes" if mode == "loop" else ""
    if mode == "once" and not baked:
        hold = plan[2] if plan else video_hold(video)
        if hold is not None:
            opts += f" end={hold:.3f}"
    side = baked.get("side", {}) if baked else {}
    bursts, t2 = side.get("bursts") or [], (baked.get("t2", 0.0) if baked else 0.0)
    if bursts:
        # a player restart resumes the STATION (held on the frame the last burst ended on) instead of replaying the first play;
        # a new bake / a reboot (the station file lives in the per-login runtime dir) starts with the first play, held on H
        st, resume = vp_dir() / f"{conn}.station", 0
        try:
            tg, _, ix = st.read_text().strip().rpartition(":")
            if tg == side.get("tag") and ix.isdigit() and 0 < int(ix) < len(bursts):
                resume = int(ix)
        except OSError:
            pass
        if resume:
            opts += f" start={bursts[resume]['start'] - 0.002:.4f} pause=yes end={bursts[resume]['start']:.4f}"
        else:
            st.unlink(missing_ok=True)
            opts += f" end={bursts[0]['start']:.4f}"   # the first play stops on H where burst 0 starts (end= is exclusive)
    # bottom layer, not background: hyprpaper shares the background layer and can map after the player (a 4K still
    # decodes slower than mpvpaper starts), which hid the video behind the still; bottom is above it, below all windows
    pr = subprocess.Popen(["mpvpaper", "-l", "bottom", "-o", opts, conn, src or video], stdin=subprocess.DEVNULL, stdout=log,
                          stderr=subprocess.STDOUT, start_new_session=True)
    write_atomic(f, json.dumps({"pid": pr.pid, "video": video, "mode": mode, "play": play, "wind": wind, "file": src or video, "baked": bool(baked), "t2": t2, "ease": ease}))


CONN_RE = r"[A-Za-z0-9_.-]{1,40}"


def vp_ipc(conn, *cmd):
    """One mpv JSON-IPC command on a play-once player's socket; the reply's `data`, or None (no socket, dead
    player, timeout). The socket path is built from a validated connector name only."""
    import socket
    if not re.fullmatch(CONN_RE, conn or ""):
        return None
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(1.0)
    try:
        s.connect(str(vp_dir() / f"{conn}.sock"))
        s.sendall((json.dumps({"command": list(cmd), "request_id": 7}) + "\n").encode())
        buf = b""
        while True:   # events may be interleaved with the reply
            chunk = s.recv(4096)
            if not chunk:
                return None
            buf += chunk
            for line in buf.split(b"\n"):
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if r.get("request_id") == 7:
                    return r.get("data") if r.get("error") == "success" else None
    except (OSError, ValueError):
        return None
    finally:
        s.close()


def video_replay(conn):
    """Replay a play-once clip that has stopped (held frame) with the same timing; one that is still playing or
    winding down is left alone, so a burst of workspace switches cannot stack restarts. True when restarted.
    The one implementation is mpv/replay.py (the workspace-switch hot path runs it directly: ~5 ms instead of ~50)."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("theme_replay", ROOT / "mpv" / "replay.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.replay(conn or "")


def video_wanted(st=None, mons=None):
    """{connector: (video file, mode, play, wind, ease)} for every connected monitor that should play one (ease None = default)."""
    st = st or load_wp_state()
    mons = connected_monitors() if mons is None else mons
    if not st["primary_video"] and not any(isinstance(e, dict) for e in st["monitors"].values()):
        return {}
    prim, res = primary_key(st, mons), {}
    for m in mons:
        ent = st["primary_video"] if m["key"] == prim else st["monitors"].get(m["key"], st["primary_video"])
        if isinstance(ent, dict) and os.path.exists(os.path.expanduser(ent["video"])):
            res[m["name"]] = (os.path.expanduser(ent["video"]), ent["mode"], ent.get("play"), ent.get("wind", 0), ent.get("ease"))
    return res


def video_wait_for_copy(video, mon, st_opt, src):
    """True when the ORIGINAL must not be played yet: "Optimize for monitor" is on, the monitor's optimized copy does not exist (and did not
    fail), and the original cannot be decoded in hardware here (software decoding of e.g. 4K 120 fps AV1 would hammer the CPU). The
    still stays up (hyprpaper); the runner starts the player when the copy is ready."""
    if src or not st_opt or hwdec_ok(video):
        return False
    plan = opt_plan(video, mon)
    return bool(plan) and not opt_path(video, plan).with_suffix(".fail").exists()


def video_sync(start=True, force=False, only=None, wait=False):
    """Make the running players match the state: stop those no longer wanted (or all of them with force), start
    the missing ones. start=False only stops (the caller restarts them). only = one connector."""
    import fcntl
    mons = connected_monitors()
    want = video_wanted(mons=mons) if mons else {}
    st_opt = load_wp_state()["optimize"]
    waiting = False
    with open(vp_dir() / "lock", "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        have = {f.stem: f for f in vp_dir().glob("*.json")}
        for conn, f in have.items():
            d = vp_read(f) or {}
            if only and conn != only:
                continue
            if force or conn not in want or not vp_alive(d.get("pid", -1)) or (d.get("video"), d.get("mode"), d.get("play"), d.get("wind", 0), d.get("ease")) != want[conn]:
                vp_stop(f)
        if not start or not want:
            return
        if wait:   # at login: hyprpaper first, so the video layer maps above it
            for _ in range(60):
                if hyprpaper_active():
                    break
                time.sleep(0.25)
        for conn, (video, mode, play, wind, ease) in want.items():
            if (only and conn != only) or not shutil.which("mpvpaper"):
                continue
            f = vp_dir() / f"{conn}.json"
            d = vp_read(f)
            if not (d and vp_alive(d["pid"])):
                mon = next((m for m in mons if m["name"] == conn), None)
                src = baked = None
                if st_opt:
                    baked = bake_cached(video, mon, play, wind, ease) if BAKE and mode == "once" else None   # (file, plan)
                    src = baked[0] if baked else opt_cached(video, mon)
                if video_wait_for_copy(video, mon, st_opt, src):
                    print(f"theme: {conn}: {Path(video).name} has no hardware decoding here: the still stays until its optimized copy ({out_codec().upper()}) is ready", flush=True)
                    waiting = True
                    continue
                if not st_opt and not src and not hwdec_ok(video):
                    print(f"theme: warning: {conn}: {Path(video).name} cannot be decoded in hardware and Optimize is off: playing it in software (high CPU)", file=sys.stderr, flush=True)
                vp_start(conn, video, mode, play, wind, str(src) if src else None, baked[1] if baked else None, ease)
    if start and want and st_opt and (not only or waiting):
        video_optimize_kick()


def video_command(args):
    """video start|stop|restart|sync [key] | replay <connector> | optimize [on|off] | thumb <file> | thumbs <file>... | status"""
    sub, rest = (args[0] if args else "sync"), args[1:]
    if sub == "replay":   # no monitor query; the workspace-switch hot path runs mpv/replay.py itself
        if rest:
            video_replay(rest[0])
        return
    mons = connected_monitors()
    only = None
    if sub in ("start", "stop", "restart") and rest:
        only = next((m["name"] for m in mons if rest[0] in (m["key"], m["name"])), rest[0])
    if sub in ("start", "sync"):
        video_sync(only=only, wait=True)
    elif sub == "restart":
        video_sync(force=True, only=only, wait=True)
    elif sub == "optimize-run":
        video_optimize_run()
    elif sub == "optimize":
        st = load_wp_state()
        if rest[:1] in (["on"], ["off"]):
            st["optimize"] = rest[0] == "on"
            save_wp_state(st)
            video_sync(force=True, wait=True)   # players restart on the copy (on) or the original (off); "on" also encodes
        print("on" if load_wp_state()["optimize"] else "off")
    elif sub == "optimize-speed":   # background | balanced | fast: no player restart, no re-apply; a running encode is re-prioritized at once
        st = load_wp_state()
        if rest[:1] and rest[0] in OPT_SPEEDS:
            st["optimize_speed"] = rest[0]
            save_wp_state(st)
            pid = opt_runner_pid()
            if pid:
                import signal
                os.kill(pid, signal.SIGUSR1)
        print(load_wp_state()["optimize_speed"])
    elif sub == "stop":
        for f in vp_dir().glob("*.json"):
            if not only or f.stem == only:
                vp_stop(f)
    elif sub == "loopinfo":   # <video> <play|full> <wind> [ease] [monitor key|connector]: how its replay works there (cached searches; the Settings read-only line)
        v = os.path.expanduser(rest[0]) if rest else ""
        pl = None if len(rest) < 2 or rest[1] == "full" else rest[1]
        mon = next((m for m in connected_monitors() if rest[4:5] and rest[4] in (m.get("key"), m.get("name"))), None)   # its fps / size decide the burst count
        bp = bake_plan_base(v, mon, pl, rest[2] if len(rest) > 2 else 0, rest[3] if len(rest) > 3 and rest[3] != "" else None) if os.path.exists(v) else None
        if bp:
            print(bake_bursts(v, bp)["text"], flush=True)
    elif sub == "hwdec":   # <video>: "yes <codec>" / "no <codec>" = can this machine decode it in hardware (Settings note when Optimize is off)
        v = os.path.expanduser(rest[0]) if rest else ""
        c = video_codec(v) if os.path.exists(v) else None
        print(("yes " if hwdec_ok(v) else "no ") + (c[0] if c else "?"), flush=True)
    elif sub in ("thumb", "thumbs"):
        for p in rest:
            t = video_thumb(os.path.expanduser(p))
            # path, thumbnail, usable whole seconds (Play for + Wind down sliders), the wind curve's mean speed
            print(f"{p}\t{t or ''}\t{video_usable(os.path.expanduser(p))}\t{WIND_AVG}\t{bake_ease_default()}", flush=True)
    elif sub == "status":
        for f in sorted(vp_dir().glob("*.json")):
            if f.name == "optimize.json":
                continue
            d = vp_read(f) or {}
            print(f"{f.stem}: pid {d.get('pid')} {'alive' if vp_alive(d.get('pid', -1)) else 'dead'} {d.get('mode')} {d.get('video')}")
        opt_reap_stale()
        rp = opt_runner_pid()
        try:
            ost = json.loads((vp_dir() / "optimize.json").read_text())
        except (OSError, ValueError):
            ost = {}
        print(f"optimize runner: {'pid ' + str(rp) + ' alive' if rp else 'not running'}, state {ost.get('state', '?')}" + (f" {ost.get('pct')} %" if rp else ""))
    else:
        sys.exit("theme: video start|stop|restart|sync [key] | replay <connector> | optimize [on|off] | thumb <file> | thumbs <file>... | status")


# ---- light mode: bar text straight on the wallpaper ----
# A bar without a backdrop (Settings > Bar "transparent when flush") draws its text on the wallpaper, which the mode does
# not change: dark text from the light palette is unreadable on a dark wallpaper. palette.json (light mode) therefore
# carries the dark palette's text colours ("dark", INK_KEYS) and, per monitor and bar edge, which of the two reads
# better on the wallpaper strip under the bar ("wall_ink": "light" = the light palette, "dark" = the dark one).
INK_KEYS = ("bg", "fg", "fg_dim", "muted", "accent", "accent2", "red", "green", "yellow", "overlay")
INK_STRIP = 0.035   # strip height under a bar, as a fraction of the screen height (a 40 px bar on 1440 px is 2.8 %)


def strip_inks(path, pal, dark):
    """{"top": ink, "bottom": ink} for one wallpaper (cover-cropped to 16:9, like hyprpaper's fit_mode = cover): the
    palette whose fg keeps the better contrast over the darkest / brightest tenth of the strip ("light" or "dark")."""
    w, h = 320, 180
    rows = max(2, round(h * INK_STRIP))
    try:
        raw = subprocess.run(["magick", f"{path}[0]", "-auto-orient", "-background", "black", "-alpha", "remove",
                              "-colorspace", "sRGB", "-resize", f"{w}x{h}^", "-gravity", "center", "-extent", f"{w}x{h}",
                              "-depth", "8", "rgb:-"], check=True, capture_output=True, timeout=30).stdout
    except (subprocess.SubprocessError, OSError):
        return {"top": "dark", "bottom": "dark"}
    if len(raw) < w * h * 3:
        return {"top": "dark", "bottom": "dark"}
    lin = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    lut = [lin(i / 255) for i in range(256)]

    def lums(y0, y1):
        b = raw[y0 * w * 3:y1 * w * 3]
        return [0.2126 * lut[b[i]] + 0.7152 * lut[b[i + 1]] + 0.0722 * lut[b[i + 2]] for i in range(0, len(b) - 2, 3)]

    def pick(ls):
        ls.sort()
        q = lambda f: ls[min(len(ls) - 1, int(len(ls) * f))]
        ratio = lambda fg, l: (max(luminance(fg), l) + 0.05) / (min(luminance(fg), l) + 0.05)
        # light ink (dark text) suffers on the darkest pixels, dark ink (light text) on the brightest
        return "light" if ratio(pal["fg"], q(0.1)) >= ratio(dark["fg"], q(0.9)) else "dark"
    return {"top": pick(lums(0, rows)), "bottom": pick(lums(h - rows, h))}


def wall_inks(wp, pal, dark):
    """{"*": inks of the primary wallpaper, "<connector>": inks of a monitor with its own wallpaper} (strip_inks).
    A video wallpaper is judged by its still."""
    res = {"*": strip_inks(wp, pal, dark)}
    try:
        ents = monitor_entries()
    except Exception:   # no state / no hyprctl: the primary is all there is
        ents = []
    for _, conn, path in ents:
        if conn:
            res[conn] = strip_inks(path, pal, dark)
    return res


def glass_file():
    """Settings > Glass state (Quickshell GlassTuneCtl, read by hypr/hyprland/managed.lua)."""
    if os.environ.get("GLASS_FILE"):
        return Path(os.environ["GLASS_FILE"])
    return Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state") / "quickshell" / "glass.json"


def migrate_glass_modes():
    """One-time split of glass.json into per-mode sets (managed.lua: top-level = dark, "light" object = light). The
    existing values stay the dark ones untouched; the light set starts as a copy of them, except tint / darkening:
    darkening off and the tint mirrored (alpha = 1 - (1 - tint alpha) * (1 - darkening), colour from the palette bg via
    tint_from_bg). Without both tint and darkening saved, those two are left to managed.lua's light default."""
    f = glass_file()
    try:
        d = json.loads(f.read_text())
    except (OSError, ValueError):
        return
    if not isinstance(d, dict) or "light" in d:
        return
    light = {k: v for k, v in d.items() if k not in ("version", "tint", "darkening", "tint_from_bg")
             and isinstance(v, (int, float)) and not isinstance(v, bool)}
    tint, dk = d.get("tint"), d.get("darkening")
    if isinstance(tint, (int, float)) and isinstance(dk, (int, float)):
        a = ((int(tint) >> 24) & 0xFF) / 255
        alpha = max(0, min(255, round((1 - (1 - a) * (1 - max(0.0, min(1.0, dk)))) * 255)))
        light.update(tint=(alpha << 24) | 0xFFFFFF, darkening=0, tint_from_bg=True)
    d["light"] = light
    write_atomic(f, json.dumps(d, separators=(",", ":")) + "\n")


def refresh_wall_ink():
    """Re-judge palette.json's wall_ink (light mode only) after a per-monitor wallpaper change that skips the render."""
    try:
        d = json.loads((OUT / "palette.json").read_text())
    except (OSError, ValueError):
        return
    if d.get("mode") != "light" or not isinstance(d.get("dark"), dict):
        return
    d["wall_ink"] = wall_inks(d["wallpaper"], d, d["dark"])
    write_atomic(OUT / "palette.json", json.dumps(d, indent=2) + "\n")


# per-mode template values: libadwaita shade alphas, the Qt palette's Light / Midlight / Dark roles (lighter / darker than
# the window, so they swap), the color-scheme names apps understand
def mode_extras(pal, mode):
    if mode == "light":
        e = {"shade_a": "0.07", "shade_dark_a": "0.2", "popover_shade_a": "0.07", "scrollbar_outline": "rgba(255, 255, 255, 0.5)",
             "kv_light": pal["bg_alt"], "kv_midlight": pal["bg_alt"], "kv_dark": pal["overlay"]}
    else:
        e = {"shade_a": "0.36", "shade_dark_a": "0.9", "popover_shade_a": "0.25", "scrollbar_outline": "rgba(0, 0, 0, 0.5)",
             "kv_light": pal["overlay"], "kv_midlight": pal["surface2"], "kv_dark": pal["bg"]}
    for k in ("kv_light", "kv_midlight", "kv_dark"):
        e[k + "_bare"] = e[k].lstrip("#")
    e["color_scheme"] = mode
    return e


def render_all(pal, cfg, mode=None, dark=None):
    """dark: the dark palette of the same wallpaper (light mode only): palette.json then also carries its text colours
    and the wallpaper ink (wall_inks) for the bar while it has no backdrop."""
    mode = mode or get_mode()
    OUT.mkdir(parents=True, exist_ok=True)
    if not DEFAULT_MODE:
        HOST_OUT.mkdir(exist_ok=True)
    wp = str(Path(os.path.expanduser(cfg["wallpaper"])))
    if DEFAULT_MODE:   # committed: no absolute home path (bin/theme-seed expands ~/ when it copies into out/)
        wp = tilde(wp)
    extra = {"wallpaper": wp, "home": str(HOME), "out": str(OUT),
             **gtk_glass_alphas(cfg.get("settings", {}), mode=mode), **{k: v for k, v in cfg.get("vars", {}).items()},
             **mode_extras(pal, mode)}
    # Brave GTK mode: active tab title and toolbar icons share one GTK colour (label); brave_tab_text picks it
    extra["brave_label"] = pal["accent"] if cfg.get("settings", {}).get("brave_tab_text", "fg") == "accent" else pal["fg"]
    # a host without the TV wallpaper (it is not in the repo) falls back to the main one instead of a black output
    tv = os.path.expanduser(extra.get("tv_wallpaper", ""))
    if not tv or not os.path.exists(tv):
        extra["tv_wallpaper"] = wp
    # Thunderbird: the shared variable block (tb-vars.css) is rendered once and pasted into userChrome / userContent as {{tb_vars}}
    # Kvantum colours with alpha (kvantum.kvconfig base / alt base / button): Kvantum parses #RRGGBBAA (its own
    # getFromRGBA; the stock themes write e.g. #000000c8), not Qt's #AARRGGBB
    kva = lambda alpha, col: f"#{col.lstrip('#')}{alpha}"
    extra["kv_base_color"] = kva(extra["kv_view_alpha"], pal["bg_alt"])
    extra["kv_alt_base_color"] = kva(extra["kv_view_alpha"], pal["surface"])
    extra["kv_button_color"] = kva(extra["kv_control_alpha"], pal["fg"])
    extra["tb_radius"] = int(cfg.get("settings", {}).get("thunderbird_radius", cfg.get("settings", {}).get("rounding", 0)))
    extra["tb_vars"] = render((ROOT / "tb-vars.css").read_text(), pal, extra)
    # per-monitor wallpapers (empty strings without entries, so the output is unchanged): see monitor_entries()
    if not DEFAULT_MODE:   # (the default is the same for every machine: no per-monitor state)
        extra.update(monitor_extras())
    else:
        extra["monitor_blocks"] = ""
    extra.update(wallpaper_t=tilde(wp), tv_wallpaper_t=tilde(extra["tv_wallpaper"]))   # hyprpaper expands ~
    extra["static_blocks"] = static_blocks(cfg, extra)
    rendered = {}
    for tpl in sorted((ROOT / "templates").iterdir()):
        if tpl.is_dir() or (DEFAULT_MODE and tpl.name in HOST_TEMPLATES):
            continue
        dest = (HOST_OUT if tpl.name in HOST_TEMPLATES else OUT) / tpl.name
        rendered[tpl.name] = render(tpl.read_text(), pal, extra)
        write_atomic(dest, rendered[tpl.name])
    render_omarchy(pal, mode, extra, rendered, wp)
    expand = tilde if DEFAULT_MODE else os.path.expanduser
    dirs = [expand(d) for d in cfg.get("wallpaper_dirs", ["~/Pictures/wallpapers"])]
    s = cfg.get("settings", {})
    # Quickshell layout defaults (palette.json); Settings > Appearance overrides them via appearance.json
    # (never touched here). Hyprland does not read them: its values are hand-written in hypr/hyprland/.
    ui = {"rounding": int(s.get("rounding", 0)), "gap": int(s.get("gap", 0)),
          "border_size": int(s.get("border_size", 2)),
          "bar_floating": bool(s.get("bar_floating", False)),
          "smart_gaps": bool(s.get("smart_gaps", True)),
          "bar_border": s.get("bar_border", 0), "bar_opacity": s.get("bar_opacity", 0.55),
          "card_fill": s.get("card_fill", 0.3), "plain_fill_min": s.get("plain_fill_min", 0)}
    light = {}
    if mode == "light" and dark and not DEFAULT_MODE:
        light = {"dark": {k: dark[k] for k in INK_KEYS}, "wall_ink": wall_inks(wp, pal, dark)}
    write_atomic(OUT / "palette.json", json.dumps({"wallpaper": wp, "wallpaper_dirs": dirs, "video_dirs": [tilde(d) for d in video_dirs(cfg)] if DEFAULT_MODE else video_dirs(cfg), "mode": mode, **ui, **pal, **light}, indent=2) + "\n")
    lua = "return {\n" + f'  wallpaper = "{wp}",\n  rounding = {ui["rounding"]},\n' + "".join(f'  {k} = "{v}",\n' for k, v in pal.items()) + "}\n"
    write_atomic(OUT / "palette.lua", lua)


# ------------------------------------------------------------ Omarchy theme dir
# out/omarchy/ is a complete Omarchy theme (colors.toml + the terminal files whose format matches ours), so Omarchy-
# ecosystem apps that read ~/.local/state/omarchy/current/theme/colors.toml follow the wallpaper. Omarchy derives
# the legacy colorN names and selection_foreground itself, so they are not written. Only the neutral ramp is mapped
# (templates/omarchy/colors.toml); the rest are palette keys.
OMARCHY_NAME = "wallpaper"                      # current/theme.name (Omarchy theme names: [A-Za-z0-9_][A-Za-z0-9._+-]*)
OMARCHY_FILES = {"alacritty.toml": "alacritty.toml", "kitty.conf": "kitty.conf", "ghostty": "ghostty.conf"}
OMARCHY_CURRENT = "~/.local/state/omarchy/current"
# icon set (Yaru accent variants) by accent hue, degrees: (upper bound, name)
YARU_HUES = [(20, "Yaru-red"), (70, "Yaru-yellow"), (100, "Yaru-olive"), (170, "Yaru-sage"), (260, "Yaru-blue"),
             (300, "Yaru-purple"), (340, "Yaru-magenta"), (361, "Yaru-red")]


def omarchy_extras(pal, mode):
    """Values Omarchy needs that the palette has no key for. Offsets follow the stock themes: dark themes shade
    background 25 % / 50 % toward black (tokyo-night), light themes only ~6 % / 12 % (catppuccin-latte); the
    foreground shades go toward white in both (light: bright_foreground stays the foreground, as in latte)."""
    light = mode == "light"
    t1, t2 = (0.06, 0.12) if light else (0.25, 0.50)
    return {"om_dark_background": mix(pal["bg"], "#000000", t1), "om_darker_background": mix(pal["bg"], "#000000", t2),
            "om_light_foreground": mix(pal["fg"], "#ffffff", 0.10),
            "om_bright_foreground": pal["fg"] if light else mix(pal["fg"], "#ffffff", 0.20),
            "om_brown": mix(pal["orange"], "#000000", 0.5)}


def yaru_icons(accent):
    h, _, s = to_hls(accent)
    if s < 0.15:
        return None
    deg = h * 360
    return next(n for hi, n in YARU_HUES if deg < hi)


def render_omarchy(pal, mode, extra, rendered, wp):
    """out/omarchy/: colors.toml + alacritty.toml kitty.conf ghostty.conf (our own outputs, same formats) and, on a host
    render only, backgrounds/ (the wallpaper), preview.png and icons.theme. Skipped (formats Omarchy renders itself
    from its own templates): btop, neovim, helix, vscode, foot, obsidian, ... See README."""
    om = OUT / "omarchy"
    om.mkdir(exist_ok=True)
    x = {**extra, "mode": mode, **omarchy_extras(pal, mode)}
    write_atomic(om / "colors.toml", render((ROOT / "templates/omarchy/colors.toml").read_text(), pal, x))
    for src, name in OMARCHY_FILES.items():
        write_atomic(om / name, rendered[src])
    if DEFAULT_MODE:   # the committed default stays tiny: no image copy (default/wallpaper.jpg is generated)
        return
    icons = yaru_icons(pal["accent"])
    if icons:
        write_atomic(om / "icons.theme", icons + "\n")
    else:
        (om / "icons.theme").unlink(missing_ok=True)
    src = Path(wp)
    if not src.is_file():
        return
    bgd = om / "backgrounds"
    bgd.mkdir(exist_ok=True)
    dst = bgd / ("wallpaper" + (src.suffix.lower() or ".jpg"))
    for f in bgd.iterdir():
        if f != dst:
            f.unlink()
    prev = om / "preview.png"
    if not dst.exists() or dst.stat().st_size != src.stat().st_size or not prev.exists() or prev.stat().st_mtime < src.stat().st_mtime:
        tmp = dst.with_name(".tmp-" + dst.name)
        shutil.copyfile(src, tmp)
        os.replace(tmp, dst)
        ptmp = om / ".tmp-preview.png"
        r = subprocess.run(["magick", str(dst) + "[0]", "-resize", "1280x720^", "-gravity", "center", "-extent", "1280x720", f"PNG:{ptmp}"],
                           capture_output=True)
        if r.returncode == 0:
            os.replace(ptmp, prev)
        else:
            ptmp.unlink(missing_ok=True)


def link_omarchy():
    """~/.local/state/omarchy/current/theme -> out/omarchy (+ theme.name). A real directory there belongs to a real
    Omarchy install and is never touched."""
    cur = Path(os.path.expanduser(OMARCHY_CURRENT))
    dest = cur / "theme"
    if dest.exists() and not dest.is_symlink():
        print(f"theme: {dest} is a real directory (an Omarchy install); not linking out/omarchy there")
        return
    cur.mkdir(parents=True, exist_ok=True)
    src = OUT / "omarchy"
    if not (dest.is_symlink() and dest.resolve() == src.resolve()):
        tmp = cur / ".theme.tmp"
        tmp.unlink(missing_ok=True)
        tmp.symlink_to(src)
        os.replace(tmp, dest)   # atomic swap of the link (a dangling link is replaced too)
    write_atomic(cur / "theme.name", OMARCHY_NAME + "\n")


# --------------------------------------------------------------------- deploy
# Some apps only read fixed paths outside this repo. These helpers put generated
# files there (symlink where the app follows links, copy/inject where it doesn't).
def link(dest, src):
    dest = Path(os.path.expanduser(dest))
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.is_symlink() and dest.resolve() == src.resolve():
        return
    if dest.exists() and not dest.is_symlink():
        dest.rename(dest.with_name(dest.name + ".pre-theme"))  # keep the original once
    if dest.is_symlink():
        dest.unlink()
    dest.symlink_to(src)


def inject(dest, text, name="theme", cm="#"):
    """Replace/insert a marked block inside a file we don't fully own (the tracked herdr base, by `theme.py default`).
    Writes through symlinks."""
    dest = Path(os.path.expanduser(dest)).resolve()
    cur = dest.read_text() if dest.exists() else ""
    new = inject_text(cur, text, name, cm)
    if new != cur:
        dest.write_text(new)


GTK3_DARK_BLUE_HUE = 0.59   # Adwaita's #15539e family: selection, focus rings, suggested-action buttons
GTK3_LIGHT_BLUE_L = 0.55    # the light stylesheet's #3584e4


def recolor_gtk_css(css, pal, mode="dark"):
    """Re-theme GTK's compiled Adwaita stylesheet (dark or light, per `mode`). Its colors are inlined in the rules
    (only a few refer to @named colors), so overriding @define-color alone recolors almost nothing. Greys are
    mapped through anchor points onto the palette's neutral ramp, the blue family follows the accent
    hue, and every other hue (warning/error/success) is left alone."""
    light = mode == "light"
    L = lambda c: to_hls(c)[1]
    bg_h, _, bg_s = to_hls(pal["bg"])
    if light:   # stock light greys: text .20, mid .58, borders .72-.82, bars .93, window .96, base 1.0
        anchors = [
            (0.0, L(pal["fg"]) * 0.5), (0.20, L(pal["fg"])), (0.58, L(pal["muted"])), (0.72, L(pal["overlay"])),
            (0.82, L(pal["surface2"])), (0.93, L(pal["surface"])), (0.96, L(pal["bg"])), (1.0, L(pal["bg_alt"])),
        ]
    else:
        anchors = [
            (0.0, 0.0), (0.106, L(pal["bg"]) * 0.55), (0.176, L(pal["bg"])), (0.208, L(pal["surface"])),
            (0.29, L(pal["surface2"])), (0.57, L(pal["muted"])), (0.80, L(pal["fg_dim"])),
            (0.93, L(pal["fg"])), (1.0, min(1.0, L(pal["fg"]) + 0.08)),
        ]

    def grey(l):
        for (x0, y0), (x1, y1) in zip(anchors, anchors[1:]):
            if l <= x1:
                return y0 + (y1 - y0) * (l - x0) / (x1 - x0 or 1)
        return anchors[-1][1]

    ah, al, asat = to_hls(pal["accent"])
    sat_scale = 0.9 * max(0.0, min(1.0, asat / 0.6))  # a greyscale wallpaper gives greyscale selections

    def sub(m):
        raw = m.group(1)
        if len(raw) == 3:
            raw = "".join(c * 2 for c in raw)
        h, l, s = to_hls("#" + raw)
        if s < 0.12:                                   # neutral
            return hls(bg_h, grey(l), min(bg_s, 0.15))
        if hue_dist(h, GTK3_DARK_BLUE_HUE) <= 0.12:    # accent family
            nl = max(0.05, min(0.95, l + (al - GTK3_LIGHT_BLUE_L))) if light else min(0.7, l + 0.15)
            return hls(ah + (h - GTK3_DARK_BLUE_HUE), nl, s * sat_scale)
        return m.group(0)

    return re.sub(r"#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b", sub, css)


def write_gtk_theme(pal, mode="dark"):
    """A real, named GTK theme. Chromium (Brave's file dialogs) loads the theme by name (GTK_THEME) and
    never applies ~/.config/gtk-3.0/gtk.css, so a user-CSS-only palette left those dialogs in stock
    Adwaita blue/grey. This theme is GTK's own stylesheet (dark or light, per `mode`) recolored with the palette."""
    light = mode == "light"
    variant = "" if light else "-dark"   # Adwaita-dark.css / gtk-contained-dark.css
    root = Path.home() / ".local/share/themes/Wall"
    (root / "gtk-3.0").mkdir(parents=True, exist_ok=True)
    (root / "gtk-4.0").mkdir(parents=True, exist_ok=True)
    stock = run_out(["gresource", "extract", "/usr/lib/libgtk-3.so.0",
                     f"/org/gtk/libgtk/theme/Adwaita/gtk-contained{variant}.css"])  # glib2-devel + gtk3
    if stock:
        css3 = recolor_gtk_css(stock, pal, mode) + f'\n@import url("file://{OUT}/gtk.css");\n'
    else:  # no gresource tool: fall back to the named-colors-only version
        css3 = (f'@import url("resource:///org/gtk/libgtk/theme/Adwaita/gtk-contained{variant}.css");\n'
                f'@import url("file://{OUT}/gtk.css");\n')
    write_atomic(root / "gtk-3.0/gtk.css", css3)
    write_atomic(root / "gtk-4.0/gtk.css",
                 f'@import url("resource:///org/gtk/libgtk/theme/Adwaita/Adwaita{variant}.css");\n@import url("file://{OUT}/gtk.css");\n')
    (root / "index.theme").write_text(
        "[Desktop Entry]\nType=X-GNOME-Metatheme\nName=Wall\n"
        f"Comment=GTK {mode} theme recolored with the wallpaper palette (generated by theme.py)\n\n"
        "[X-GNOME-Metatheme]\nGtkTheme=Wall\n"
    )
    # Wall-Glass: Wall + translucent header bars, only for Brave in GTK mode (bin/brave shim, brave_mode = "gtk")
    glass = Path.home() / ".local/share/themes/Wall-Glass"
    (glass / "gtk-3.0").mkdir(parents=True, exist_ok=True)
    write_atomic(glass / "gtk-3.0/gtk.css",
                 f'@import url("file://{root}/gtk-3.0/gtk.css");\n@import url("file://{HOST_OUT}/brave-glass.css");\n')
    (glass / "index.theme").write_text(
        "[Desktop Entry]\nType=X-GNOME-Metatheme\nName=Wall-Glass\n"
        "Comment=Wall with translucent header bars for Brave's GTK mode (generated by theme.py)\n\n"
        "[X-GNOME-Metatheme]\nGtkTheme=Wall-Glass\n"
    )
    for f in ("gtk-3.0", "gtk-4.0"):
        _sub_file(f"~/.config/{f}/settings.ini", r"^gtk-theme-name=.*$", "gtk-theme-name=Wall")
        _sub_file(f"~/.config/{f}/settings.ini", r"^gtk-application-prefer-dark-theme=.*$",
                  f"gtk-application-prefer-dark-theme={'false' if light else 'true'}")
        # stock images on buttons/menus are the old GTK look (and pull in legacy icons); Adwaita has none
        for key in ("gtk-button-images", "gtk-menu-images"):
            _sub_file(f"~/.config/{f}/settings.ini", rf"^{key}=.*$", f"{key}=false")
    _sub_file("~/.gtkrc-2.0", r"^gtk-button-images=.*$", "gtk-button-images=0")
    _sub_file("~/.gtkrc-2.0", r"^gtk-menu-images=.*$", "gtk-menu-images=0")
    _sub_file("~/.config/xsettingsd/xsettingsd.conf", r'^Net/ThemeName .*$', 'Net/ThemeName "Wall"')
    _sub_file("~/.config/xsettingsd/xsettingsd.conf", r"^Gtk/ButtonImages .*$", "Gtk/ButtonImages 0")
    _sub_file("~/.config/xsettingsd/xsettingsd.conf", r"^Gtk/MenuImages .*$", "Gtk/MenuImages 0")
    if run_out(["gsettings", "get", "org.gnome.desktop.interface", "gtk-theme"]).strip("'\n ") != "Wall":
        sh("gsettings set org.gnome.desktop.interface gtk-theme Wall")
    set_color_scheme(mode)


def set_color_scheme(mode):
    """freedesktop color-scheme (gsettings -> the Settings portal): Chromium / Electron / GTK4 / libadwaita apps follow it
    (running ones flip live); "default" would mean no preference and they start light."""
    want = "prefer-light" if mode == "light" else "prefer-dark"
    if run_out(["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]).strip("'\n ") != want:
        sh(f"gsettings set org.gnome.desktop.interface color-scheme {want}")


KVANTUM_DIR = Path("/usr/share/Kvantum")   # base themes (theme.toml kvantum_base), recoloured to the palette


def kv_recolor(hexc, pal):
    """KvFlat colour -> palette: greys by lightness onto the bg..fg ramp, its blue family onto the accent
    (same lightness), anything else unchanged."""
    r, g, b = hex_to_rgb(hexc)
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    if s < 0.15 or max(r, g, b) - min(r, g, b) < 12:
        ramp = [(0.10, "bg"), (0.16, "bg_alt"), (0.18, "surface"), (0.25, "surface2"), (0.32, "overlay"),
                (0.45, "muted"), (0.52, "subtle"), (0.62, "fg_dim"), (0.90, "fg")]
        if l <= ramp[0][0]:
            return pal[ramp[0][1]]
        for (l0, k0), (l1, k1) in zip(ramp, ramp[1:]):
            if l <= l1:
                f = (l - l0) / (l1 - l0)
                c0, c1 = hex_to_rgb(pal[k0]), hex_to_rgb(pal[k1])
                return "#%02x%02x%02x" % tuple(round(a + (b2 - a) * f) for a, b2 in zip(c0, c1))
        return pal[ramp[-1][1]]
    if 0.5 <= h <= 0.7:   # KvFlat's blue accent family
        ar, ag, ab = hex_to_rgb(pal["accent"])
        ah, al, asat = colorsys.rgb_to_hls(ar / 255, ag / 255, ab / 255)
        rr, gg, bb = colorsys.hls_to_rgb(ah, min(0.75, max(0.25, l)), asat)
        return "#%02x%02x%02x" % (round(rr * 255), round(gg * 255), round(bb * 255))
    return hexc


def cfg_settings():
    try:
        return mode_cfg(load_cfg(), get_mode()).get("settings", {})
    except Exception:
        return {}


def kvantum_installed():
    """Kvantum's Qt 6 style plugin and its base themes are present (package `kvantum`)."""
    plugin = any(Path(d, "qt6/plugins/styles/libkvantum.so").exists() for d in ("/usr/lib", "/usr/lib64"))
    return plugin and KVANTUM_DIR.is_dir()


def qt_style(cfg):
    """theme.toml qt_style, except "kvantum" on a host without Kvantum: Fusion (the opaque palette style) instead of
    a style Qt cannot load (Qt / KDE would silently fall back to their own default, not the palette look)."""
    style = cfg.get("settings", {}).get("qt_style")
    if isinstance(style, str) and style.lower() == "kvantum" and not kvantum_installed():
        print("theme: qt_style = kvantum but Kvantum is not installed (pacman -S kvantum); using Fusion", file=sys.stderr)
        return "Fusion"
    return style


def write_kvantum_theme(pal, root=None, base="KvFlat", mode=None):
    """Kvantum theme "Wall" (Qt / KDE apps when the widget style is kvantum, theme.toml qt_style): KvFlat's
    SVG and kvconfig recoloured to the palette, with out/host/kvantum.kvconfig (translucent windows at the glass
    card fill, colours) on top; ~/.config/Kvantum/kvantum.kvconfig selects it."""
    base_cfg, base_svg = KVANTUM_DIR / base / f"{base}.kvconfig", KVANTUM_DIR / base / f"{base}.svg"
    if not base_cfg.exists() or not base_svg.exists():
        return False
    root = Path(root) if root else Path.home() / ".config/Kvantum"
    (root / "Wall").mkdir(parents=True, exist_ok=True)
    sub = lambda txt: re.sub(r"#([0-9a-fA-F]{6})\b", lambda m: kv_recolor("#" + m.group(1), pal), txt)
    # SVG: the libadwaita-style shapes from kvantum_svg.py, plus the base theme's elements it does not draw
    # (arrows, grips, handles, ...) recoloured, with their <defs>
    import xml.etree.ElementTree as ET
    if str(ROOT) not in sys.path:   # python3 -I leaves the script dir off sys.path
        sys.path.insert(0, str(ROOT))
    import kvantum_svg
    a = gtk_glass_alphas(cfg_settings(), mode=mode)
    gen = kvantum_svg.build(pal, float(a["gtk_a_view"]), float(a["gtk_a_popover"]))
    drawn = {p.split('id="')[1].split('"')[0] for p in gen.parts if 'id="' in p}
    drawn |= {d + "-" + e for d in list(drawn) for e in ("top", "bottom", "left", "right", "topleft", "topright",
                                                        "bottomleft", "bottomright")}
    ns = "{http://www.w3.org/2000/svg}"
    tree = ET.fromstring(sub(base_svg.read_text()))
    extra = []
    for el in tree.iter():
        i = el.get("id", "")
        if el.tag == ns + "defs":
            extra.append(ET.tostring(el, encoding="unicode"))
        elif i and i not in drawn and i.split("-")[0] in ("arrow", "grip", "splitter", "resize", "toolbar", "dial",
                                                          "ss", "header", "tab", "titlebar", "mdi", "flat", "sizegrip"):
            if not any(i.startswith(d) for d in drawn if d.split("-")[0] == i.split("-")[0] and i.startswith(d)):
                extra.append(ET.tostring(el, encoding="unicode"))
    svg = gen.text("\n".join(extra)).replace(' xmlns:ns0="http://www.w3.org/2000/svg"', "").replace("ns0:", "")
    # ElementTree renames xlink to ns1 per element; QtSvg only understands the literal xlink:href
    svg = re.sub(r' xmlns:ns\d="http://www.w3.org/1999/xlink"', "", svg)
    svg = re.sub(r"\bns\d:href=", "xlink:href=", svg)
    svg = svg.replace('<svg xmlns="http://www.w3.org/2000/svg"',
                      '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"', 1)
    write_atomic(root / "Wall/Wall.svg", svg)
    # merge: base sections (recoloured), then our keys replace / extend theirs per section
    def parse(txt):
        secs, cur = {}, None
        for line in txt.splitlines():
            m = re.match(r"\s*\[(.+)\]\s*$", line)
            if m:
                cur = m.group(1); secs.setdefault(cur, {})
            elif cur and "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1); secs[cur][k.strip()] = v.strip()
        return secs
    secs = parse(sub(base_cfg.read_text()).replace("=white", "=" + pal["fg"]))
    for sec, kv in parse((HOST_OUT / "kvantum.kvconfig").read_text()).items():
        secs.setdefault(sec, {}).update(kv)
    # the libadwaita min sizes (34 px) belong to buttons / entries / combos / tabs / menu items only: every other
    # section inheriting PanelButtonCommand gets them reset unless it sets its own
    sized = {"PanelButtonCommand", "PanelButtonTool", "ToolbarButton", "LineEdit", "ComboBox", "Tab", "MenuItem"}
    for sec, kv in secs.items():
        if sec not in sized and not sec.startswith("%") and kv.get("inherits"):
            kv.setdefault("min_height", "0"); kv.setdefault("min_width", "0")
    # frame.expansion (rounded 9 px corners on 34 px controls with 6-7 px padding, kvantum_svg "expand-" twins)
    # belongs to buttons / entries / combos only; everything else inheriting PanelButtonCommand draws plain frames
    expanded = {"PanelButtonCommand", "PanelButtonTool", "ToolbarButton", "LineEdit", "ComboBox", "DropDownButton"}
    for sec, kv in secs.items():
        if sec not in expanded and not sec.startswith("%") and kv.get("inherits"):
            kv.setdefault("frame.expansion", "0")
    text = "# generated by ~/.config/theme/theme.py from KvFlat + out/host/kvantum.kvconfig -- do not edit\n"
    text += "\n".join(f"[{sec}]\n" + "".join(f"{k}={v}\n" for k, v in kv.items()) for sec, kv in secs.items())
    write_atomic(root / "Wall/Wall.kvconfig", text)
    sel = root / "kvantum.kvconfig"
    want = "[General]\ntheme=Wall\n"
    if not sel.exists() or sel.read_text() != want:
        sel.write_text(want)
    return True


def purge_oxygen(mode="dark"):
    """KDE leftovers: Plasma's look-and-feel was Oxygen, and ~/.config/kdedefaults supplies the
    fallback for any key kdeglobals doesn't set. Move them all to Breeze Dark / Fusion / our
    scheme (Breeze Dark / Breeze look-and-feel by mode). (Cursor themes are a separate choice and are left alone.)"""
    laf_name = "org.kde.breeze.desktop" if mode == "light" else "org.kde.breezedark.desktop"
    laf = Path("/usr/share/plasma/look-and-feel") / laf_name
    cfg = Path.home() / ".config"

    def kw(file, group, key, val):
        sh(f"kwriteconfig6 --file '{cfg / file}' --group '{group}' --key {key} '{val}'")

    if laf.exists():
        kw("kdeglobals", "KDE", "LookAndFeelPackage", laf_name)
        (cfg / "kdedefaults").mkdir(exist_ok=True)
        pkg = cfg / "kdedefaults/package"
        if pkg.exists() and "oxygen" in pkg.read_text().lower():
            pkg.write_text(laf_name)
        kw("kdedefaults/ksplashrc", "KSplash", "Theme", "org.kde.breeze.desktop")
    kw("kdedefaults/kdeglobals", "General", "ColorScheme", "Wall")
    kw("kdedefaults/kdeglobals", "Icons", "Theme", "Adwaita")
    kw("kdedefaults/kdeglobals", "KDE", "widgetStyle", "Fusion")
    kw("kdedefaults/plasmarc", "Theme", "name", "default")
    kw("kdedefaults/kwinrc", "org.kde.kdecoration2", "library", "org.kde.breeze")
    kw("kdedefaults/kwinrc", "org.kde.kdecoration2", "theme", "Breeze")
    kw("kwinrc", "org.kde.kdecoration2", "theme", "Breeze")


def clear_app_color_overrides():
    """KDE apps can pin their own color scheme ([UiSettings] ColorScheme= in e.g. dolphinrc, which
    was set to the light Oxygen scheme). That beats kdeglobals, so the generated scheme never
    reached them. Remove the pin; the app then follows kdeglobals."""
    for f in (Path.home() / ".config").glob("*rc"):
        if f.name == "kdeglobals":
            continue
        try:
            lines = f.read_text().splitlines(keepends=True)
        except OSError:
            continue
        sec, out, changed = None, [], False
        for l in lines:
            m = re.match(r"\[(.+)\]\s*$", l)
            if m:
                sec = m.group(1)
            if sec == "UiSettings" and re.match(r"ColorScheme=", l):
                changed = True
                continue
            out.append(l)
        if changed:
            f.write_text("".join(out))


def apply_fonts(cfg):
    """One UI font for Qt (qt5ct/qt6ct), KDE (kdeglobals) and GTK. ui_font = "" disables."""
    s = cfg.get("settings", {})
    fam = s.get("ui_font", cfg.get("vars", {}).get("font", ""))
    if not fam:
        return
    size = int(s.get("ui_font_size", 11))
    spec = lambda sz: f"{fam},{sz},-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    for q in ("qt5ct/qt5ct.conf", "qt6ct/qt6ct.conf"):
        _sub_file(f"~/.config/{q}", r"^general=.*$", f'general="{spec(size)}"')
        _sub_file(f"~/.config/{q}", r"^fixed=.*$", f'fixed="{spec(size)}"')
    for key, sz in (("font", size), ("fixed", size), ("menuFont", size), ("toolBarFont", size), ("smallestReadableFont", size - 2)):
        sh(f"kwriteconfig6 --file kdeglobals --group General --key {key} '{spec(sz)}'")
    gtk = f"{fam} {size}"
    for f in ("gtk-3.0", "gtk-4.0"):
        _sub_file(f"~/.config/{f}/settings.ini", r"^gtk-font-name=.*$", f"gtk-font-name={gtk}", append=f"gtk-font-name={gtk}")
    _sub_file("~/.gtkrc-2.0", r"^gtk-font-name=.*$", f'gtk-font-name="{gtk}"', append=f'gtk-font-name="{gtk}"')
    _sub_file("~/.config/xsettingsd/xsettingsd.conf", r"^Gtk/FontName .*$", f'Gtk/FontName "{fam},  {size}"')
    sh(f"gsettings set org.gnome.desktop.interface font-name '{gtk}'")
    sh(f"gsettings set org.gnome.desktop.interface monospace-font-name '{gtk}'")


HERDR_BASE = ROOT.parent / "herdr" / "config.toml"   # tracked, carries the default [theme] block
HERDR_HEADER = "# generated by theme.py (config/herdr/config.toml + this machine's theme block): edit the repo file, then run `theme.py render`\n"


def inject_text(cur, text, name="theme", cm="#"):
    begin, end = f"{cm} >>> {name} (generated, do not edit) >>>", f"{cm} <<< {name} <<<"
    block = f"{begin}\n{text.rstrip()}\n{end}\n"
    pat = re.compile(re.escape(begin) + r".*?" + re.escape(end) + r"\n?", re.S)
    return pat.sub(lambda _: block, cur) if pat.search(cur) else (cur.rstrip("\n") + "\n\n" if cur else "") + block


def deploy_herdr():
    """~/.config/herdr/config.toml = the tracked base with this machine's theme block: a real generated file (herdr has
    no include), so a wallpaper switch never touches the tracked file. The old symlink into the repo is replaced once."""
    dest = Path.home() / ".config/herdr/config.toml"
    if not (dest.exists() or dest.is_symlink() or dest.parent.exists() or shutil.which("herdr")):
        return
    base = HERDR_BASE.read_text() if HERDR_BASE.exists() else ""
    new = HERDR_HEADER + inject_text(base, (OUT / "herdr.toml").read_text())
    if dest.is_symlink():
        dest.unlink()   # pointed into the repo: nothing to keep
    elif dest.exists():
        cur = dest.read_text()
        if cur == new:
            return
        if not cur.startswith("# generated by theme.py"):   # a foreign file: keep the original
            keep = dest.with_name(dest.name + ".pre-theme")
            dest.rename(keep if not keep.exists() else dest.with_name(f"{dest.name}.pre-theme.{int(time.time())}"))
    dest.parent.mkdir(parents=True, exist_ok=True)
    write_atomic(dest, new)


def deploy(cfg, pal, mode=None):
    mode = mode or get_mode()
    link_omarchy()
    link("~/.config/gtk-3.0/gtk.css", HOST_OUT / "gtk3.css")  # gtk.css + glass for CSD GTK3 windows (Gecko excluded)
    link("~/.config/gtk-4.0/gtk.css", HOST_OUT / "gtk4.css")  # gtk.css + translucent libadwaita (gtk_glass_*)
    if (OUT / "geary-user-style.css").exists() and (shutil.which("geary") or Path("~/.config/geary").expanduser().is_dir()):
        link("~/.config/geary/user-style.css", OUT / "geary-user-style.css")  # Geary message bodies (plain text), read at start

    # KDE/Dolphin: two scheme names so re-applying a changed palette is never a
    # no-op "already using this scheme" for plasma-apply-colorscheme.
    kde = Path.home() / ".local/share/color-schemes"
    kde.mkdir(parents=True, exist_ok=True)
    src = (OUT / "kde.colors").read_text()
    for name in ("Wall", "WallB"):
        (kde / f"{name}.colors").write_text(src.replace("@@SCHEME@@", name))

    # Qt apps via qt6ct (QT_QPA_PLATFORMTHEME=qt6ct)
    link("~/.config/qt6ct/colors/wall.conf", OUT / "qt6ct.conf")
    qt = Path.home() / ".config/qt6ct/qt6ct.conf"
    if qt.exists():
        txt = qt.read_text()
        want = f"color_scheme_path={Path.home()}/.config/qt6ct/colors/wall.conf"
        new = re.sub(r"(?m)^color_scheme_path=.*$", want, txt)
        if new != txt:
            qt.write_text(new)

    style = qt_style(cfg)
    if style and qt.exists():  # Oxygen ignores QPalette/kdeglobals; Breeze/Fusion follow them
        txt = qt.read_text()
        new = re.sub(r"(?m)^style=.*$", f"style={style}", txt)
        if new != txt:
            qt.write_text(new)
    if style:  # KDE apps (Dolphin) take the widget style from kdeglobals instead
        sh(f"kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle {style}")

    clear_app_color_overrides()
    apply_fonts(cfg)
    write_gtk_theme(pal, mode)
    write_kvantum_theme(pal, base=cfg.get("settings", {}).get("kvantum_base", "KvFlat"), mode=mode)
    apply_qt_layout(cfg)
    purge_oxygen(mode)

    deploy_herdr()


# ---------------------------------------------------------------------- brave
BRAVE_DIR = Path.home() / ".config/BraveSoftware/Brave-Browser"


def brave_running():
    return bool(run_out(["pgrep", "-x", "brave"]))


def apply_brave(cfg, pal, mode=None):
    """Brave's "Use GTK theme" ignores our gtk.css (Chromium resolves GTK colors in its
    own context), so use its own seed-color theme instead: write the seed into the
    profile Preferences. A running Brave rewrites that file on exit and would discard
    the edit, so this only runs while Brave is closed -- the `brave` launcher in
    ~/.local/bin calls `theme.py brave` right before starting it. Returns True if applied."""
    s = cfg.get("settings", {})
    if not s.get("brave", True) or not BRAVE_DIR.is_dir() or brave_running():
        return False
    scheme = 1 if (mode or get_mode()) == "light" else 2   # Chromium color_scheme2: 1 light, 2 dark
    gtk_mode = s.get("brave_mode", "seed") == "gtk"   # GTK mode: frame colours from Wall-Glass (the shim's GTK_THEME)
    seed = pal.get(s.get("brave_seed", "accent_soft"), pal["accent_soft"]).lstrip("#")
    argb = (0xFF << 24) | int(seed, 16)
    argb -= 1 << 32 if argb >= 1 << 31 else 0  # Chromium stores a signed 32-bit int
    done = False
    for prefs in sorted(BRAVE_DIR.glob("*/Preferences")):
        if prefs.parent.name.endswith("JUNK") or not (prefs.parent.name == "Default" or prefs.parent.name.startswith("Profile")):
            continue
        try:
            d = json.loads(prefs.read_text())
        except (OSError, ValueError):
            continue
        ext_theme = d.setdefault("extensions", {}).setdefault("theme", {})
        if ext_theme.get("id"):  # the user installed a theme from the web store: leave it alone
            continue
        if gtk_mode:
            # GTK mode: the translucent Wall-Glass tab strip. Optional brave_gtk_seed: Chromium still derives its
            # accent (omnibox focus ring, toggles, links in its own UI) from the seed colour while the toolbar /
            # tab colours keep coming from GTK; "" leaves the seed prefs alone.
            want = {"system_theme": 1}
            # The tab strip is only translucent with Chromium's own (client-side) frame: "Use system title bar and
            # borders" (browser.custom_chrome_frame = false) makes the whole window an opaque surface and the strip
            # shows the headerbar colour solid (measured: rgb = bg, alpha dropped). Force the custom frame.
            frame_ok = d.setdefault("browser", {}).get("custom_chrome_frame") is True
            d["browser"]["custom_chrome_frame"] = True
            gseed = s.get("brave_gtk_seed", "")
            th = d.setdefault("browser", {}).setdefault("theme", {})
            new_th = dict(th)
            if gseed:
                gv = (0xFF << 24) | int(pal.get(gseed, pal["accent"]).lstrip("#"), 16)
                gv -= 1 << 32 if gv >= 1 << 31 else 0
                new_th.update({"user_color2": gv, "color_variant2": s.get("brave_gtk_variant", 3),
                               "color_scheme2": scheme, "follows_system_colors": False})
            if frame_ok and ext_theme.get("system_theme") == 1 and new_th == th:
                done = True
                continue
            ext_theme.update(want)
            th.clear(); th.update(new_th)
            write_atomic(prefs, json.dumps(d, separators=(",", ":")))
            done = True
            continue
        ext_theme["system_theme"] = 0  # seed mode: leave "GTK" mode, it can't follow our colors
        th = d.setdefault("browser", {}).setdefault("theme", {})
        th.update({"user_color2": argb, "color_variant2": s.get("brave_variant", 2),
                   "color_scheme2": scheme, "follows_system_colors": False})
        write_atomic(prefs, json.dumps(d, separators=(",", ":")))
        done = True
    return done


# ---------------------------------------------------------------- thunderbird
TB_DIR = Path.home() / ".thunderbird"
TB_PREFS = """user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);"""


def thunderbird_profile():
    """The profile this install starts with: installs.ini Default (what `thunderbird` opens), else the
    profiles.ini section with Default=1. None if Thunderbird was never run."""
    import configparser
    for fn, inst in (("installs.ini", True), ("profiles.ini", False)):
        cp = configparser.ConfigParser(interpolation=None)
        cp.optionxform = str
        if not cp.read(TB_DIR / fn):
            continue
        for s in cp.sections():
            if inst:
                rel = cp[s].get("Default")
                if rel and (TB_DIR / rel).is_dir():
                    return TB_DIR / rel
            elif s.startswith("Profile") and cp[s].get("Default") == "1" and cp[s].get("Path"):
                path = TB_DIR / cp[s]["Path"] if cp[s].get("IsRelative", "1") == "1" else Path(cp[s]["Path"])
                if path.is_dir():
                    return path
    return None


def apply_thunderbird(cfg, profile=None):
    """userChrome.css / userContent.css (generated) into the default profile's chrome/ and a marked block in
    user.js that enables them. Only these files are written (never prefs.js, mail or account data); a foreign
    userChrome.css / userContent.css is moved to *.pre-theme once. A running Thunderbird reads them at start only."""
    if not cfg.get("settings", {}).get("thunderbird", True):
        return False
    profile = profile or thunderbird_profile()
    if not profile:
        return False
    chrome = profile / "chrome"
    chrome.mkdir(exist_ok=True)
    for name in ("userChrome.css", "userContent.css"):
        dest, text = chrome / name, (OUT / f"thunderbird-{name}").read_text()
        if dest.exists() and not dest.is_symlink() and "generated by" not in dest.read_text()[:200]:
            dest.rename(dest.with_name(name + ".pre-theme"))
        if not dest.exists() or dest.read_text() != text:
            write_atomic(dest, text)
    inject(profile / "user.js", TB_PREFS, name="theme", cm="//")
    return True


# ---------------------------------------------------------------------- icons
ICON_NAMES = ("Wall-Adwaita", "Wall-AdwaitaB")  # alternated so a re-apply is a real theme *change*
ICON_DIRS = ("places", "devices", "mimetypes", "status")
ADWAITA_BLUE_HUE = 0.583  # #62a0ea, the folder blue every Adwaita color icon is built around


def recolor_svg(svg, shift, sat_scale, only_blue):
    """Rotate Adwaita's blue family (or every chromatic color) by `shift` hue,
    keeping lightness and the relative offsets inside the family, so gradients and
    shading survive. Greys, blacks and whites are left alone."""

    def sub(m):
        h, l, s = to_hls("#" + m.group(1))
        if s < 0.15 or l < 0.06 or l > 0.97:
            return m.group(0)
        if only_blue and hue_dist(h, ADWAITA_BLUE_HUE) > 0.10:
            return m.group(0)  # warning yellow, error red, green etc. keep their meaning
        return hls(h + shift, l, s * sat_scale)

    return re.sub(r"#([0-9a-fA-F]{6})\b", sub, svg)


def gen_icons(pal, cfg):
    s = cfg.get("settings", {})
    base = Path("/usr/share/icons") / s.get("icon_base", "Adwaita")
    if not (base / "scalable").is_dir():
        return False
    ah, _, asat = to_hls(pal["accent"])
    shift = ah - ADWAITA_BLUE_HUE
    # a colorless wallpaper (accent fell back to the greyish foreground) => greyscale icons
    sat_scale = s.get("icon_saturation", 0.8) * max(0.0, min(1.0, asat / 0.55))
    only_blue = s.get("icon_recolor", "blue") != "all"

    index = (base / "index.theme").read_text()
    sections = "".join(
        m.group(0) for m in re.finditer(r"(?ms)^\[scalable/(%s)\].*?(?=^\[|\Z)" % "|".join(ICON_DIRS), index)
    )
    for name in ICON_NAMES:
        root = Path.home() / ".local/share/icons" / name
        for d in ICON_DIRS:
            (root / "scalable" / d).mkdir(parents=True, exist_ok=True)
            for svg in (base / "scalable" / d).glob("*.svg"):
                (root / "scalable" / d / svg.name).write_text(
                    recolor_svg(svg.read_text(), shift, sat_scale, only_blue)
                )
        dirs = ",".join(f"scalable/{d}" for d in ICON_DIRS)
        (root / "index.theme").write_text(
            f"[Icon Theme]\nName={name}\nComment=Adwaita recolored from the wallpaper (generated)\n"
            f"Inherits={s.get('icon_base', 'Adwaita')},AdwaitaLegacy,hicolor\nDirectories={dirs}\n\n{sections}"
        )
    gen_qt_icons(pal, cfg)
    return True


QT_ICON_NAME = "Wall-Adwaita-Qt"
# KDE action names (Dolphin, Ark, ...) -> the Adwaita symbolic icon libadwaita apps show for the same action
QT_ICON_ALIASES = {
    "application-menu": "open-menu", "view-list-icons": "view-grid", "view-list-details": "view-list",
    "view-list-tree": "view-list", "view-list-text": "view-list", "view-split-left-right": "view-dual",
    "configure": "emblem-system", "settings-configure": "emblem-system", "dialog-close": "window-close",
    "tab-close": "window-close", "document-open-folder": "folder-open", "view-sidebar": "sidebar-show",
    "sidebar-expand": "sidebar-show", "view-more-symbolic": "view-more", "overflow-menu": "view-more",
    "edit-clear": "edit-clear", "window-new": "window-new", "go-home": "go-home", "view-hidden": "view-reveal",
    "view-visible": "view-reveal", "kt-show-hidden": "view-reveal", "view-preview": "view-reveal",
}


def gen_qt_icons(pal, cfg, root=None):
    """Icon theme for Qt / KDE only (theme.toml qt_symbolic_icons): libadwaita shows SYMBOLIC (monochrome) icons in
    header bars, toolbars and sidebars, but KDE apps ask for plain names (go-previous, user-home, ...) that resolve
    to coloured legacy icons. This theme puts first: Adwaita's symbolic actions / ui icons under their plain names
    (+ KDE aliases), Breeze Dark's monochrome actions for names Adwaita lacks, and the symbolic places / devices at
    16 px only (sidebars), all recoloured to the palette fg; then the colour Wall-Adwaita dirs (symlinks), so the
    same names stay coloured at view sizes. GTK keeps Wall-Adwaita."""
    s = cfg.get("settings", {})
    if not s.get("qt_symbolic_icons", True):
        return False
    sym = Path("/usr/share/icons/Adwaita/symbolic")
    if not sym.is_dir():
        return False
    fg = pal["fg"]
    root = Path(root) if root else Path.home() / ".local/share/icons" / QT_ICON_NAME
    colour = Path.home() / ".local/share/icons" / ICON_NAMES[0]
    mono = lambda txt: re.sub(r"#(2e3436|222222|000000|2e3434|474747|241f31)\b", fg, txt, flags=re.I)
    dirs, sections = [], []

    def add_dir(rel, ctx, size, typ, extra=""):
        dirs.append(rel)
        sections.append(f"[{rel}]\nContext={ctx}\nSize={size}\nType={typ}\n{extra}\n")
        (root / rel).mkdir(parents=True, exist_ok=True)

    import shutil
    if root.exists():
        shutil.rmtree(root)
    # sidebars (16-24 px requests, Dolphin's places panel): symbolic places / devices; listed before the colour
    # dirs, so they win up to 24 px and the colour folders stay for icon views (Dolphin's details view at <= 24 px
    # shows the symbolic folders too: one icon name serves both)
    for ctx, d in (("Places", "places"), ("Devices", "devices")):
        add_dir(f"16/{d}", ctx, 16, "Scalable", "MinSize=16\nMaxSize=24\n")
        for f in (sym / d).glob("*-symbolic.svg"):
            (root / f"16/{d}" / f.name.replace("-symbolic", "")).write_text(mono(f.read_text()))
    # actions: Adwaita symbolic under plain and -symbolic names, aliases, then Breeze Dark's for the rest
    add_dir("symbolic/actions", "Actions", 16, "Scalable", "MinSize=8\nMaxSize=512\n")
    act = root / "symbolic/actions"
    have = {}
    for d in ("actions", "ui", "legacy"):
        for f in (sym / d).glob("*-symbolic.svg"):
            have.setdefault(f.name[:-len("-symbolic.svg")], f)
    for name, f in have.items():
        txt = mono(f.read_text())
        (act / f"{name}.svg").write_text(txt)
        (act / f"{name}-symbolic.svg").write_text(txt)
    for alias, target in QT_ICON_ALIASES.items():
        f = have.get(target) or next(iter((sym).glob(f"*/{target}-symbolic.svg")), None)
        if f and not (act / f"{alias}.svg").exists():
            (act / f"{alias}.svg").write_text(mono(f.read_text()))
    breeze = Path("/usr/share/icons/breeze-dark/actions/16")
    if breeze.is_dir():
        for f in breeze.glob("*.svg"):
            out = act / f.name
            if out.exists():
                continue
            try:
                txt = f.read_text()
            except OSError:
                continue
            out.write_text(re.sub(r"(\.ColorScheme-Text\s*\{\s*color:\s*)#[0-9a-fA-F]{6}", r"\g<1>" + fg, txt))
    # colour icons for every other size / context: Wall-Adwaita's recoloured dirs
    for d in ICON_DIRS:
        rel = f"scalable/{d}"
        dirs.append(rel)
        m = re.search(r"(?ms)^\[%s\].*?(?=^\[|\Z)" % re.escape(rel), (colour / "index.theme").read_text()) \
            if (colour / "index.theme").exists() else None
        sections.append(m.group(0) if m else f"[{rel}]\nSize=128\nMinSize=8\nMaxSize=512\nType=Scalable\n\n")
        (root / "scalable").mkdir(parents=True, exist_ok=True)
        (root / rel).symlink_to(colour / rel)
    (root / "index.theme").write_text(
        f"[Icon Theme]\nName={QT_ICON_NAME}\nComment=Qt / KDE: Adwaita symbolic in toolbars and sidebars (generated)\n"
        # KIconLoader group defaults (libadwaita: 16 px toolbar / header bar icons); FollowsColorScheme lets KDE
        # recolour the Breeze fallbacks' ColorScheme-Text to the palette like Breeze does
        "MainToolbarDefault=16\nMainToolbarSizes=16,22,32\nToolbarDefault=16\nToolbarSizes=16,22,32\n"
        "SmallDefault=16\nSmallSizes=16\nPanelDefault=32\nDialogDefault=32\nDesktopDefault=48\nFollowsColorScheme=true\n"
        f"Inherits={ICON_NAMES[0]},Adwaita,AdwaitaLegacy,breeze-dark,hicolor\nDirectories={','.join(dirs)}\n\n"
        + "\n".join(sections))
    return True


def current_icon_name():
    return run_out(["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"]).strip().strip("'")


def next_icon_name():
    return ICON_NAMES[1] if current_icon_name() == ICON_NAMES[0] else ICON_NAMES[0]


def _sub_file(path, pattern, repl, append=None):
    """Regex-replace a line in a config file we don't own; optionally append when absent."""
    path = Path(path).expanduser()
    if not path.exists():
        return
    txt = path.read_text()
    new, n = re.subn(pattern, repl, txt, flags=re.M)
    if n == 0 and append:
        new = txt.rstrip("\n") + "\n" + append + "\n"
    if new != txt:
        path.write_text(new)


def set_icon_theme(name):
    """Point every toolkit at `name` so GTK 2/3/4, Qt 5/6, KDE and XWayland apps all agree.
    GTK3/4 reload icons live when the name changes."""
    sh(f"gsettings set org.gnome.desktop.interface icon-theme {name}")
    for f in ("gtk-3.0", "gtk-4.0"):
        _sub_file(f"~/.config/{f}/settings.ini", r"^gtk-icon-theme-name=.*$", f"gtk-icon-theme-name={name}")
    _sub_file("~/.gtkrc-2.0", r"^gtk-icon-theme-name=.*$", f'gtk-icon-theme-name="{name}"',
              append=f'gtk-icon-theme-name="{name}"')
    _sub_file("~/.config/xsettingsd/xsettingsd.conf", r'^Net/IconThemeName .*$', f'Net/IconThemeName "{name}"')
    set_qt_icon_theme(name)


def set_qt_icon_theme(gtk_name):
    """Qt 5/6 + KDE: the symbolic Qt layer (gen_qt_icons) when it exists, else the GTK name."""
    qt = QT_ICON_NAME if (cfg_settings().get("qt_symbolic_icons", True)
                          and (Path.home() / ".local/share/icons" / QT_ICON_NAME / "index.theme").exists()) else gtk_name
    for q in ("qt5ct/qt5ct.conf", "qt6ct/qt6ct.conf"):
        _sub_file(f"~/.config/{q}", r"^icon_theme=.*$", f"icon_theme={qt}")
    sh(f"kwriteconfig6 --file kdeglobals --group Icons --key Theme {qt}")  # KDE apps (Dolphin, ...)


def apply_qt_layout(cfg):
    """libadwaita header bar look for KDE toolbars (theme.toml qt_symbolic_icons): 16 px icons, icon only."""
    if not cfg.get("settings", {}).get("qt_symbolic_icons", True):
        return
    for grp in ("MainToolbarIcons", "ToolbarIcons"):
        sh(f"kwriteconfig6 --file kdeglobals --group {grp} --key Size 16")
    for key in ("ToolButtonStyle", "ToolButtonStyleOtherToolbars"):
        sh(f"kwriteconfig6 --file kdeglobals --group 'Toolbar style' --key {key} NoText")
    sh("kwriteconfig6 --file dolphinrc --group PlacesPanel --key IconSize 16")  # Nautilus sidebar: 16 px symbolic
    if (Path.home() / ".local/share/icons" / QT_ICON_NAME / "index.theme").exists():
        set_qt_icon_theme(current_icon_name())


# --------------------------------------------------------------------- reload
def run_out(cmd, timeout=15):
    """stdout of a successful command, "" if it is missing, fails or hangs (minimal installs lack some tools)."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return ""
    return r.stdout if r.returncode == 0 else ""


def sh(cmd, timeout=10):
    try:
        subprocess.run(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=timeout)
    except subprocess.TimeoutExpired:
        pass


def reload_terminals():
    sh("pkill -USR1 -x kitty")  # kitty: reload config (re-reads the included colors)
    sh("pkill -USR2 -x ghostty")  # ghostty: reload config
    # alacritty watches its imported files itself


def reload_nvim():
    """Every running nvim exposes an RPC socket in $XDG_RUNTIME_DIR; ThemeReload()
    is defined in config/nvim/lua/plugins/theme.lua. Stale sockets just fail fast."""
    run = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    procs = [
        subprocess.Popen(
            ["nvim", "--server", str(s), "--remote-expr", "luaeval('ThemeReload()')"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        for s in run.glob("nvim.*.0")
    ]
    for pr in procs:
        try:
            pr.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pr.kill()


def reload_zellij():
    # zellij watches config.kdl and re-reads themes from theme_dir when it changes;
    # an identical rewrite is enough to trigger that.
    cfg = (Path.home() / ".config/zellij/config.kdl").resolve()
    if cfg.exists():
        cfg.write_text(cfg.read_text())


def reload_gtk():
    # GTK/libadwaita re-parse the user gtk.css when the color scheme / theme flips,
    # so blip both and put them straight back.
    def get(k):
        return run_out(["gsettings", "get", "org.gnome.desktop.interface", k]).strip()

    scheme, theme = get("color-scheme"), get("gtk-theme")
    if not scheme:
        return
    sh("gsettings set org.gnome.desktop.interface color-scheme default")
    if theme:
        sh("gsettings set org.gnome.desktop.interface gtk-theme Adwaita")
    time.sleep(0.2)
    sh(f"gsettings set org.gnome.desktop.interface color-scheme {scheme}")
    if theme:
        sh(f"gsettings set org.gnome.desktop.interface gtk-theme {theme}")


def reload_kde():
    kg = Path.home() / ".config/kdeglobals"
    cur = re.search(r"(?m)^ColorScheme=(.*)$", kg.read_text()) if kg.exists() else None
    nxt = "WallB" if cur and cur.group(1) == "Wall" else "Wall"
    # KDE layers its own "accent color" over the scheme's selection/focus colors; without this it
    # keeps a stale one (an old wallpaper's) and Dolphin's highlights stay the wrong hue
    accent = PAL[0]["accent"] if PAL[0] else ""
    sh("kwriteconfig6 --file kdeglobals --group General --key accentColorFromWallpaper false")
    if accent:
        r, g, b = hex_to_rgb(accent)
        sh(f"kwriteconfig6 --file kdeglobals --group General --key AccentColor '{r},{g},{b}'")
    sh(f"plasma-apply-colorscheme {('--accent-color ' + repr(accent) + ' ') if accent else ''}{nxt}")


def reload_icons(cfg):
    if cfg.get("settings", {}).get("icons", True) and gen_icons(PAL[0], cfg):
        set_icon_theme(next_icon_name())


PAL = [None]  # the palette of this run, for reload jobs that need it


def refresh_nautilus():
    """A running Nautilus keeps its old icon theme for every new window, so the process
    itself must restart. Idle (no windows, just the background service): quit it, free.
    With windows open: leave them alone and say so."""
    if not run_out(["pgrep", "-x", "nautilus"]):
        return
    out = run_out(["hyprctl", "clients", "-j"])
    try:
        wins = [c for c in json.loads(out) if c.get("class") == "org.gnome.Nautilus"]
    except ValueError:
        wins = []
    if wins:
        print(f"theme: nautilus has {len(wins)} window(s) open and keeps its old icons/colors; "
              "close them (or run `nautilus -q`) and reopen", file=sys.stderr)
    else:
        sh("nautilus -q")


def reload_apps(cfg, mode_only=False):
    """mode_only (light / dark switch): the wallpaper did not change, so hyprpaper is left running."""
    from concurrent.futures import ThreadPoolExecutor

    def hypr():
        sh("hyprctl reload")
        if cfg.get("settings", {}).get("restart_hyprpaper", True) and not mode_only:
            restart_hyprpaper()

    def quit_apps():
        for cmd in cfg.get("settings", {}).get("quit_on_apply", []):
            sh(cmd)

    jobs = [quit_apps, refresh_nautilus, hypr, reload_terminals, reload_nvim, reload_zellij, reload_gtk, reload_kde, lambda: reload_icons(cfg),
            lambda: sh("herdr server reload-config")]
    with ThreadPoolExecutor(len(jobs)) as ex:
        for f in [ex.submit(j) for j in jobs]:
            f.result()
    # tofi/hyprlock read their files at launch; quickshell watches out/palette.json;
    # brave picks up its policy file on its own within a few seconds.


# ------------------------------------------------------------------------ main
def deep_merge(base, over):
    out = dict(base)
    for k, v in over.items():
        out[k] = deep_merge(out[k], v) if isinstance(v, dict) and isinstance(out.get(k), dict) else v
    return out


def load_cfg():
    """theme.toml (tracked) with theme.local.toml (git-ignored, per machine) merged over it."""
    with open(ROOT / "theme.toml", "rb") as f:
        cfg = tomllib.load(f)
    if not DEFAULT_MODE and LOCAL_TOML.exists():
        try:
            with open(LOCAL_TOML, "rb") as f:
                cfg = deep_merge(cfg, tomllib.load(f))
        except (tomllib.TOMLDecodeError, OSError) as e:
            print(f"theme: ignoring unreadable {LOCAL_TOML.name}: {e}", file=sys.stderr)
    return cfg


LOCAL_HEADER = """# Per-machine theme selection (git-ignored). theme.py apply writes `wallpaper` here; theme.toml (tracked) keeps the
# defaults. Anything from theme.toml can be overridden here: [settings], [overrides], [vars].
# [vars] tv_wallpaper = "~/..."   image of HDMI-A-1 (hyprpaper), [vars] static_blocks = per-monitor hyprpaper blocks.
"""


def set_wallpaper(path):
    """The selected wallpaper goes to theme.local.toml; the tracked theme.toml is never written."""
    t = LOCAL_TOML.read_text() if LOCAL_TOML.exists() else LOCAL_HEADER
    line = f'wallpaper = "{path}"'
    if re.search(r'(?m)^wallpaper\s*=', t):
        t = re.sub(r'(?m)^wallpaper\s*=.*$', lambda _: line, t, count=1)
    else:
        m = re.search(r'(?m)^\[', t)
        t = t[:m.start()] + line + "\n\n" + t[m.start():] if m else t.rstrip("\n") + "\n\n" + line + "\n"
    write_atomic(LOCAL_TOML, t)


def write_hyprpaper(cfg):
    """Re-render only out/hyprpaper.conf (a non-primary monitor changed: no palette, no app reloads)."""
    extra = {"wallpaper": str(Path(os.path.expanduser(cfg["wallpaper"]))), **cfg.get("vars", {})}
    if not os.path.exists(os.path.expanduser(extra.get("tv_wallpaper", ""))):
        extra["tv_wallpaper"] = extra["wallpaper"]
    extra.update(monitor_extras())
    extra.update(wallpaper_t=tilde(extra["wallpaper"]), tv_wallpaper_t=tilde(extra["tv_wallpaper"]))
    extra["static_blocks"] = static_blocks(cfg, extra)
    drop_marker()
    write_atomic(OUT / "hyprpaper.conf", render((ROOT / "templates/hyprpaper.conf").read_text(), {}, extra))


def pop_all(args, name):
    """Every value of a repeatable option, removed from args."""
    vals = []
    while name in args:
        i = args.index(name)
        vals.append(args[i + 1] if i + 1 < len(args) else "")
        del args[i:i + 2]
    return vals


def monitor_command(cmd, args, o):
    """Per-monitor wallpaper commands; returns True when handled without a theme re-render.
    apply <img|video> --monitor <key> [--monitor <key> ...] | clear <key>... | primary <key> | link <a> <b> [--from <key>] | unlink <a> <b>.
    `o` = {mode, play, wind, ease} (the caller's options; link fills them from the source's entry when the primary is in the group).
    Several --monitor keys (a link group) = ONE call: the entry is made once, the state and hyprpaper conf written once, each
    output live-set, the players synced once. When the primary is among them the others are saved, then the normal full apply
    (palette, apps, hyprpaper restart) runs for the primary and picks the others' entries up from the state.
    The primary's wallpaper IS theme.toml's (a video's still, with the video in `primary_video`)."""
    if cmd == "apply" and "--monitor" in args:
        keys = list(dict.fromkeys(pop_all(args, "--monitor")))
        if not keys or not all(valid_key(k) for k in keys) or not args:
            sys.exit("theme: apply <img> --monitor <key> [--monitor <key> ...]")
        st, mons = load_wp_state(), connected_monitors()
        prim = primary_key(st, mons)
        others = [k for k in keys if k != prim]
        if not others:
            return False   # the primary alone: the normal apply
        ent = make_entry(args[0], o["mode"], o["play"], o["wind"], o["ease"])
        for k in others:
            st["monitors"][k] = json.loads(json.dumps(ent))
        st["primary"] = st["primary"] or prim   # pin the default so a later layout change does not move it
        save_wp_state(st)
        video_optimize_poke()
        if prim in keys:
            return False   # the full apply below re-renders hyprpaper (with these entries) and syncs the players
        write_hyprpaper(load_cfg())
        for k in others:
            live_set_wallpaper(k, next((m["name"] for m in mons if m["key"] == k), None), entry_image(ent))
        video_sync()
        print(f"theme: {', '.join(others)} -> {Path(args[0]).name}" + (f" ({ent['mode']})" if isinstance(ent, dict) else " (hyprpaper only)"))
        return True
    if cmd == "clear" and args:
        st, mons = load_wp_state(), connected_monitors()
        for k in args:
            st["monitors"].pop(k, None)
        save_wp_state(st)
        cfg = load_cfg()
        write_hyprpaper(cfg)
        for k in args:
            live_set_wallpaper(k, next((m["name"] for m in mons if m["key"] == k), None), os.path.expanduser(cfg["wallpaper"]))
        video_sync()
        return True
    if cmd == "primary" and args:
        key = args[0]
        if not valid_key(key):
            sys.exit("theme: primary <key>")
        st, mons = load_wp_state(), connected_monitors()
        old = primary_key(st, mons)
        if key == old and st["primary"] == key:
            return True
        cfg = load_cfg()
        oldent = st["primary_video"] or cfg["wallpaper"]
        st["primary_video"] = None
        if key != old:
            st["monitors"][old] = oldent   # the old primary keeps what it shows
        new = st["monitors"].pop(key, None) or oldent
        st["primary"] = key
        if isinstance(new, dict):
            st["primary_video"] = new
        save_wp_state(st)
        img = tilde(entry_image(new))
        if img != cfg["wallpaper"]:
            set_wallpaper(img)   # the new primary's image becomes the theme source: full apply
            args[:] = []
            return False
        write_hyprpaper(cfg)
        video_sync()
        return True
    if cmd == "unlink" and len(args) == 2:
        st = load_wp_state()
        st["links"] = [p for p in st["links"] if set(p) != set(args)]
        save_wp_state(st)
        return True
    if cmd == "link" and len(args) >= 2:
        a, b = args[0], args[1]
        src = pop_opt(args, "--from") or a
        if not (valid_key(a) and valid_key(b) and valid_key(src)) or a == b:
            sys.exit("theme: link <keyA> <keyB> [--from <key>]")
        st, mons = load_wp_state(), connected_monitors()
        if not any(set(p) == {a, b} for p in st["links"]):
            st["links"].append([a, b])
        group = link_group(st, a)
        src = src if src in group else a
        save_wp_state(st)
        # the whole group takes the source's wallpaper (what the source shows: its entry, else the primary's)
        prim = primary_key(st, mons)
        cfg = load_cfg()
        ent = (st["primary_video"] or cfg["wallpaper"]) if src == prim else st["monitors"].get(src)
        members = [k for k in group if k != src]
        if ent is None:   # the source just follows the primary: so does everyone linked to it
            follow = [k for k in members if k != prim]
            return monitor_command("clear", follow, o) if follow else True
        isv = isinstance(ent, dict)
        o.update(mode=ent["mode"] if isv else None, play=ent.get("play") if isv else None,
                 wind=ent.get("wind", 0) if isv else 0, ease=ent.get("ease") if isv else None)
        args[:] = [os.path.expanduser(ent["video"] if isv else ent)] + [x for k in members for x in ("--monitor", k)]
        return monitor_command("apply", args, o)
    return False


def pop_opt(args, name):
    if name in args:
        i = args.index(name)
        v = args[i + 1] if i + 1 < len(args) else None
        del args[i:i + 2]
        return v
    return None


def seed_script():
    return ROOT / "bin" / "theme-seed"


def seed_out(force=False):
    """Run bin/theme-seed (the one implementation, also used by the git hooks and on macOS): fills a missing / seeded out/
    from default/. Only needed when out/ has no real render yet (marker present, or no palette.json), and never on a
    machine with its own selection (theme.local.toml): there a missing out/ is rendered from the selection, not seeded."""
    if LOCAL_TOML.exists() and not force:
        return
    if force or (OUT / MARKER).exists() or not (OUT / "palette.json").exists():
        env = {**os.environ, "THEME_OUT_DIR": str(OUT), "THEME_SEED_FORCE": "1" if force else ""}
        subprocess.run(["sh", str(seed_script()), "-q"], env=env, check=False)


def drop_marker():
    """out/ is about to hold a real render: bin/theme-seed must never touch it again."""
    try:
        (OUT / MARKER).unlink()
    except FileNotFoundError:
        pass


def toml_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, list):
        return "[" + ", ".join(toml_val(x) for x in v) + "]"
    s = str(v)
    if "\n" in s:
        return "'''\n" + s.strip("\n") + "\n'''"
    return json.dumps(s)


def write_local(top, sections):
    """theme.local.toml from {key: value} top-level pairs and {section: {key: value}}."""
    out = [LOCAL_HEADER + "\n"]
    out += [f"{k} = {toml_val(v)}\n" for k, v in top.items()]
    for sec, kv in sections.items():
        if kv:
            out.append(f"\n[{sec}]\n" + "".join(f"{k} = {toml_val(v)}\n" for k, v in kv.items()))
    write_atomic(LOCAL_TOML, "".join(out))


def old_static_blocks(tpl_text):
    """The machine-specific hyprpaper blocks of the pre-split template: every wallpaper block except the catch-all."""
    blocks = re.findall(r"(?ms)^wallpaper \{\n.*?^\}", tpl_text)
    return "\n\n".join(b for b in blocks if not re.search(r"(?m)^\s*monitor\s*=\s*$", b))


def migrate_local(args):
    """One-time, on the machine that generated the old tracked files: theme.local.toml from the working theme.toml
    (wallpaper, tv_wallpaper) and the machine-specific blocks of the old hyprpaper template (read from git HEAD)."""
    if LOCAL_TOML.exists() and "--force" not in args:
        print(f"theme: {LOCAL_TOML} exists, leaving it (--force rewrites)")
        return
    with open(ROOT / "theme.toml", "rb") as f:
        cur = tomllib.load(f)
    vars_ = {}
    if cur.get("vars", {}).get("tv_wallpaper"):
        vars_["tv_wallpaper"] = cur["vars"]["tv_wallpaper"]
    blocks = ""
    r = subprocess.run(["git", "-C", str(ROOT), "show", "HEAD:config/theme/templates/hyprpaper.conf"], capture_output=True, text=True)
    if r.returncode == 0:
        blocks = old_static_blocks(r.stdout)
    else:
        print("theme: old hyprpaper template not found in git HEAD: static_blocks left empty", file=sys.stderr)
    if blocks:
        vars_["static_blocks"] = blocks
    write_local({"wallpaper": cur["wallpaper"]}, {"vars": vars_})
    print(f"theme: wrote {LOCAL_TOML.name}: wallpaper {cur['wallpaper']}" + (", static_blocks" if blocks else ""))


def adopt_legacy(args):
    """A machine that had the old tracked out/ and theme.toml: restore its theme from a backup folder (out/, theme.toml)
    into the per-machine layout. A wallpaper that does not exist here falls back to the default (with a warning)."""
    if not args:
        sys.exit("theme: adopt-legacy <backup dir with out/ and theme.toml>")
    d = Path(args[0]).expanduser()
    try:
        with open(d / "theme.toml", "rb") as f:
            old = tomllib.load(f)
        with open(ROOT / "theme.toml", "rb") as f:
            new = tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError) as e:
        sys.exit(f"theme: adopt-legacy: {e}")
    wp = old.get("wallpaper")
    if not wp or not os.path.exists(os.path.expanduser(wp)):
        print(f"theme: adopt-legacy: wallpaper {wp!r} does not exist here, using the default theme", file=sys.stderr)
        return False
    top = {"wallpaper": wp}
    tv = old.get("vars", {}).get("tv_wallpaper")
    vars_ = {"tv_wallpaper": tv} if tv and os.path.exists(os.path.expanduser(tv)) else {}
    sections = {"vars": vars_}
    for sec in ("settings", "overrides"):   # local edits of the old theme.toml survive as local overrides
        diff = {k: v for k, v in old.get(sec, {}).items() if new.get(sec, {}).get(k) != v}
        sections[sec] = diff
    if (d / "out").is_dir():
        OUT.mkdir(parents=True, exist_ok=True)
        for f in (d / "out").iterdir():
            if f.is_file() and not f.name.endswith(".tmp"):
                shutil.copy2(f, OUT / f.name)
    drop_marker()
    write_local(top, sections)
    print(f"theme: adopted {d}: wallpaper {wp}")
    return True


def default_command():
    """Regenerate the tracked default (default/ outputs + the [theme] block of the tracked herdr base) from
    default/wallpaper.jpg and theme.toml alone (no theme.local.toml, no per-machine state, no host outputs, no reloads)."""
    global OUT, DEFAULT_MODE
    OUT, DEFAULT_MODE = DEFAULT_DIR, True
    wpfile = DEFAULT_DIR / "wallpaper.jpg"
    if not wpfile.exists():
        sys.exit(f"theme: {wpfile} missing")
    cfg = load_cfg()
    if cfg["wallpaper"] != "~/.config/theme/default/wallpaper.jpg":
        print(f"theme: theme.toml wallpaper is {cfg['wallpaper']!r}, expected the default one", file=sys.stderr)
    base = extract(wpfile)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "extracted.json").write_text(json.dumps({"wallpaper": cfg["wallpaper"], **base}))
    pal = build_palette(base, cfg)
    PAL[0] = pal
    render_all(pal, cfg)
    if HERDR_BASE.exists():
        inject(HERDR_BASE, (OUT / "herdr.toml").read_text())
    for f in OUT.glob("*.tmp"):
        f.unlink()
    print(f"theme: default  bg {pal['bg']}  fg {pal['fg']}  accent {pal['accent']}")


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "apply"
    args = list(argv[2:])
    if cmd == "video":
        return video_command(args)
    if cmd == "default":
        return default_command()
    if cmd == "seed":
        return seed_out(force=True)
    if cmd == "mode":   # theme.py mode [get|dark|light|toggle]: persist the mode, then re-render + reload everything
        want = args[0] if args else "get"
        if want == "get":
            print(get_mode())
            return
        if want not in (*MODES, "toggle"):
            sys.exit("theme: mode [get|dark|light|toggle]")
        apply_lock()   # before reading / writing the mode: a running apply finishes with the mode it started with
        os.environ.pop("THEME_MODE", None)   # the saved mode is what this run renders
        want = ("light" if get_mode() == "dark" else "dark") if want == "toggle" else want
        set_mode(want)
        cmd, args = "mode-apply", []
        argv = argv[:2]
    if cmd == "migrate-local":
        return migrate_local(args)
    if cmd == "adopt-legacy":
        adopt_legacy(args)
        cmd, args = "render", []
    if cmd in ("apply", "clear", "primary", "link", "unlink", "render", "mode-apply"):
        apply_lock()
        migrate_glass_modes()   # before any reload: managed.lua reads the per-mode glass sets
    seed_out()
    o = {"mode": pop_opt(args, "--mode"),
         "play": pop_opt(args, "--play"), "wind": pop_opt(args, "--wind") or 0,   # no --play = full length
         "ease": pop_opt(args, "--ease")}   # replay transition seconds; absent = the theme.toml default
    if cmd in ("apply", "clear", "primary", "link", "unlink"):
        if monitor_command(cmd, args, o):
            refresh_wall_ink()   # a monitor's own wallpaper changed: light mode's bar ink for it too
            return
        if cmd != "apply":
            cmd = "apply"
    mode, play, wind, ease = o["mode"], o["play"], o["wind"], o["ease"]
    argv = argv[:2] + args
    if cmd == "apply" and len(argv) > 2:
        ent = make_entry(argv[2], mode, play, wind, ease)   # the primary: an image, or a video whose still is the theme wallpaper
        st = load_wp_state()
        if isinstance(ent, dict) or st["primary_video"]:   # (no state file is created for plain image applies)
            st["primary_video"] = ent if isinstance(ent, dict) else None
            if isinstance(ent, dict):
                st["primary"] = st["primary"] or primary_key(st, connected_monitors())
            save_wp_state(st)
            video_optimize_poke()
        set_wallpaper(tilde(entry_image(ent)))
    mode = get_mode()
    cfg = mode_cfg(load_cfg(), mode)   # the glass knobs of this mode
    wp = Path(os.path.expanduser(cfg["wallpaper"]))
    if cmd == "brave":  # used by the launcher in ~/.local/bin: cached palette, no rendering
        cache = OUT / "extracted.json"
        base = json.loads(cache.read_text()) if cache.exists() else extract(wp)
        apply_brave(cfg, build_palette({k: base[k] for k in ("bg", "fg", "accent")}, cfg, mode), mode)
        return
    cache = OUT / "extracted.json"
    stale = True
    if cache.exists():
        stale = json.loads(cache.read_text()).get("wallpaper") not in (str(wp), tilde(wp))  # wallpaper edited in toml (the default's cache has the ~ form)
    if cmd in ("apply", "show") or stale:
        OUT.mkdir(parents=True, exist_ok=True)
        base = extract(wp)
        if cmd != "show" or not (OUT / MARKER).exists():   # `show` is not a render: it must not turn a seeded out/ into a real one
            drop_marker()
            cache.write_text(json.dumps({"wallpaper": str(wp), **base}))
    else:
        base = json.loads(cache.read_text())
        base = {k: base[k] for k in ("bg", "fg", "accent")}
    pal = build_palette(base, cfg, mode)
    dark = build_palette(base, cfg, "dark") if mode == "light" else None   # light mode: the bar's text on the wallpaper
    if cmd == "show":
        for k, v in pal.items():
            print(f"{k:16}{v}")
        return
    PAL[0] = pal
    drop_marker()
    render_all(pal, cfg, mode, dark)
    if os.environ.get("THEME_OUT_DIR"):   # a redirected out/ is a test render: never repoint the live ~/.config links or apps at it
        return
    deploy(cfg, pal, mode)
    apply_brave(cfg, pal, mode)
    apply_thunderbird(cfg)
    if cmd in ("apply", "mode-apply"):
        reload_apps(cfg, mode_only=cmd == "mode-apply")
    if cmd == "apply":
        # a restarted hyprpaper brings the players back itself (restart_hyprpaper); otherwise just reconcile them
        video_sync(start=not cfg.get("settings", {}).get("restart_hyprpaper", True))
    print(f"theme: {wp.name} ({mode})  bg {pal['bg']}  fg {pal['fg']}  accent {pal['accent']}")


if __name__ == "__main__":
    if sys.platform == "darwin":  # Linux desktop only; macOS uses the committed out/ files as they are
        sys.exit(0)
    main(sys.argv)
