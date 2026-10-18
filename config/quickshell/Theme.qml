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
    readonly property int barGap: p.bar_gap
    readonly property int barRadius: p.bar_radius
    readonly property int barBorder: p.bar_border
    readonly property int rounding: p.rounding

    // layout/typography knobs shared by everything in the shell
    readonly property string font: "Paper Mono"
    readonly property int fontSize: 13
    readonly property string iconFont: "Font Awesome 7 Sharp"   // Pro desktop font, installed in ~/.local/share/fonts (not in this repo)
    readonly property int iconSize: 15      // FA glyphs are far larger than the old Nerd Font ones
    readonly property int radius: p.rounding
    readonly property int barHeight: 40
    readonly property int gap: 8

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    FileView {
        path: root.themeDir + "/out/palette.json"
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
            property int bar_gap: 0
            property int bar_radius: 0
            property int bar_border: 0
            property int rounding: 10
        }
    }
}
