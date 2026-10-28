import QtQuick
import QtQuick.Layouts

// The "Primary" marker of a monitor: an accent dot and the word, wherever monitors are listed (MonitorChip, MonitorCard,
// the Monitors map). `compact` = the dot only (a tight chip); `ink` = a set with fg / bg / accent (Theme.barInkLight) for a
// marker drawn over a wallpaper: it then sits on a dark pill (the Monitors map tiles).
Rectangle {
    id: tag
    property bool compact: false
    property var ink: null
    readonly property bool pill: ink !== null
    readonly property int pad: pill ? Theme.controlGap : 0
    readonly property real wordWidth: word.implicitWidth + row.spacing   // what `compact` saves

    implicitWidth: row.implicitWidth + 2 * pad
    implicitHeight: row.implicitHeight + (pill ? 4 : 0)
    radius: Math.min(Theme.radiusDeep, height / 3)
    color: pill ? Theme.alpha(ink.bg, 0.72) : Theme.alpha(Theme.bg, 0)
    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 4
        Rectangle { Layout.preferredWidth: 6; Layout.preferredHeight: 6; radius: 3; color: tag.pill ? tag.ink.accent : Theme.accent }
        Label {
            id: word
            visible: !tag.compact
            text: "Primary"
            font.pixelSize: tag.pill ? Theme.fontTiny : Theme.fontCaption
            font.bold: tag.pill
            color: tag.pill ? tag.ink.fg : Theme.accent
        }
    }
}
