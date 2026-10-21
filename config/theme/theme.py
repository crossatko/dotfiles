#!/usr/bin/env python3
"""Single-source theming: wallpaper -> palette -> every app's colors.

    theme.py apply [WALLPAPER]   extract palette, render templates, reload apps
    theme.py render              re-render from current theme.toml (no extraction)
    theme.py show                print the resolved palette

Edit theme.toml to change anything. Wallpaper-derived values can be pinned with
[overrides]; everything else follows the wallpaper. Stdlib + ImageMagick only.
"""
import colorsys
import json
import os
import re
import subprocess
import sys
import time
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "out"
HOME = Path.home()


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
    """Lighten `color` (keeping hue/saturation) until it reads on `bg`."""
    h, l, s = to_hls(color)
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


def build_palette(base, cfg):
    s = cfg.get("settings", {})
    bg = base["bg"]
    # keep the wallpaper's tint but force a dark, low-chroma base
    bh, bl, bs = to_hls(bg)
    bg = hls(bh, min(bl, s.get("bg_max_lightness", 0.075)), min(bs, 0.15))
    fh, fl, fs = to_hls(base["fg"])
    fg = hls(fh, max(fl, 0.78), min(fs, 0.25))

    fg = ensure_contrast(fg, bg, 9.0)

    accent = base["accent"]
    if accent is None:
        accent = fg  # no color in the image: the foreground doubles as the accent
    else:
        ah, al, as_ = to_hls(accent)
        accent = hls(ah, max(0.42, min(al, 0.62)), max(as_, 0.55))
        accent = ensure_contrast(accent, bg, 4.6)  # also lands in an ANSI slot
    ah, _, _ = to_hls(accent)

    p = {"bg": bg, "fg": fg, "accent": accent}
    p["bg_alt"] = mix(bg, fg, 0.03)
    p["surface"] = mix(bg, fg, 0.07)
    p["surface2"] = mix(bg, fg, 0.13)
    p["overlay"] = mix(bg, fg, 0.28)
    p["muted"] = ensure_contrast(mix(bg, fg, 0.52), bg, 3.0)
    p["subtle"] = ensure_contrast(mix(bg, fg, 0.55), bg, 4.5)  # dim but always legible: line numbers, hints
    p["fg_dim"] = mix(bg, fg, 0.75)
    p["accent_soft"] = mix(bg, accent, 0.45)

    # ANSI: fixed hues, saturation capped so they sit quietly next to the
    # artwork; whichever hue is nearest the accent snaps to it exactly.
    sat = s.get("ansi_saturation", 0.38)
    light = s.get("ansi_lightness", 0.64)
    nearest = min(ANSI_HUES, key=lambda k: hue_dist(ANSI_HUES[k], ah))
    for name, h in ANSI_HUES.items():
        # snap only on a near-exact hue match, so e.g. an orange accent can't
        # silently turn the terminal's red into orange
        if name == nearest and hue_dist(h, ah) < 0.05 and to_hls(accent)[2] > 0.2:
            p[name] = accent
        else:
            p[name] = hls(h, light, sat)
    p["orange"] = hls((ANSI_HUES["red"] + ANSI_HUES["yellow"]) / 2, light, sat)
    p["accent2"] = p["blue"] if nearest != "blue" else p["cyan"]

    p["black"] = p["surface2"]
    p["white"] = p["fg_dim"]
    for name in ("black", "white", *ANSI_HUES):
        h, l, sa = to_hls(p[name])
        p["bright_" + name] = hls(h, l + 0.09, sa)
    p["bright_black"] = p["muted"]
    p["bright_white"] = fg

    # error/warn/ok semantic aliases so templates don't hard-pick ANSI names
    p["error"], p["warn"], p["ok"], p["info"] = p["red"], p["yellow"], p["green"], p["blue"]

    for k, v in cfg.get("overrides", {}).items():
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


def gtk_glass_alphas(s, glass=None):
    clamp = lambda x: min(1.0, max(0.0, float(x)))
    if glass is None:
        glass = hypr_solid_glass()
    # Theme.qml cardFill: 0.3 on the glass, else bar_opacity + 0.3 (keep in sync)
    card = 0.3 if glass else min(1.0, float(s.get("bar_opacity", 0.55)) + 0.3)
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


def render_all(pal, cfg):
    OUT.mkdir(exist_ok=True)
    wp = str(Path(os.path.expanduser(cfg["wallpaper"])))
    extra = {"wallpaper": wp, "home": str(HOME), "out": str(OUT),
             **gtk_glass_alphas(cfg.get("settings", {})), **{k: v for k, v in cfg.get("vars", {}).items()}}
    # Brave GTK mode: active tab title and toolbar icons share one GTK colour (label); brave_tab_text picks it
    extra["brave_label"] = pal["accent"] if cfg.get("settings", {}).get("brave_tab_text", "fg") == "accent" else pal["fg"]
    # a host without the TV wallpaper (it is not in the repo) falls back to the main one instead of a black output
    tv = os.path.expanduser(extra.get("tv_wallpaper", ""))
    if not tv or not os.path.exists(tv):
        extra["tv_wallpaper"] = wp
    for tpl in sorted((ROOT / "templates").iterdir()):
        dest = OUT / tpl.name
        write_atomic(dest, render(tpl.read_text(), pal, extra))
    dirs = [os.path.expanduser(d) for d in cfg.get("wallpaper_dirs", ["~/Pictures/wallpapers"])]
    s = cfg.get("settings", {})
    # Quickshell layout defaults (palette.json); Settings > Appearance overrides them via appearance.json
    # (never touched here). Hyprland does not read them: its values are hand-written in hypr/hyprland/.
    ui = {"rounding": int(s.get("rounding", 0)), "gap": int(s.get("gap", 0)),
          "border_size": int(s.get("border_size", 2)),
          "bar_floating": bool(s.get("bar_floating", False)),
          "smart_gaps": bool(s.get("smart_gaps", True)),
          "bar_border": s.get("bar_border", 0), "bar_opacity": s.get("bar_opacity", 0.55)}
    write_atomic(OUT / "palette.json", json.dumps({"wallpaper": wp, "wallpaper_dirs": dirs, **ui, **pal}, indent=2) + "\n")
    lua = "return {\n" + f'  wallpaper = "{wp}",\n  rounding = {ui["rounding"]},\n' + "".join(f'  {k} = "{v}",\n' for k, v in pal.items()) + "}\n"
    write_atomic(OUT / "palette.lua", lua)


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


def inject(dest, text, name="theme"):
    """Replace/insert a marked block inside a file we don't fully own (herdr's
    config.toml). Writes through symlinks, so a dotfiles-managed file stays a link."""
    dest = Path(os.path.expanduser(dest)).resolve()
    begin, end = f"# >>> {name} (generated, do not edit) >>>", f"# <<< {name} <<<"
    cur = dest.read_text() if dest.exists() else ""
    block = f"{begin}\n{text.rstrip()}\n{end}\n"
    pat = re.compile(re.escape(begin) + r".*?" + re.escape(end) + r"\n?", re.S)
    new = pat.sub(lambda _: block, cur) if pat.search(cur) else (cur.rstrip("\n") + "\n\n" if cur else "") + block
    if new != cur:
        dest.write_text(new)


GTK3_DARK_BLUE_HUE = 0.59   # Adwaita's #15539e family: selection, focus rings, suggested-action buttons


def recolor_gtk_css(css, pal):
    """Re-theme GTK's compiled Adwaita dark stylesheet. Its colors are inlined in the rules (only a few
    refer to @named colors), so overriding @define-color alone recolors almost nothing. Greys are
    mapped through anchor points onto the palette's neutral ramp, the blue family follows the accent
    hue, and every other hue (warning/error/success) is left alone."""
    L = lambda c: to_hls(c)[1]
    bg_h, _, bg_s = to_hls(pal["bg"])
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

    ah, _, asat = to_hls(pal["accent"])
    sat_scale = 0.9 * max(0.0, min(1.0, asat / 0.6))  # a greyscale wallpaper gives greyscale selections

    def sub(m):
        raw = m.group(1)
        if len(raw) == 3:
            raw = "".join(c * 2 for c in raw)
        h, l, s = to_hls("#" + raw)
        if s < 0.12:                                   # neutral
            return hls(bg_h, grey(l), min(bg_s, 0.15))
        if hue_dist(h, GTK3_DARK_BLUE_HUE) <= 0.12:    # accent family
            return hls(ah + (h - GTK3_DARK_BLUE_HUE), min(0.7, l + 0.15), s * sat_scale)
        return m.group(0)

    return re.sub(r"#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b", sub, css)


def write_gtk_theme(pal):
    """A real, named GTK theme. Chromium (Brave's file dialogs) loads the theme by name (GTK_THEME) and
    never applies ~/.config/gtk-3.0/gtk.css, so a user-CSS-only palette left those dialogs in stock
    Adwaita blue/grey. This theme is GTK's own dark stylesheet recolored with the palette."""
    root = Path.home() / ".local/share/themes/Wall"
    (root / "gtk-3.0").mkdir(parents=True, exist_ok=True)
    (root / "gtk-4.0").mkdir(parents=True, exist_ok=True)
    stock = subprocess.run(
        ["gresource", "extract", "/usr/lib/libgtk-3.so.0", "/org/gtk/libgtk/theme/Adwaita/gtk-contained-dark.css"],
        capture_output=True, text=True,
    ).stdout
    if stock:
        css3 = recolor_gtk_css(stock, pal) + f'\n@import url("file://{OUT}/gtk.css");\n'
    else:  # no gresource tool: fall back to the named-colors-only version
        css3 = (f'@import url("resource:///org/gtk/libgtk/theme/Adwaita/gtk-contained-dark.css");\n'
                f'@import url("file://{OUT}/gtk.css");\n')
    write_atomic(root / "gtk-3.0/gtk.css", css3)
    write_atomic(root / "gtk-4.0/gtk.css",
                 f'@import url("resource:///org/gtk/libgtk/theme/Adwaita/Adwaita-dark.css");\n@import url("file://{OUT}/gtk.css");\n')
    (root / "index.theme").write_text(
        "[Desktop Entry]\nType=X-GNOME-Metatheme\nName=Wall\n"
        "Comment=GTK dark theme recolored with the wallpaper palette (generated by theme.py)\n\n"
        "[X-GNOME-Metatheme]\nGtkTheme=Wall\n"
    )
    # Wall-Glass: Wall + translucent header bars, only for Brave in GTK mode (bin/brave shim, brave_mode = "gtk")
    glass = Path.home() / ".local/share/themes/Wall-Glass"
    (glass / "gtk-3.0").mkdir(parents=True, exist_ok=True)
    write_atomic(glass / "gtk-3.0/gtk.css",
                 f'@import url("file://{root}/gtk-3.0/gtk.css");\n@import url("file://{OUT}/brave-glass.css");\n')
    (glass / "index.theme").write_text(
        "[Desktop Entry]\nType=X-GNOME-Metatheme\nName=Wall-Glass\n"
        "Comment=Wall with translucent header bars for Brave's GTK mode (generated by theme.py)\n\n"
        "[X-GNOME-Metatheme]\nGtkTheme=Wall-Glass\n"
    )
    for f in ("gtk-3.0", "gtk-4.0"):
        _sub_file(f"~/.config/{f}/settings.ini", r"^gtk-theme-name=.*$", "gtk-theme-name=Wall")
        # stock images on buttons/menus are the old GTK look (and pull in legacy icons); Adwaita has none
        for key in ("gtk-button-images", "gtk-menu-images"):
            _sub_file(f"~/.config/{f}/settings.ini", rf"^{key}=.*$", f"{key}=false")
    _sub_file("~/.gtkrc-2.0", r"^gtk-button-images=.*$", "gtk-button-images=0")
    _sub_file("~/.gtkrc-2.0", r"^gtk-menu-images=.*$", "gtk-menu-images=0")
    _sub_file("~/.config/xsettingsd/xsettingsd.conf", r'^Net/ThemeName .*$', 'Net/ThemeName "Wall"')
    _sub_file("~/.config/xsettingsd/xsettingsd.conf", r"^Gtk/ButtonImages .*$", "Gtk/ButtonImages 0")
    _sub_file("~/.config/xsettingsd/xsettingsd.conf", r"^Gtk/MenuImages .*$", "Gtk/MenuImages 0")
    if subprocess.run(["gsettings", "get", "org.gnome.desktop.interface", "gtk-theme"],
                      capture_output=True, text=True).stdout.strip("'\n ") != "Wall":
        sh("gsettings set org.gnome.desktop.interface gtk-theme Wall")


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
        return load_cfg().get("settings", {})
    except Exception:
        return {}


def write_kvantum_theme(pal, root=None, base="KvFlat"):
    """Kvantum theme "Wall" (Qt / KDE apps when the widget style is kvantum, theme.toml qt_style): KvFlat's
    SVG and kvconfig recoloured to the palette, with out/kvantum.kvconfig (translucent windows at the glass
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
    a = gtk_glass_alphas(cfg_settings())
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
    for sec, kv in parse((OUT / "kvantum.kvconfig").read_text()).items():
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
    text = "# generated by ~/.config/theme/theme.py from KvFlat + out/kvantum.kvconfig -- do not edit\n"
    text += "\n".join(f"[{sec}]\n" + "".join(f"{k}={v}\n" for k, v in kv.items()) for sec, kv in secs.items())
    write_atomic(root / "Wall/Wall.kvconfig", text)
    sel = root / "kvantum.kvconfig"
    want = "[General]\ntheme=Wall\n"
    if not sel.exists() or sel.read_text() != want:
        sel.write_text(want)
    return True


def purge_oxygen():
    """KDE leftovers: Plasma's look-and-feel was Oxygen, and ~/.config/kdedefaults supplies the
    fallback for any key kdeglobals doesn't set. Move them all to Breeze Dark / Fusion / our
    scheme. (Cursor themes are a separate choice and are left alone.)"""
    laf = Path("/usr/share/plasma/look-and-feel/org.kde.breezedark.desktop")
    cfg = Path.home() / ".config"

    def kw(file, group, key, val):
        sh(f"kwriteconfig6 --file '{cfg / file}' --group '{group}' --key {key} '{val}'")

    if laf.exists():
        kw("kdeglobals", "KDE", "LookAndFeelPackage", "org.kde.breezedark.desktop")
        (cfg / "kdedefaults").mkdir(exist_ok=True)
        pkg = cfg / "kdedefaults/package"
        if pkg.exists() and "oxygen" in pkg.read_text().lower():
            pkg.write_text("org.kde.breezedark.desktop")
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


def deploy(cfg, pal):
    link("~/.config/gtk-3.0/gtk.css", OUT / "gtk3.css")  # gtk.css + glass for CSD GTK3 windows (Gecko excluded)
    link("~/.config/gtk-4.0/gtk.css", OUT / "gtk4.css")  # gtk.css + translucent libadwaita (gtk_glass_*)

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

    style = cfg.get("settings", {}).get("qt_style")
    if style and qt.exists():  # Oxygen ignores QPalette/kdeglobals; Breeze/Fusion follow them
        txt = qt.read_text()
        new = re.sub(r"(?m)^style=.*$", f"style={style}", txt)
        if new != txt:
            qt.write_text(new)
    if style:  # KDE apps (Dolphin) take the widget style from kdeglobals instead
        sh(f"kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle {style}")

    clear_app_color_overrides()
    apply_fonts(cfg)
    write_gtk_theme(pal)
    write_kvantum_theme(pal, base=cfg.get("settings", {}).get("kvantum_base", "KvFlat"))
    apply_qt_layout(cfg)
    purge_oxygen()

    herdr = Path.home() / ".config/herdr/config.toml"
    if herdr.exists():
        inject(herdr, (OUT / "herdr.toml").read_text())


# ---------------------------------------------------------------------- brave
BRAVE_DIR = Path.home() / ".config/BraveSoftware/Brave-Browser"


def brave_running():
    return subprocess.run(["pgrep", "-x", "brave"], capture_output=True).returncode == 0


def apply_brave(cfg, pal):
    """Brave's "Use GTK theme" ignores our gtk.css (Chromium resolves GTK colors in its
    own context), so use its own seed-color theme instead: write the seed into the
    profile Preferences. A running Brave rewrites that file on exit and would discard
    the edit, so this only runs while Brave is closed -- the `brave` launcher in
    ~/.local/bin calls `theme.py brave` right before starting it. Returns True if applied."""
    s = cfg.get("settings", {})
    if not s.get("brave", True) or not BRAVE_DIR.is_dir() or brave_running():
        return False
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
            gseed = s.get("brave_gtk_seed", "")
            th = d.setdefault("browser", {}).setdefault("theme", {})
            new_th = dict(th)
            if gseed:
                gv = (0xFF << 24) | int(pal.get(gseed, pal["accent"]).lstrip("#"), 16)
                gv -= 1 << 32 if gv >= 1 << 31 else 0
                new_th.update({"user_color2": gv, "color_variant2": s.get("brave_gtk_variant", 3),
                               "color_scheme2": 2, "follows_system_colors": False})
            if ext_theme.get("system_theme") == 1 and new_th == th:
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
                   "color_scheme2": 2, "follows_system_colors": False})
        write_atomic(prefs, json.dumps(d, separators=(",", ":")))
        done = True
    return done


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
    r = subprocess.run(["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"], capture_output=True, text=True)
    return r.stdout.strip().strip("'")


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
        r = subprocess.run(["gsettings", "get", "org.gnome.desktop.interface", k], capture_output=True, text=True)
        return r.stdout.strip()

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
    if subprocess.run(["pgrep", "-x", "nautilus"], capture_output=True).returncode != 0:
        return
    out = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True).stdout
    try:
        wins = [c for c in json.loads(out) if c.get("class") == "org.gnome.Nautilus"]
    except ValueError:
        wins = []
    if wins:
        print(f"theme: nautilus has {len(wins)} window(s) open and keeps its old icons/colors; "
              "close them (or run `nautilus -q`) and reopen", file=sys.stderr)
    else:
        sh("nautilus -q")


def reload_apps(cfg):
    from concurrent.futures import ThreadPoolExecutor

    def hypr():
        sh("hyprctl reload")
        if cfg.get("settings", {}).get("restart_hyprpaper", True):
            # wait for the old process to fully exit or the new one loses the race for
            # the layer surface and silently leaves the previous wallpaper up
            sh("pkill -x hyprpaper; while pgrep -x hyprpaper >/dev/null; do sleep 0.1; done; "
               "sleep 0.3; setsid hyprpaper >/dev/null 2>&1 &")

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
def load_cfg():
    with open(ROOT / "theme.toml", "rb") as f:
        return tomllib.load(f)


def set_wallpaper(path):
    p = ROOT / "theme.toml"
    t = p.read_text()
    t = re.sub(r'(?m)^wallpaper\s*=.*$', f'wallpaper = "{path}"', t, count=1)
    p.write_text(t)


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "apply"
    if cmd == "apply" and len(argv) > 2:
        set_wallpaper(str(Path(argv[2]).expanduser().absolute()).replace(str(HOME), "~"))
    cfg = load_cfg()
    wp = Path(os.path.expanduser(cfg["wallpaper"]))
    if cmd == "brave":  # used by the launcher in ~/.local/bin: cached palette, no rendering
        cache = OUT / "extracted.json"
        base = json.loads(cache.read_text()) if cache.exists() else extract(wp)
        apply_brave(cfg, build_palette({k: base[k] for k in ("bg", "fg", "accent")}, cfg))
        return
    cache = OUT / "extracted.json"
    stale = True
    if cache.exists():
        stale = json.loads(cache.read_text()).get("wallpaper") != str(wp)  # wallpaper edited in toml
    if cmd in ("apply", "show") or stale:
        OUT.mkdir(exist_ok=True)
        base = extract(wp)
        cache.write_text(json.dumps({"wallpaper": str(wp), **base}))
    else:
        base = json.loads(cache.read_text())
        base = {k: base[k] for k in ("bg", "fg", "accent")}
    pal = build_palette(base, cfg)
    if cmd == "show":
        for k, v in pal.items():
            print(f"{k:16}{v}")
        return
    PAL[0] = pal
    render_all(pal, cfg)
    deploy(cfg, pal)
    apply_brave(cfg, pal)
    if cmd == "apply":
        reload_apps(cfg)
    print(f"theme: {wp.name}  bg {pal['bg']}  fg {pal['fg']}  accent {pal['accent']}")


if __name__ == "__main__":
    main(sys.argv)
