pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

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
    readonly property var wallpaperDirs: p.wallpaper_dirs
    readonly property real barOpacity: p.bar_opacity
    readonly property int barBorder: p.bar_border

    // layout/typography knobs shared by everything in the shell
    readonly property string font: "Paper Mono"
    readonly property int fontSize: 13
    readonly property string iconFont: "Font Awesome 7 Sharp"   // Pro desktop font, installed in ~/.local/share/fonts (not in this repo)
    readonly property int iconSize: 15      // FA glyphs are far larger than the old Nerd Font ones
    readonly property int barHeight: 40

    // Shape and spacing: effective value = user override (Appearance.qml, appearance.json) else the
    // theme default (theme.toml [settings] -> palette.json). The palette defaults are clamped to the same
    // ranges as the overrides; legacy palette keys bar_gap / bar_radius are ignored (derived below).
    function clampInt(v, lo, hi, dflt) {
        return (typeof v !== "number" || !isFinite(v)) ? dflt : Math.max(lo, Math.min(hi, Math.round(v)))
    }
    readonly property int radius: Appearance.pick("radius", clampInt(p.rounding, 0, 32, 0))     // R, for outer elements
    readonly property int rounding: radius                  // old name, kept until every component uses radius*
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
    readonly property int popupGap: barFloating ? Math.max(4, gapOut) : 8     // popup card <-> bar
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
    Component.onCompleted: paletteFile.text()

    FileView {
        id: paletteFile
        path: root.themeDir + "/out/palette.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
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
            property var wallpaper_dirs: []
            property real bar_opacity: 0.55
            property int bar_border: 0
            property var rounding: 0
            property var gap: 0
            property var border_size: 2
            property var bar_floating: false
            property var smart_gaps: true
        }
    }
}
