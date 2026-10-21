"""Adwaita-style SVG for the generated Kvantum theme "Wall" (imported by theme.py write_kvantum_theme).

libadwaita (our GTK4 glass CSS) is the design reference. The fills and sizes below were MEASURED from a libadwaita
1.10 gallery rendered with our gtk4.css (see AGENTS.md "Design match"): no bevels or gradients, translucent
currentColor fills on the glass (buttons / entries fg 10 %, hover 15 %, pressed / checked 30 %; flat buttons
hover 7 %, pressed 16 %), rounded corners (buttons / entries 9 px, popovers 12 px, rows / tabs / menu items 6 px),
20 px check boxes / radios with a 2 px fg 15 % ring, accent only for checked / suggested / progress / focus,
accent_fg (the palette bg) on accent.
Every Kvantum frame-able element is a set of nine SVG elements: the interior `<id>` plus
`<id>-top|bottom|left|right|topleft|topright|bottomleft|bottomright`; the frame width in the kvconfig must equal
the piece size here (radius + transparent margin), so the corners are quarter circles of exactly the radius.
Elements this module does not draw (arrows, grips, ...) are copied from the base theme's SVG by theme.py."""

ALPHA = {"btn": 0.10, "btn_hover": 0.15, "btn_press": 0.30, "btn_on": 0.30,
         "flat_hover": 0.07, "flat_press": 0.16, "flat_on": 0.10,
         "row_hover": 0.05, "row_sel": 0.10, "tab_sel": 0.10, "tab_hover": 0.05,
         "groove": 0.15, "scroll": 0.35, "check_border": 0.15}

# piece sizes the kvconfig template relies on (frame.* = radius + margin); keep both in sync
ROW_MX, ROW_MY, ROW_R = 0, 0, 6   # list / sidebar rows: Kvantum caps ItemView frames (and text margins) at 6 px, so no inset


def _rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


class Svg:
    def __init__(self):
        self.parts, self.x = [], 10

    def _fill(self, color, a):
        return f'fill="{color}" fill-opacity="{a:.3f}"' if a > 0 else 'fill="#000000" fill-opacity="0"'

    def box(self, ident, r, color, a, stroke=None, sa=0.0, sw=0, mx=0, my=0):
        """Nine-piece rounded box: corners radius r, optional inner stroke (sw px) of colour `stroke`, and a
        transparent outer margin mx (left / right) / my (top / bottom), so the frame pieces are (r + m) wide."""
        r = max(1, r)
        x0, y0, cw, ch = self.x, 10, r + mx, r + my
        f = self._fill(color, a)
        st = f'fill="{stroke}" fill-opacity="{sa:.3f}"' if stroke and sw else None
        clear = 'fill="#000000" fill-opacity="0.001"'   # not 0: QtSvg leaves fully transparent shapes out of an element's bounds
        p = [f'<rect id="{ident}" x="{x0 + cw}" y="{y0 + ch}" width="{r}" height="{r}" {f}/>']
        # edges: piece box, filled part (inner side), stroke strip (outer side of the fill)
        ix, iy = x0 + cw, y0 + ch          # inner top-left corner point
        ex, ey = x0 + cw + r, y0 + ch + r  # inner bottom-right corner point
        edges = {"top": ((ix, y0, r, ch), (ix, y0 + my, r, r), (ix, y0 + my, r, sw)),
                 "bottom": ((ix, ey, r, ch), (ix, ey, r, r), (ix, ey + r - sw, r, sw)),
                 "left": ((x0, iy, cw, r), (x0 + mx, iy, r, r), (x0 + mx, iy, sw, r)),
                 "right": ((ex, iy, cw, r), (ex, iy, r, r), (ex + r - sw, iy, sw, r))}
        for name, (box, fill, strip) in edges.items():
            g = [f'<rect x="{box[0]}" y="{box[1]}" width="{box[2]}" height="{box[3]}" {clear}/>',
                 f'<rect x="{fill[0]}" y="{fill[1]}" width="{fill[2]}" height="{fill[3]}" {f}/>']
            if st:
                g.append(f'<rect x="{strip[0]}" y="{strip[1]}" width="{strip[2]}" height="{strip[3]}" {st}/>')
            p.append(f'<g id="{ident}-{name}">' + "".join(g) + "</g>")
        # corners: piece box + quarter disc around the inner corner point (+ annulus for the stroke)
        corners = {"topleft": (x0, y0, ix, iy, -1, -1), "topright": (ex, y0, ex, iy, 1, -1),
                   "bottomleft": (x0, ey, ix, ey, -1, 1), "bottomright": (ex, ey, ex, ey, 1, 1)}
        for name, (bx, by, cx, cy, sx, sy) in corners.items():
            sweep = 1 if sx * sy > 0 else 0
            g = [f'<rect x="{bx}" y="{by}" width="{cw}" height="{ch}" {clear}/>',
                 f'<path d="M{cx},{cy} L{cx + sx * r},{cy} A{r},{r} 0 0 {sweep} {cx},{cy + sy * r} Z" {f}/>']
            if st:
                ri = max(0, r - sw)
                g.append(f'<path d="M{cx + sx * r},{cy} A{r},{r} 0 0 {sweep} {cx},{cy + sy * r} '
                         f'L{cx},{cy + sy * ri} A{ri},{ri} 0 0 {1 - sweep} {cx + sx * ri},{cy} Z" {st}/>')
            p.append(f'<g id="{ident}-{name}">' + "".join(g) + "</g>")
        self.parts += p
        self.x += 2 * cw + r + 10

    def icon(self, ident, size, body, h=None):
        """One plain element of size x size (or size x h); `body` gets (x, y) and returns SVG markup."""
        x0, y0, h = self.x, 10, h or size
        self.parts.append(f'<g id="{ident}"><rect x="{x0}" y="{y0}" width="{size}" height="{h}" '
                          f'fill="#000000" fill-opacity="0"/>{body(x0, y0)}</g>')
        self.x += size + 10

    def text(self, extra=""):
        return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="200">\n' % (self.x + 10)
                + "\n".join(self.parts) + "\n" + extra + "\n</svg>\n")


def build(pal, view_alpha, menu_alpha):
    """Return the SVG markup (without the copied base elements)."""
    fg, bg, acc, surf = pal["fg"], pal["bg"], pal["accent"], pal["surface"]
    acc_fg = bg   # libadwaita accent_fg_color in out/gtk.css
    s = Svg()
    A = ALPHA
    base_box = s.box
    def ebox(ident, *a, **k):
        """box + its "expand-" twin: with frame.expansion (kvconfig) Kvantum draws the expand- element with
        expansion / 2 px corners while the logical frame (padding) stays smaller (34 px buttons with 9 px corners)"""
        base_box(ident, *a, **k); base_box("expand-" + ident, *a, **k)
    # push buttons (PanelButtonCommand / ComboBox): 9 px, currentColor fills
    ebox("button-normal", 9, fg, A["btn"]); ebox("button-focused", 9, fg, A["btn_hover"])
    ebox("button-pressed", 9, fg, A["btn_press"]); ebox("button-toggled", 9, fg, A["btn_on"])
    ebox("button-disabled", 9, fg, A["btn"] / 2)
    # default ("suggested") button: Kvantum draws a default push button with the status "default"
    # (button-default-*); the corner indicator is drawn empty
    ebox("button-default", 9, acc, 1.0)
    s.icon("button-default-indicator", 8, lambda x, y: "")
    # tool buttons: flat until hovered (libadwaita header bar / flat buttons)
    ebox("tbutton-normal", 9, fg, 0); ebox("tbutton-focused", 9, fg, A["flat_hover"])
    ebox("tbutton-pressed", 9, fg, A["flat_press"]); ebox("tbutton-toggled", 9, fg, A["btn_on"])
    # entries: same fill as buttons, accent focus ring (2 px, 50 %)
    ebox("lineedit-normal", 9, fg, A["btn"]); ebox("lineedit-focused", 9, fg, A["btn"], acc, 0.5, 2)
    ebox("lineedit-disabled", 9, fg, A["btn"] / 2)
    # item views (lists, sidebars, trees, combo popups): 6 px rounded rows like libadwaita's
    # navigation sidebar / popover lists; selection fg 10 %, hover 5 %
    for st, a in (("normal", 0), ("focused", A["row_hover"]), ("pressed", A["row_sel"]), ("toggled", A["row_sel"])):
        s.box(f"itemview-{st}", ROW_R, fg, a, mx=ROW_MX, my=ROW_MY)
        # unfocused windows: Kvantum asks for "<element>-inactive" and has no usable fallback for view items
        s.box(f"itemview-{st}-inactive", ROW_R, fg, a, mx=ROW_MX, my=ROW_MY)
    # frames: libadwaita draws none; a view frame is just the view background
    s.box("common-normal", 6, bg, 0); s.box("common-focused", 6, bg, 0)
    # group boxes = libadwaita cards / boxed lists (12 px, card colour at the view layer alpha)
    s.box("group-normal", 12, surf, view_alpha)
    # menus = popovers (12 px), items 6 px
    # padding 6 (frame.* in the kvconfig) with 12 px corners via frame.expansion=24 -> expand-menu-normal
    s.box("menu-normal", 12, surf, menu_alpha); s.box("expand-menu-normal", 12, surf, menu_alpha)
    # separator: 1 px line, 6 px above / below (13 px = menu_separator_height)
    s.icon("menuitem-separator", 20, lambda x, y: f'<rect x="{x}" y="{y+6}" width="20" height="1" fill="{fg}" fill-opacity="0.15"/>', h=13)
    s.box("menuitem-focused", 6, fg, A["flat_hover"]); s.box("menuitem-pressed", 6, fg, A["flat_press"])
    s.box("menuitem-toggled", 6, fg, A["flat_press"])
    s.box("menubaritem-focused", 6, fg, A["flat_hover"]); s.box("menubaritem-toggled", 6, fg, A["flat_press"])
    # tooltips
    s.box("tooltip-normal", 9, surf, 0.95)
    # tabs: AdwTabBar, selected tab a soft pill, frame invisible
    s.box("tab-normal", 6, fg, 0); s.box("tab-focused", 6, fg, A["tab_hover"]); s.box("tab-toggled", 6, fg, A["tab_sel"])
    s.box("tabframe-normal", 9, fg, 0)
    # tab close button: window-close-symbolic in a 24 px circle on hover
    def xmark(hl):
        def body(x, y):
            c = (f'<circle cx="{x+8}" cy="{y+8}" r="8" fill="{fg}" fill-opacity="{hl:.2f}"/>' if hl else "")
            return c + (f'<path d="M{x+5},{y+5} L{x+11},{y+11} M{x+11},{y+5} L{x+5},{y+11}" stroke="{fg}" '
                        'stroke-width="1.5" stroke-linecap="round" fill="none"/>')
        return body
    for st, hl in (("normal", 0), ("focused", A["flat_hover"]), ("pressed", A["flat_press"]), ("toggled", 0)):
        s.icon(f"tab-close-{st}", 16, xmark(hl))
    # toolbars / header sections: flat on the glass
    s.box("toolbar-normal", 1, fg, 0); s.box("header-normal", 3, fg, 0); s.box("header-focused", 3, fg, A["row_hover"])
    # slider: 4 px groove, accent fill, 20 px light knob
    knob = "#f0f0f0"
    s.box("slider-normal", 2, fg, A["groove"]); s.box("slider-toggled", 2, acc, 1.0)
    s.icon("slidercursor-normal", 20, lambda x, y: f'<circle cx="{x+10}" cy="{y+10}" r="10" fill="{knob}"/>')
    s.icon("slidercursor-focused", 20, lambda x, y: f'<circle cx="{x+10}" cy="{y+10}" r="10" fill="#ffffff"/>')
    s.icon("slidercursor-pressed", 20, lambda x, y: f'<circle cx="{x+10}" cy="{y+10}" r="10" fill="#e0e0e0"/>')
    s.icon("slidercursor-disabled", 20, lambda x, y: f'<circle cx="{x+10}" cy="{y+10}" r="10" fill="{fg}" fill-opacity="0.4"/>')
    # progress: 8 px groove + accent (libadwaita progressbar trough)
    s.box("progress-normal", 4, fg, A["groove"]); s.box("progress-pattern-normal", 4, acc, 1.0)
    s.box("progress-pattern-disabled", 4, fg, 0.3)
    # scrollbars: no groove, thin pill slider (also the transient / overlay slider "ss")
    s.box("scrollbargroove-normal", 3, fg, 0)
    s.box("scrollbarslider-normal", 4, fg, A["scroll"]); s.box("scrollbarslider-focused", 4, fg, A["scroll"] + 0.15)
    s.box("scrollbarslider-pressed", 4, fg, A["scroll"] + 0.25)
    s.box("ss-normal", 3, fg, A["scroll"]); s.box("ss-focused", 3, fg, A["scroll"] + 0.15)
    s.box("ss-pressed", 3, fg, A["scroll"] + 0.25)
    # spin box +/- (libadwaita list-remove / list-add symbolic, 16 px)
    def pm(plus, a):
        def body(x, y):
            d = f"M{x+3},{y+8} L{x+13},{y+8}" + (f" M{x+8},{y+3} L{x+8},{y+13}" if plus else "")
            return f'<path d="{d}" stroke="{fg}" stroke-opacity="{a}" stroke-width="2" stroke-linecap="round" fill="none"/>'
        return body
    # IndicatorSpinBox uses indicator.element=spin: spin-up = +, spin-down = - (arrow-* stay arrows for combos)
    for st, a in (("normal", 1), ("focused", 1), ("pressed", 1), ("disabled", 0.35)):
        s.icon(f"arrow-plus-{st}", 16, pm(True, a)); s.icon(f"arrow-minus-{st}", 16, pm(False, a))
        s.icon(f"spin-up-{st}", 16, pm(True, a)); s.icon(f"spin-down-{st}", 16, pm(False, a))
    # check boxes / radios: 20 px, 2 px fg 15 % ring -> accent fill with an accent_fg mark
    chk = "M{a},{b} l3.5,3.5 l7,-7.5"
    def cb(checked, focused, tri=False):
        def body(x, y):
            ring = (f'<rect x="{x+1}" y="{y+1}" width="18" height="18" rx="5" fill="{acc if checked else "none"}" '
                    f'stroke="{acc if checked else fg}" stroke-opacity="{1 if checked else A["check_border"]}" stroke-width="2"/>')
            if tri:
                mark = (f'<path d="M{x+6},{y+10} L{x+14},{y+10}" stroke="{acc_fg}" stroke-width="2" stroke-linecap="round"/>')
            elif checked:
                mark = (f'<path d="{chk.format(a=x+5, b=y+10)}" fill="none" stroke="{acc_fg}" stroke-width="2" '
                        'stroke-linecap="round" stroke-linejoin="round"/>')
            else:
                mark = ""
            foc = (f'<rect x="{x}" y="{y}" width="20" height="20" rx="6" fill="none" stroke="{acc}" stroke-opacity="0.5"/>'
                   if focused else "")
            return ring + mark + foc
        return body
    for st, (c, f, t) in {"normal": (0, 0, 0), "focused": (0, 1, 0), "checked-normal": (1, 0, 0),
                          "checked-focused": (1, 1, 0), "tristate-normal": (1, 0, 1), "tristate-focused": (1, 1, 1)}.items():
        s.icon(f"checkbox-{st}", 20, cb(c, f, t))
    def rb(checked, focused):
        def body(x, y):
            ring = (f'<circle cx="{x+10}" cy="{y+10}" r="9" fill="{acc if checked else "none"}" stroke="{acc if checked else fg}" '
                    f'stroke-opacity="{1 if checked else A["check_border"]}" stroke-width="2"/>')
            dot = f'<circle cx="{x+10}" cy="{y+10}" r="4" fill="{acc_fg}"/>' if checked else ""
            foc = f'<circle cx="{x+10}" cy="{y+10}" r="9.5" fill="none" stroke="{acc}" stroke-opacity="0.5"/>' if focused else ""
            return ring + dot + foc
        return body
    for st, (c, f) in {"normal": (0, 0), "focused": (0, 1), "checked-normal": (1, 0), "checked-focused": (1, 1)}.items():
        s.icon(f"radio-{st}", 20, rb(c, f))
    return s
