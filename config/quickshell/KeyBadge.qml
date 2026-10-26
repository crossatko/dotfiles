import QtQuick

// Small keyboard-shortcut hint ("1", "F", "A") on a tile or option row of a modal menu. `sel` = accent look.
// Concentric with a radiusModal box it sits 8 px inside.
Rectangle {
    id: kb
    property string text: ""
    property bool sel: false
    property bool outlined: false          // keycap chip for a row's shortcut hint: smaller, hairline border, no fill (the filled badge is a quick-run number)

    implicitWidth: Math.max(outlined ? 18 : 20, kbLabel.implicitWidth + (outlined ? 10 : 12))
    implicitHeight: outlined ? 18 : 20
    radius: Theme.inner(Theme.radiusModal, outlined ? 9 : 8)
    color: outlined ? "transparent" : sel ? Theme.alpha(Theme.accent, 0.3) : Theme.alpha(Theme.fg, 0.08)
    border.width: outlined ? 1 : 0
    border.color: sel ? Theme.alpha(Theme.accent, 0.55) : Theme.alpha(Theme.fg, 0.16)
    Label {
        id: kbLabel
        anchors.centerIn: parent
        text: kb.text
        font.pixelSize: kb.outlined ? Theme.fontCaption - 1 : Theme.fontCaption
        color: kb.outlined ? (kb.sel ? Theme.fgDim : Theme.alpha(Theme.muted, 0.8)) : kb.sel ? Theme.accent : Theme.muted
    }
}
