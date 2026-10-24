import QtQuick

// Small keyboard-shortcut hint ("1", "F", "A") on a tile or option row of a modal menu. `sel` = accent look.
// Concentric with a radiusModal box it sits 8 px inside.
Rectangle {
    id: kb
    property string text: ""
    property bool sel: false

    implicitWidth: Math.max(20, kbLabel.implicitWidth + 12)
    implicitHeight: 20
    radius: Theme.inner(Theme.radiusModal, 8)
    color: sel ? Theme.alpha(Theme.accent, 0.3) : Theme.alpha(Theme.fg, 0.08)
    Label { id: kbLabel; anchors.centerIn: parent; text: kb.text; font.pixelSize: Theme.fontCaption; color: kb.sel ? Theme.accent : Theme.muted }
}
