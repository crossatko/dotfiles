import QtQuick

// Status mark for list ROWS (switches live only on section headers). Fixed 22px column so rows
// with and without a mark never shift. connected = check, busy = pulsing ellipsis,
// idle = nothing, or a faint plug while `hovered` (hints click-to-connect).
Item {
    id: rs

    property bool connected: false
    property bool busy: false
    property bool hovered: false
    property bool hintable: true

    implicitWidth: 22
    implicitHeight: 22

    Text {
        id: glyph
        anchors.centerIn: parent
        font.family: Theme.iconFont
        font.styleName: "Regular"
        font.pixelSize: 14
        text: rs.busy ? "" : rs.connected ? "" : ""
        color: rs.connected || rs.busy ? Theme.accent : Theme.muted
        opacity: rs.busy || rs.connected ? 1 : (rs.hovered && rs.hintable ? 0.7 : 0)
        Behavior on opacity { NumberAnimation { duration: 120 } }

        SequentialAnimation on scale {
            running: rs.busy
            loops: Animation.Infinite
            NumberAnimation { to: 0.7; duration: 380; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 380; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) glyph.scale = 1
        }
    }
}
