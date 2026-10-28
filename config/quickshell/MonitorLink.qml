import QtQuick

// The link bridge on the seam between two neighbouring monitor chips (MonitorSection `linkable`: Settings > Bar and
// > Wallpaper). A plain chain glyph in the middle of the seam (no pill, no border): accent while linked, with an accent
// connector line from chip edge to chip edge on both sides of it (the two read as one); not linked = the glyph alone in
// a faint fg that brightens on hover. The whole seam is the hit area (the tooltip names the pair); Tab focuses it (a
// focus ring only then), Space / Enter toggle. Emits `toggled` only; the page decides what linking means (copy the
// edited monitor's wallpaper / bar layout to the newly linked one).
Item {
    id: lk
    property bool linked: false
    property string tip: ""                // accessible name, e.g. "Link Monitor A and Monitor B"
    signal toggled()

    readonly property bool lit: tap.containsMouse || activeFocus
    readonly property int clear: 2                           // gap between the glyph and the connector line
    activeFocusOnTab: visible
    Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { lk.toggled(); e.accepted = true } }
    Accessible.role: Accessible.CheckBox
    Accessible.name: tip
    Accessible.checked: linked

    // the connector (linked only): chip edge to the glyph and on from it to the other chip
    readonly property real stubW: Math.max(0, (width - glyph.width) / 2 - clear)
    Rectangle {
        x: 0; y: (lk.height - height) / 2; width: lk.stubW; height: 2
        color: Theme.accent
        opacity: lk.linked ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
    }
    Rectangle {
        x: lk.width - width; y: (lk.height - height) / 2; width: lk.stubW; height: 2
        color: Theme.accent
        opacity: lk.linked ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
    }
    Icon {
        id: glyph
        anchors.centerIn: parent
        text: Icons.link
        font.pixelSize: Theme.iconMd
        color: lk.linked ? Theme.accent : Theme.alpha(Theme.fg, lk.lit ? 0.8 : 0.4)
        Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
        PressFeedback { area: tap; depth: 3 }
    }
    // keyboard focus only
    Rectangle {
        visible: lk.activeFocus
        anchors.centerIn: parent
        width: glyph.width + 8; height: glyph.height + 8
        radius: Theme.radiusDeep
        color: Theme.alpha(Theme.fg, 0)
        border.width: 1
        border.color: Theme.alpha(Theme.fg, 0.6)
    }
    MouseArea {
        id: tap
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: lk.toggled()
    }
    TipBubble { anchors.fill: parent; alignRight: false; text: lk.tip; shown: tap.containsMouse || lk.activeFocus }
}
