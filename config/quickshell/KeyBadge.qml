import QtQuick

// Small keyboard-shortcut hint ("1", "F", "A") on a tile or option row of a modal menu. `sel` = accent look.
// Concentric with a radiusModal box it sits 8 px inside. Two sizes: the filled quick-run number badge and the smaller
// keycap chip (`outlined`: hairline border, no fill) for a row's Hyprland shortcut.
Rectangle {
    id: kb
    property string text: ""
    property bool sel: false
    property bool outlined: false          // keycap chip for a row's shortcut hint: smaller, hairline border, no fill (the filled badge is a quick-run number)
    readonly property int badgeH: outlined ? 18 : 20      // keycap / number badge height

    implicitWidth: Math.max(badgeH, kbLabel.implicitWidth + (outlined ? Theme.padSm : Theme.pad))
    implicitHeight: badgeH
    radius: Theme.inner(Theme.radiusModal, outlined ? 9 : 8)
    color: outlined ? Theme.alpha(Theme.fg, 0) : sel ? Theme.alpha(Theme.accent, 0.3) : Theme.alpha(Theme.fg, 0.08)
    border.width: outlined ? 1 : 0
    border.color: sel ? Theme.alpha(Theme.accent, 0.55) : Theme.alpha(Theme.fg, 0.16)
    Label {
        id: kbLabel
        anchors.centerIn: parent
        text: kb.text
        font.pixelSize: kb.outlined ? Theme.fontTiny : Theme.fontCaption
        color: kb.outlined ? (kb.sel ? Theme.fgDim : Theme.alpha(Theme.muted, 0.8)) : kb.sel ? Theme.accent : Theme.muted
    }
}
