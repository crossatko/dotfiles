import QtQuick

// The bar of `screen` in a screen mock at real pixels (PillPreview): a card-filled strip on its edge, the bar's own height,
// floating gap and radius (BarConfig), so the pill's distance from it reads true. Nothing for a screen without a bar.
Item {
    id: bk
    property var screen: null
    // qmllint disable missing-property
    readonly property string edge: screen ? Popups.barEdgeOf(screen.name) : ""
    // qmllint enable missing-property
    readonly property real gap: BarConfig.barGapOf(screen)
    visible: edge !== ""
    Rectangle {
        x: bk.gap
        width: bk.width - 2 * bk.gap
        height: BarConfig.heightOf(bk.screen)
        y: bk.edge === "top" ? bk.gap : bk.height - bk.gap - height
        radius: BarConfig.radiusOf(bk.screen)
        color: Theme.alpha(Theme.bg, Theme.cardFill)
        border.width: 1
        border.color: Theme.edge
    }
}
