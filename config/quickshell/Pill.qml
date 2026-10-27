import QtQuick

// Small tinted badge: caption-bold text on a faint fill with a matching edge (a plan name, "Custom", a count).
// `tint` = the colour it is made of (accent by default; accent2 for Settings tags, red for a problem).
Rectangle {
    id: pill
    property string text: ""
    property color tint: Theme.accent

    implicitWidth: label.implicitWidth + 2 * Theme.gapRow - 2
    readonly property int pillH: 20        // caption text + 4 px above and below
    implicitHeight: pillH
    radius: Math.min(Theme.radiusDeep, Math.floor(height / 3))
    color: Theme.alpha(tint, 0.18)
    border.width: 1
    border.color: Theme.alpha(tint, 0.6)
    Label { id: label; anchors.centerIn: parent; text: pill.text; color: pill.tint; font.pixelSize: Theme.fontCaption; font.bold: true }
}
