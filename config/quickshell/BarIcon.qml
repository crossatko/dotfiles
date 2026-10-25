import QtQuick
import QtQuick.Layouts

// A glyph icon for bar chips: a fixed Theme.chipIcon square box with the glyph's RASTERISED ink centred in it.
// InkMeter renders the glyph once (same font/size) and reports its real ink edges, anti-aliasing included; the
// glyph is then moved so the ink box centre sits on the box centre: exactly (sub-pixel) horizontally; vertically the
// baseline is kept on a whole pixel (crisp strokes), so the ink can be up to 0.5 px off (near-ties: ink goes up).
// This is the one place that absorbs font ascent/descent and side bearings, so no icon needs a manual nudge.
//   measure  = string whose ink is centred (default: the glyph itself). Set it to the widest state of a glyph
//              that changes (volume levels) so the icon doesn't jump when the state changes.
//   vMeasure = same for the vertical axis only (default: measure).
//   inkLeft / inkRight = blank px between the box edges and the (measure) ink, negative when the ink overflows
//              the box; Chip uses them to give icon+label chips equal padding to the visible ink.
Item {
    id: icon
    property string text
    // qmllint disable missing-property
    property var ink: parent?.parent?.ink ?? Theme   // colour set of the enclosing Chip (see BarLabel)
    // qmllint enable missing-property
    property color color: ink.fg
    property string family: Theme.iconFont
    property string styleName: "Regular"
    property int pixelSize: Theme.iconSize
    property string measure: text
    property string vMeasure: measure

    readonly property real inkLeft: inkH.ink.ok ? glyph.x + inkH.ink.l : 0
    readonly property real inkRight: inkH.ink.ok ? width - (glyph.x + inkH.ink.r) : 0

    Layout.preferredWidth: Theme.chipIcon
    Layout.preferredHeight: Theme.chipIcon
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: Theme.chipIcon
    implicitHeight: Theme.chipIcon

    readonly property int weight: ({ Thin: 100, Light: 300, Regular: 400, Medium: 500, Bold: 700, Solid: 900, Black: 900 })[styleName] || Font.Normal
    // nearest DEVICE pixel (1/dpr logical px at fractional scales); near-ties (within 0.1 device px) move the ink up.
    // Assumes the box itself sits on the device grid (bar chips: whole logical px from the edge, 12 * scale is whole).
    function snap(v) { const k = inkH.dpr; return Math.ceil(v * k - 0.6) / k }

    InkMeter { id: inkH; text: icon.measure; family: icon.family; weight: icon.weight; pixelSize: icon.pixelSize }
    InkMeter { id: inkV; text: icon.vMeasure !== icon.measure ? icon.vMeasure : ""; family: icon.family; weight: icon.weight; pixelSize: icon.pixelSize }
    // fallback until the first measurement lands (one frame)
    TextMetrics { id: tm; text: icon.measure; font.family: icon.family; font.styleName: icon.styleName; font.pixelSize: icon.pixelSize }

    Text {
        id: glyph
        readonly property var v: inkV.text ? inkV.ink : inkH.ink
        text: icon.text
        color: icon.color
        font.family: icon.family
        font.styleName: icon.styleName
        font.pixelSize: icon.pixelSize
        // The glyph is drawn with its origin at x and its baseline at y + baselineOffset (NOT rounded: Qt places the
        // glyph quads at fractional positions); ink is relative to those.
        // x is not snapped: horizontal sub-pixel offsets render cleanly (LCD AA), so the ink lands exactly centred.
        // The baseline IS put on a whole device pixel: a fractional baseline smears horizontal strokes (hamburger
        // bars) over two rows. The vertical leftover (<= 0.5 device px, ties go up) is the price of crisp strokes.
        x: inkH.ink.ok ? icon.width / 2 - (inkH.ink.l + inkH.ink.r) / 2
                       : Math.round(icon.width / 2 - (tm.tightBoundingRect.x + tm.tightBoundingRect.width / 2))
        y: v.ok ? icon.snap(icon.height / 2 - (v.t + v.b) / 2) - baselineOffset
                : Math.round(icon.height / 2 - (baselineOffset + tm.tightBoundingRect.y + tm.tightBoundingRect.height / 2))
    }
}
