pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Live view of ~/.config/theme/out/palette.json. theme.py rewrites that file
// atomically, FileView watches it, so every binding in the shell restyles the
// moment a wallpaper is applied -- no restart.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string themeDir: home + "/.config/theme"

    readonly property color bg: p.bg
    readonly property color bgAlt: p.bg_alt
    readonly property color surface: p.surface
    readonly property color surface2: p.surface2
    readonly property color overlay: p.overlay
    readonly property color muted: p.muted
    readonly property color fgDim: p.fg_dim
    readonly property color fg: p.fg
    readonly property color accent: p.accent
    readonly property color accent2: p.accent2
    readonly property color red: p.red
    readonly property color green: p.green
    readonly property color yellow: p.yellow
    readonly property color blue: p.blue
    readonly property color magenta: p.magenta
    readonly property color cyan: p.cyan
    readonly property color orange: p.orange
    readonly property string wallpaper: p.wallpaper
    readonly property string mode: p.mode === "light" ? "light" : "dark"   // light / dark theme (theme.py mode, Settings > Wallpaper & theme)
    readonly property bool light: mode === "light"
    readonly property var wallpaperDirs: p.wallpaper_dirs
    readonly property var videoDirs: p.video_dirs && p.video_dirs.length > 0 ? p.video_dirs : [home + "/Videos/wallpapers"]   // video wallpapers (mp4/webm/mkv), see SettingsWallpaper.qml
    readonly property real barOpacity: p.bar_opacity
    // Glass look: on while the running Hyprland draws decoration:blur:variant solid_glass (the blur fork). Anything else
    // (stock Hyprland without that variant, kawase, blur off, no hyprctl) keeps the original, more opaque fills, which
    // the qs-.* layer rule blurs as before. Re-checked on every config reload.
    property bool glass: false
    property bool glassKnown: false     // false until the first check finished
    // true when the running Hyprland fades a layer's glass with the layer's own alpha (fork option
    // decoration:blur:solid_glass:layer_alpha_ref > 0, set by managed.lua when the option exists): a card fading its
    // opacity then fades its glass too. false (installed build without the option): the glass is drawn at full
    // strength whatever the card's opacity, so it would stay as a dark empty box after the content has faded and
    // vanish in one frame (measured 2026-10-21); glassScaleAt() then shrinks the glass instead in the last part.
    property bool glassFades: false
    // fill alpha of glass cards (popups, OSD, toasts): low enough for the lens / rim to show; else the original fill
    // Per colour mode (theme.toml [settings] = dark, [settings_light] = light; palette.json carries the active mode's):
    // card_fill on solid_glass (light: a pale card needs a much stronger fill to keep its dark text readable; theme.py
    // uses the same value for GTK / Qt windows), plain_fill_min = floor of every fill without solid_glass
    readonly property real cardFill: glass ? p.card_fill : Math.max(Math.min(1, barOpacity + 0.3), p.plain_fill_min)
    // fill alpha of the bar container: like the cards on glass, else the bar_opacity setting over the plain blur
    readonly property real barFill: glass ? cardFill : Math.max(barOpacity, p.plain_fill_min)

    // Text drawn straight on the wallpaper (a bar without backdrop, Settings > Bar "transparent when flush"): the
    // wallpaper is the same in both modes, so light mode's dark text would vanish on a dark wallpaper. In light mode
    // palette.json carries the dark palette's colours ("dark") and, per monitor and edge, which palette reads on the
    // wallpaper strip under the bar ("wall_ink", theme.py wall_inks). inkOn() -> Theme itself or darkInk; both have
    // the colour properties the bar uses (bg fg fgDim muted accent accent2 red green yellow overlay).
    readonly property QtObject darkInk: QtObject {
        readonly property color bg: p.dark?.bg ?? root.bg
        readonly property color fg: p.dark?.fg ?? root.fg
        readonly property color fgDim: p.dark?.fg_dim ?? root.fgDim
        readonly property color muted: p.dark?.muted ?? root.muted
        readonly property color accent: p.dark?.accent ?? root.accent
        readonly property color accent2: p.dark?.accent2 ?? root.accent2
        readonly property color red: p.dark?.red ?? root.red
        readonly property color green: p.dark?.green ?? root.green
        readonly property color yellow: p.dark?.yellow ?? root.yellow
        readonly property color overlay: p.dark?.overlay ?? root.overlay
    }
    function inkOn(screenName, atTop) {
        if (!light) return root
        const w = p.wall_ink ?? {}
        const e = w[screenName] ?? w["*"] ?? {}
        return (atTop ? e.top : e.bottom) === "light" ? root : darkInk
    }
    // Bar text on a bare wallpaper (BarInk.qml, wallpaper aware, any theme mode): the theme's own hues clamped to a lightness
    // that reads on a dark wallpaper (barInkLight: light text, dark chip pill) or a bright one (barInkDark: dark text,
    // light chip pill). Same property names as Theme / darkInk.
    function tone(c, lo, hi, maxSat) {
        return Qt.hsla(Math.max(0, c.hslHue), Math.min(maxSat, c.hslSaturation), Math.max(lo, Math.min(hi, c.hslLightness)), 1)
    }
    readonly property QtObject barInkLight: QtObject {
        readonly property color bg: root.tone(root.bg, 0.05, 0.14, 0.5)
        readonly property color fg: root.tone(root.fg, 0.92, 0.97, 0.25)
        readonly property color fgDim: root.tone(root.fgDim, 0.82, 0.92, 0.35)
        readonly property color muted: root.tone(root.muted, 0.76, 0.88, 0.4)
        readonly property color accent: root.tone(root.accent, 0.66, 0.85, 1)
        readonly property color accent2: root.tone(root.accent2, 0.66, 0.85, 1)
        readonly property color red: root.tone(root.red, 0.66, 0.85, 1)
        readonly property color green: root.tone(root.green, 0.62, 0.85, 1)
        readonly property color yellow: root.tone(root.yellow, 0.62, 0.85, 1)
        readonly property color overlay: root.tone(root.overlay, 0.2, 0.4, 0.5)
    }
    readonly property QtObject barInkDark: QtObject {
        readonly property color bg: root.tone(root.bg, 0.92, 0.99, 0.5)
        readonly property color fg: root.tone(root.fg, 0.04, 0.09, 0.25)
        readonly property color fgDim: root.tone(root.fgDim, 0.10, 0.18, 0.35)
        readonly property color muted: root.tone(root.muted, 0.14, 0.24, 0.4)
        readonly property color accent: root.tone(root.accent, 0.18, 0.32, 1)
        readonly property color accent2: root.tone(root.accent2, 0.18, 0.32, 1)
        readonly property color red: root.tone(root.red, 0.20, 0.34, 1)
        readonly property color green: root.tone(root.green, 0.16, 0.28, 1)
        readonly property color yellow: root.tone(root.yellow, 0.16, 0.26, 1)
        readonly property color overlay: root.tone(root.overlay, 0.6, 0.8, 0.5)
    }
    function checkGlass() { glassProbe.running = true }
    Process {
        id: glassProbe
        command: ["hyprctl", "-j", "--batch", "getoption decoration:blur:enabled ; getoption decoration:blur:variant ; getoption decoration:blur:solid_glass:layer_alpha_ref"]
        stdout: StdioCollector {
            onStreamFinished: {
                const en = /"decoration:blur:enabled",\s*"(?:bool|int)":\s*(true|1)\b/.test(text)
                const va = /"decoration:blur:variant",\s*"int":\s*(\d+)/.exec(text)
                root.glass = en && va !== null && va[1] === "11"      // 11 = solid_glass
                const rf = /"decoration:blur:solid_glass:layer_alpha_ref",\s*"float":\s*([\d.eE+-]+)/.exec(text)
                root.glassFades = rf !== null && parseFloat(rf[1]) > 0
                root.glassKnown = true
            }
        }
        onExited: root.glassKnown = true
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "configreloaded") root.checkGlass() }
    }
    readonly property int barBorder: p.bar_border

    // layout/typography knobs shared by everything in the shell
    readonly property string font: "Paper Mono"
    readonly property int fontSize: 13      // body text (Label default)
    readonly property int fontTitle: 17     // popup / modal / Settings sidebar title
    readonly property int fontSmall: 12     // buttons, secondary lines, values next to sliders
    readonly property int fontCaption: 11   // sub lines under a row title, captions, hints, section heads
    readonly property int fontTiny: 10      // badges and footnotes
    readonly property string iconFont: "Font Awesome 7 Sharp"   // Pro desktop font, installed in ~/.local/share/fonts (not in this repo)
    readonly property string iconFontPro: "Font Awesome 7 Pro"   // Pro desktop font (Solid for filled glyphs), installed in ~/.local/share/fonts
    readonly property string brandFont: "Font Awesome 7 Brands" // brand logos (system package)
    readonly property int iconSize: 15      // FA glyphs are far larger than the old Nerd Font ones
    readonly property int barHeight: 40

    // Shape and spacing: effective value = user override (Appearance.qml, appearance.json) else the
    // theme default (theme.toml [settings] -> palette.json). The palette defaults are clamped to the same
    // ranges as the overrides; legacy palette keys bar_gap / bar_radius are ignored (derived below).
    function clampInt(v, lo, hi, dflt) {
        return (typeof v !== "number" || !isFinite(v)) ? dflt : Math.max(lo, Math.min(hi, Math.round(v)))
    }
    readonly property int radius: Appearance.pick("radius", clampInt(p.rounding, 0, 32, 0))     // R, for outer elements
    readonly property int gap: Appearance.pick("gap", clampInt(p.gap, 0, 32, 0))                // window gap G
    readonly property int gapIn: Math.round(gap / 2)        // Hyprland gaps_in (visible gap between windows ~ G)
    readonly property int gapOut: Appearance.pick("edgeGap", gap)                               // Hyprland gaps_out (screen edge)
    readonly property int borderSize: Appearance.pick("border", clampInt(p.border_size, 0, 6, 2))
    readonly property bool barFloating: Appearance.pick("barFloating", p.bar_floating === true)
    readonly property bool smartGaps: Appearance.pick("smartGaps", p.smart_gaps !== false)

    // bar: docked = flush with the screen edge, square; floating = gapOut away from the edge and both sides, radius R
    readonly property int barGap: barFloating ? gapOut : 0
    readonly property int barRadius: barFloating ? radius : 0
    readonly property int barPad: 6                          // chip inset inside the bar
    readonly property int barReserve: barHeight + barGap     // screen space the bar takes from its edge
    // bar chip geometry (Chip.qml / BarIcon.qml): every chip is chipHeight tall; an icon-only chip is a chipHeight square
    // (icon box centred, equal padding on all four sides); a chip with a label has chipPadX left/right; icon <-> label = chipGap
    readonly property int chipHeight: barHeight - 2 * barPad // 28
    readonly property int chipPadX: 10
    readonly property int chipGap: 6
    readonly property int chipIcon: 16                      // fixed square box every bar icon is centred in (by its ink bounds)
    readonly property int popupGap: barFloating ? Math.max(4, gapOut) : 8     // popup card <-> bar
    // gap between adjacent controls (the 6 of Settings rows / button groups, = chipGap; blocks are 2x apart)
    readonly property int controlGap: 6
    // popup motion (PopupHost.qml), ms: open fade/scale-in, close fade-out, card glide + resize when switching chips,
    // old content fading out / new content fading in during a switch
    // Base values at speed 1 (Settings -> Animations: Motion.qml, animations.json): duration = base / popupSpeed,
    // style "none" = 0 (instant)
    readonly property real popupSpeedK: Motion.popupStyle === "none" ? 0 : 1 / Motion.popupSpeed
    // floor of one frame (16 ms) for any animated value, so 10x never gives 1-7 ms steps
    function popupMs(base) { return popupSpeedK === 0 ? 0 : Math.max(16, Math.round(base * popupSpeedK)) }
    // 1x = Motion.baseMs (shared with Hyprland); the switch's content fades are 35 % / 65 % of it
    readonly property int popupOpenMs: popupMs(Motion.baseMs)
    readonly property int popupCloseMs: popupMs(Motion.baseMs * 0.75)    // close = 0.75 x open
    readonly property int popupMoveMs: popupMs(Motion.baseMs)
    readonly property int popupFadeOutMs: popupMs(Motion.baseMs * 0.35)
    readonly property int popupFadeInMs: popupMs(Motion.baseMs * 0.65)
    // feedback motion: one half of the "busy" pulse (Toggle knob, RowState glyph, lock dots; not speed-scaled: it is a
    // state, not a transition) and the wrong-password shake (whole run, speed-scaled) with its amplitude
    readonly property int busyPulseMs: 380
    readonly property int shakeMs: popupMs(Motion.baseMs * 1.5)
    readonly property int shakePx: 10
    // how much the lock screen darkens the wallpaper (x (1 - dim), a black veil in LockView): the blurred backdrop and what the glass
    // clock / dots refract (GlassShape `dim`) use the same amount
    readonly property real lockDim: LockPrefs.dim    // Settings > Lock "Wallpaper dim" (default 0.5)
    readonly property int lockRevealMs: popupMs(Motion.baseMs * 2.5)   // lock screen -> desktop transition after unlock
    // curve (Motion.popupCurve): open / move ease out (Back overshoots); close = the same family decelerating WITHOUT
    // overshoot (Back closes with OutCubic), so it is visible to the very end: no last-frame drop from an ease-in, no
    // crossing of 0 before the end (2026-10-20; before: In* curves, and Back closed early, see PopupHost)
    readonly property int popupEaseOpen: ({ quint: Easing.OutQuint, expo: Easing.OutExpo, back: Easing.OutBack, linear: Easing.Linear })[Motion.popupCurve] ?? Easing.OutCubic
    readonly property int popupEaseClose: ({ quint: Easing.OutQuint, expo: Easing.OutExpo, linear: Easing.Linear })[Motion.popupCurve] ?? Easing.OutCubic
    readonly property int popupEaseMove: popupEaseOpen
    // Glass of a card in open / close motion at progress t (1 = open), as a scale of the card's glass region about its
    // centre (Glass.qml `glassScale`). With a fading glass (glassFades) always 1: the glass fades with the card. Without
    // it the glass cannot fade, so below t = glassTailFrom (content <= 15 % visible) the region shrinks instead,
    // linearly in time for the cubic curves (cube roots), down to nothing at t = 0.005 (Glass.qml drops a region
    // below opacity 0.004 anyway: ending there left a 30 % box that vanished at once, measured), so the last glass
    // frame is a tiny one rather than the full card vanishing at once.
    readonly property real glassTailFrom: 0.15
    function glassScaleAt(t) {
        if (glassFades || t >= glassTailFrom) return 1
        const a = Math.cbrt(Math.max(0, t)), e = Math.cbrt(0.005)
        return Math.max(0, (a - e) / (Math.cbrt(glassTailFrom) - e))
    }
    // style (Motion.popupStyle): scale = fade + scale 0.96 -> 1 + 10 px slide (default); slide = fade + 24 px
    // slide; fade = fade only; none = instant
    readonly property real popupScaleFrom: Motion.popupStyle === "scale" ? 0.96 : 1
    readonly property real popupSlidePx: Motion.popupStyle === "scale" ? 10 : Motion.popupStyle === "slide" ? 24 : 0
    readonly property int edgeGap: barFloating ? gapOut : 12                  // popups/toasts <-> screen edge

    // Concentric inner radius: an element inset by `inset` inside one of radius `outer`.
    // Exactly 0 when outer is 0; never below min(outer, 4) otherwise.
    function inner(outer, inset) { return outer <= 0 ? 0 : Math.max(Math.min(outer, 4), outer - inset) }
    readonly property int radiusChip: inner(radius, barPad)     // chips inside the bar
    readonly property int radiusItem: inner(radius, 12)         // items inside a popup card / panel
    readonly property int radiusPage: inner(radius, 18)         // Settings page content inside the card
    readonly property int radiusDeep: inner(radiusItem, 8)      // something inside an item
    readonly property int radiusModal: inner(radius, 20)        // modal cards

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // first read is synchronous, so shape defaults (bar_floating, rounding, gap) are right on the first frame
    Component.onCompleted: { paletteFile.text(); checkGlass() }

    FileView {
        id: paletteFile
        path: root.themeDir + "/out/palette.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        // qmllint disable missing-type
        // false positive: Quickshell's qmltypes name this property's type "FileViewAdapter" instead of "qs::io::FileViewAdapter"
        adapter: p
        // qmllint enable missing-type
    }

    JsonAdapter {
        id: p
        property string bg: "#131313"
        property string bg_alt: "#181818"
        property string surface: "#20201f"
        property string surface2: "#2b2a2a"
        property string overlay: "#464545"
        property string muted: "#727170"
        property string fg_dim: "#9c9a98"
        property string fg: "#c9c7c5"
        property string accent: "#cf5b59"
        property string accent2: "#809cc6"
        property string red: "#c68080"
        property string green: "#82c680"
        property string yellow: "#c6b380"
        property string blue: "#809cc6"
        property string magenta: "#c580c6"
        property string cyan: "#80c6c6"
        property string orange: "#c69980"
        property string wallpaper: ""
        property string mode: "dark"
        property var wallpaper_dirs: []
        property var video_dirs: []
        property real bar_opacity: 0.55
        property real card_fill: 0.3
        property real plain_fill_min: 0
        property var dark: ({})        // light mode only: the dark palette's text colours (darkInk)
        property var wall_ink: ({})    // light mode only: {"*" | connector: {top, bottom: "light" | "dark"}} (inkOn)
        property int bar_border: 0
        property var rounding: 0
        property var gap: 0
        property var border_size: 2
        property var bar_floating: false
        property var smart_gaps: true
    }
}
