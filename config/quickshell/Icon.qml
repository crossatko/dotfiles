import QtQuick

// A Font Awesome glyph (Theme.iconFont, Sharp Regular) with Label's defaults (Theme.fg, Theme.fontSize,
// vertically centred). Set text, font.pixelSize and color. Not for bar chips: those use BarIcon (ink-centred box).
Label {
    font.family: Theme.iconFont
    font.styleName: "Regular"
}
