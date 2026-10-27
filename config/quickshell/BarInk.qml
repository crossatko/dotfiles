import QtQuick

// The colour set of one bar section (left / centre / right), wallpaper aware. Chip, BarIcon and BarLabel read bg fg fgDim
// muted accent accent2 red green yellow overlay, bare, hoverColor and hoverAlpha from it (Bar.qml hands it to the section, the Chip finds it).
//
// While the bar has no backdrop (`flat`) its text sits on the wallpaper, so, whatever the theme mode: dark text on a bright
// wallpaper, light text on a dark one (Theme.barInkDark / Theme.barInkLight: the theme's hues clamped to a readable
// lightness). `seg` = {mean, lo, hi} linear luminance of the wallpaper behind this section (BarContrast.segment); the
// verdict compares the contrast each ink would keep over the darkest / brightest part of it and has hysteresis (the
// verdict flips only when the other ink is clearly better), so a section never flickers on a wallpaper that sits on the edge.
// `mode`: auto (decide by seg), dark / light (force the text), off (the theme's colours, `base`). With a backdrop
// (not flat) or no data yet the set is `base` (Theme, or Theme.inkOn() in light mode), as before. Colours and the chip
// animate on a switch (Theme.popupMs, animation speed 0 = instant).
QtObject {
    id: ink

    property var base: Theme
    property var seg: null
    property bool flat: false
    property string mode: "auto"
    property real sens: 50                 // 0..100: how readily dark text is chosen (50 = neutral)
    property real fill: 0.35               // hover fill strength while flat (hoverAlpha = 0.26 / 0.32 x)
    property real inkLum: 0.8              // linear luminance of the light / dark text colours, for the contrast estimate
    property real darkLum: 0.01

    property bool darkText: false          // the verdict (hysteresis state)
    readonly property bool active: flat && mode !== "off" && (mode !== "auto" || seg !== null)
    readonly property var set: !active ? base : (mode === "dark" || (mode === "auto" && darkText)) ? Theme.barInkDark : Theme.barInkLight

    // contrast ratios of both inks over the section (middle between the mean and the extreme: busy wallpapers count, a
    // single speck does not); > 1 means the dark text is the better one
    readonly property real score: {
        if (!seg) return 1
        const lo = (seg.lo + seg.mean) / 2, hi = (seg.hi + seg.mean) / 2
        const dark = (lo + 0.05) / (darkLum + 0.05), light = (inkLum + 0.05) / (hi + 0.05)
        return dark / light * Math.pow(2, (sens - 50) / 25)
    }
    property bool seeded: false
    function decide() {
        if (!seeded) { if (seg) { darkText = score > 1; seeded = true } return }   // first data: no hysteresis
        // dark text now: it stays unless the light text is better by 15 %; light text now: dark must win by 15 %
        if (darkText ? score < 1 / 1.15 : score > 1.15) darkText = !darkText
    }
    onScoreChanged: decide()
    onSegChanged: decide()

    readonly property int ms: Theme.popupMs(Motion.baseMs * 1.5)
    property color bg: set.bg
    property color fg: set.fg
    property color fgDim: set.fgDim
    property color muted: set.muted
    property color accent: set.accent
    property color accent2: set.accent2
    property color red: set.red
    property color green: set.green
    property color yellow: set.yellow
    property color overlay: set.overlay
    // Chip fills (Chip.qml). While the bar has no backdrop (flat) a chip is fully transparent at rest: contrast comes from the
    // ink colour only. The hovered chip gets a soft wash: a grey-blue behind dark text (alpha 0.26 x fill), white behind light
    // text (0.32 x fill; light on dark needs more), so the default fill of 0.35 is ~9 % / ~11 % and 1.0 about the old strong
    // look. Active chips keep their accent fill. With a backdrop the palette's faint fill stays (`bare` false).
    readonly property bool bare: flat
    readonly property bool darkSet: set.fg.hslLightness < 0.5
    property color hoverColor: flat ? (darkSet ? Qt.rgba(0.2, 0.26, 0.36, 1) : Qt.rgba(1, 1, 1, 1)) : set.fg
    Behavior on hoverColor { ColorAnimation { duration: ink.ms } }
    readonly property real hoverAlpha: flat ? fill * (darkSet ? 0.26 : 0.32) : 0.10
    Behavior on bg { ColorAnimation { duration: ink.ms } }
    Behavior on fg { ColorAnimation { duration: ink.ms } }
    Behavior on fgDim { ColorAnimation { duration: ink.ms } }
    Behavior on muted { ColorAnimation { duration: ink.ms } }
    Behavior on accent { ColorAnimation { duration: ink.ms } }
    Behavior on accent2 { ColorAnimation { duration: ink.ms } }
    Behavior on red { ColorAnimation { duration: ink.ms } }
    Behavior on green { ColorAnimation { duration: ink.ms } }
    Behavior on yellow { ColorAnimation { duration: ink.ms } }
    Behavior on overlay { ColorAnimation { duration: ink.ms } }
}
