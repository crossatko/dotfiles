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


def render_all(pal, cfg):
    OUT.mkdir(exist_ok=True)
    wp = str(Path(os.path.expanduser(cfg["wallpaper"])))
    extra = {"wallpaper": wp, "home": str(HOME), **{k: v for k, v in cfg.get("vars", {}).items()}}
    for tpl in sorted((ROOT / "templates").iterdir()):
        dest = OUT / tpl.name
        write_atomic(dest, render(tpl.read_text(), pal, extra))
    dirs = [os.path.expanduser(d) for d in cfg.get("wallpaper_dirs", ["~/Pictures/wallpapers"])]
    s = cfg.get("settings", {})
    ui = {"bar_opacity": s.get("bar_opacity", 0.55),
          "bar_gap": s.get("bar_gap", 0), "bar_radius": s.get("bar_radius", 0),
          "bar_border": s.get("bar_border", 0), "rounding": s.get("rounding", 10)}
    write_atomic(OUT / "palette.json", json.dumps({"wallpaper": wp, "wallpaper_dirs": dirs, **ui, **pal}, indent=2) + "\n")
    lua = "return {\n" + f'  wallpaper = "{wp}",\n  rounding = {s.get("rounding", 10)},\n' + "".join(f'  {k} = "{v}",\n' for k, v in pal.items()) + "}\n"
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
    link("~/.config/gtk-3.0/gtk.css", OUT / "gtk.css")
    link("~/.config/gtk-4.0/gtk.css", OUT / "gtk.css")

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
        ext_theme["system_theme"] = 0  # leave "GTK" mode, it can't follow our colors
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
    for q in ("qt5ct/qt5ct.conf", "qt6ct/qt6ct.conf"):
        _sub_file(f"~/.config/{q}", r"^icon_theme=.*$", f"icon_theme={name}")
    _sub_file("~/.config/xsettingsd/xsettingsd.conf", r'^Net/IconThemeName .*$', f'Net/IconThemeName "{name}"')
    sh(f"kwriteconfig6 --file kdeglobals --group Icons --key Theme {name}")  # KDE apps (Dolphin, ...)


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
