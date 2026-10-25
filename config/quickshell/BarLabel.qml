import QtQuick
import QtQuick.Layouts

// Label for use inside bar chips. Every one fills the chip's full height with its text centered in that
// box, so text and icons of different fonts / sizes in different chips share one vertical center (with
// plain Labels each is only as tall as its own font, so a chip containing an 18px icon pushed its
// neighbours' text up or down).
// inkLeft / inkRight = blank px between this item's edges and the text's visible ink (side bearings plus alignment
// slack, measured by InkMeter); Chip uses them to pad icon+label chips evenly to the ink.
Text {
    id: lbl
    // colour set: the enclosing Chip's (Theme, or Theme.darkInk on a light-mode bar without backdrop, Bar.qml ink), else Theme
    // qmllint disable missing-property
    property var ink: parent?.parent?.ink ?? Theme   // parent = the Chip's row, its parent the Chip
    // qmllint enable missing-property
    color: ink.fg
    font.family: Theme.font
    font.pixelSize: Theme.fontSize
    verticalAlignment: Text.AlignVCenter
    Layout.fillHeight: true

    // where the text run starts inside the item (horizontalAlignment)
    readonly property real textX: (horizontalAlignment & Text.AlignRight) ? width - contentWidth
                                : (horizontalAlignment & Text.AlignHCenter) ? (width - contentWidth) / 2 : 0
    readonly property real inkLeft: inkM.ink.ok ? textX + inkM.ink.l : 0
    // elided: the run is cut to whole characters + "…" (fixed advance assumed: the bar font is monospace)
    readonly property real inkRight: !inkM.ink.ok ? 0
        : !truncated ? width - (textX + inkM.ink.r)
        : inkE.ink.ok ? width - (Math.floor(width / (inkM.ink.adv / text.length)) - 1) * (inkM.ink.adv / text.length) - inkE.ink.r : 0

    InkMeter { id: inkM; text: lbl.text; family: lbl.font.family; weight: lbl.font.weight; pixelSize: lbl.font.pixelSize }
    InkMeter { id: inkE; text: lbl.truncated ? "…" : ""; family: lbl.font.family; weight: lbl.font.weight; pixelSize: lbl.font.pixelSize }
}
