import QtQuick
import QtQuick.Layouts

// Settings > Voice / Diacritics > Pill: one section on both pages. Head, the live preview (PillPreview: the real card at actual
// size on a crop of the monitor where the pill sits), the feature's own rows (children, e.g. Diacritics "Text"), then
// where it sits (PillPositionRows). `card` = the feature's real pill card with demo state (bind `openMotion: <section>.motion`,
// `fromTop: <section>.atTop`, `width: <section>.cardW`). The preview draws the saved monitor
// (pill_screen) when it is connected, else the one picked in Settings (Monitors.selected).
ColumnLayout {
    id: sec
    property var store: null
    property real titleWidth: 120
    property alias card: preview.card
    readonly property real maxH: preview.placement.maxH       // the tallest a card may get on the drawn monitor
    readonly property OpenMotion motion: preview.motion
    readonly property bool atTop: preview.atTop
    readonly property int cardW: preview.cardW
    readonly property bool dragging: pos.dragging
    default property alias rows: own.data

    readonly property var shownScreen: Monitors.byKey(store ? store.pillScreen : "") || Monitors.selected

    Layout.fillWidth: true
    spacing: Theme.gapRow

    SectionHead {
        title: "Pill"
        detail: sec.store && sec.store.pillKeys.some(k => sec.store.overridden(k)) ? "moved" : ""
        InfoTip { text: "The preview shows the real pill with sample content at actual size, on the monitor where it opens." }
    }
    PillPreview {
        id: preview
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        store: sec.store
        screen: sec.shownScreen
    }
    ColumnLayout {
        id: own
        Layout.fillWidth: true
        spacing: Theme.gapRow
        visible: children.length > 0
    }
    PillPositionRows { id: pos; store: sec.store; place: preview.placement; titleWidth: sec.titleWidth }
}
