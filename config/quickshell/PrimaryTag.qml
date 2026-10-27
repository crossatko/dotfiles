import QtQuick
import QtQuick.Layouts

// The "Primary" marker of a monitor: an accent dot and the word, in monitor lists, cards and the picker; `compact` = the
// dot only (a tight MonitorChip).
RowLayout {
    id: tag
    property bool compact: false
    spacing: 4
    Rectangle { Layout.preferredWidth: 6; Layout.preferredHeight: 6; radius: 3; color: Theme.accent }
    Label { visible: !tag.compact; text: "Primary"; font.pixelSize: Theme.fontCaption; color: Theme.accent }
}
