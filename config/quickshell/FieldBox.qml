import QtQuick

// Single-line text field in the popup card style (the Wi-Fi password look): dim box, accent border while
// focused, red border on `error`. Esc stamps Popups.escAt (so the popup itself stays open) and emits `cancelled`.
// Popups only get keyboard focus a moment after opening: call focusField() from Qt.callLater after showing it.
Rectangle {
    id: box
    property alias text: field.text
    property string placeholder: ""
    property bool error: false
    property real outerRadius: Theme.radius      // radius of whatever the field sits in (see Btn)
    property real inset: 12
    property alias inputMethodHints: field.inputMethodHints
    property alias maximumLength: field.maximumLength
    readonly property alias input: field
    signal accepted()
    signal cancelled()
    function focusField() { field.forceActiveFocus(); field.selectAll() }

    implicitHeight: 32
    implicitWidth: 80
    radius: Math.min(Theme.inner(outerRadius, inset), Math.floor(height / 3))
    color: Theme.alpha(Theme.bg, 0.6)
    border.width: 1
    border.color: error ? Theme.alpha(Theme.red, 0.9) : field.activeFocus ? Theme.alpha(Theme.accent, 0.9) : Theme.alpha(Theme.overlay, 0.6)
    Behavior on border.color { ColorAnimation { duration: 120 } }

    TextInput {
        id: field
        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.fg
        selectionColor: Theme.accent
        selectedTextColor: Theme.bg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        clip: true
        onAccepted: box.accepted()
        Keys.onEscapePressed: { Popups.escAt = Date.now(); box.cancelled() }
        Label { visible: field.text === ""; anchors.verticalCenter: parent.verticalCenter; text: box.placeholder; color: Theme.muted; font.pixelSize: Theme.fontSmall }
    }
}
