import QtQuick

// Single-line text field in the popup card style (the Wi-Fi password look): dim box, accent border while
// focused, red border on `error`. `flat` = borderless title look: no box, a hairline underline that turns accent
// while focused (red on `error`). Esc stamps Popups.escAt (so the popup itself stays open) and emits `cancelled`.
// `enabled: false` dims it and makes it read-only. Popups only get keyboard focus a moment after opening: call
// focusField() from Qt.callLater after showing it.
Rectangle {
    id: box
    property alias text: field.text
    property string placeholder: ""
    property bool error: false
    property bool flat: false
    property bool dropRepeat: false   // swallow key auto-repeat except Backspace / Delete (the lock screen: a stuck key must not type)
    property int pixelSize: Theme.fontSize
    property alias horizontalAlignment: field.horizontalAlignment
    property real outerRadius: Theme.radius      // radius of whatever the field sits in (see Btn)
    property real inset: Theme.pad
    property alias inputMethodHints: field.inputMethodHints
    property alias maximumLength: field.maximumLength
    readonly property alias input: field
    readonly property bool focused: field.activeFocus
    signal accepted()
    signal cancelled()
    function focusField() { field.forceActiveFocus(); field.selectAll() }

    implicitHeight: flat ? pixelSize + 20 : Theme.controlH
    implicitWidth: 80
    radius: flat ? 0 : Math.min(Theme.inner(outerRadius, inset), Math.floor(height / 3))
    color: flat ? Theme.alpha(Theme.bg, 0) : Theme.alpha(Theme.bg, field.activeFocus ? 0.7 : 0.45)
    border.width: flat ? 0 : 1
    border.color: error ? Theme.dangerEdge : field.activeFocus ? Theme.accentEdge : Theme.edge
    opacity: enabled ? 1 : Theme.disabledOpacity
    Behavior on border.color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
    Behavior on opacity { NumberAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }

    // flat: underline (hairline at rest, 2 px accent / red while focused or wrong)
    Rectangle {
        visible: box.flat
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: field.activeFocus || box.error ? 2 : 1
        radius: height / 2
        color: box.error ? Theme.dangerEdge : field.activeFocus ? Theme.accentEdge : Theme.edge
        Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
    }

    TextInput {
        id: field
        anchors { fill: parent; leftMargin: box.flat ? 2 : Theme.padSm; rightMargin: box.flat ? 2 : Theme.padSm; bottomMargin: box.flat ? 2 : 0 }
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.fg
        selectionColor: Theme.accent
        selectedTextColor: Theme.bg
        font.family: Theme.font
        font.pixelSize: box.pixelSize
        font.bold: box.flat
        readOnly: !box.enabled
        activeFocusOnTab: box.enabled
        clip: true
        onAccepted: box.accepted()
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: e => { if (box.dropRepeat && e.isAutoRepeat && e.key !== Qt.Key_Backspace && e.key !== Qt.Key_Delete) e.accepted = true }
        Keys.onEscapePressed: { Popups.escAt = Date.now(); box.cancelled() }
        Label {
            visible: field.text === ""
            anchors { verticalCenter: parent.verticalCenter; left: field.horizontalAlignment === TextInput.AlignHCenter ? undefined : parent.left
                      horizontalCenter: field.horizontalAlignment === TextInput.AlignHCenter ? parent.horizontalCenter : undefined }
            text: box.placeholder
            color: Theme.muted
            font.pixelSize: box.flat ? box.pixelSize : Theme.fontSmall
        }
    }
}
