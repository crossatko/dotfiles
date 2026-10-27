pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// The "Customise…" fold of a Settings section: everything detailed (sliders, switches, per-item rows) lives in here,
// closed by default, so the page shows only its few primary choices. The head is an explicit action (a Btn-like row:
// chevron + label + an optional `detail` badge such as "3 changed", never a sentence); the body unfolds with the fold motion (FoldBox:
// Motion.moveMs, fades in; reduced motion = instant) and keeps the page's row layout (`titleWidth` for the rows).
// Usage:   AdvancedFold { Layout.fillWidth: true;  PrefSlider { ... }  PrefToggle { ... } }
ColumnLayout {
    id: af
    property string label: "Customise…"
    property string detail: ""
    property bool open: false
    property alias bodySpacing: body.spacing
    default property alias content: body.data

    spacing: 0
    Layout.fillWidth: true

    Rectangle {
        id: head
        Layout.fillWidth: true
        implicitHeight: 30
        radius: Theme.radiusPage
        color: af.open ? Theme.alpha(Theme.fg, 0.06) : headArea.containsMouse ? Theme.alpha(Theme.fg, 0.08) : Theme.alpha(Theme.fg, 0.04)
        border.width: 1
        border.color: Theme.alpha(Theme.overlay, headArea.activeFocus ? 0.9 : 0.45)
        Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
        HoverGlow { area: headArea; radius: head.radius }
        PressFeedback { area: headArea }
        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            spacing: 8
            Chevron { open: af.open; Layout.preferredWidth: 14; horizontalAlignment: Text.AlignHCenter }
            Label { text: af.label; font.pixelSize: Theme.fontSmall; color: Theme.fg }
            Label { Layout.fillWidth: true; text: af.detail; color: Theme.muted; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }
        }
        MouseArea {
            id: headArea
            objectName: af.objectName + "-head"     // test hook: `qs ipc call settingsui locate <fold objectName>-head`
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: af.label
            onClicked: af.open = !af.open
            Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { af.open = !af.open; e.accepted = true } }
        }
    }
    FoldBox {
        Layout.fillWidth: true
        open: af.open
        contentHeight: body.implicitHeight + 12
        ColumnLayout {
            id: body
            width: parent.width
            y: 12
            spacing: 12
        }
    }
}
