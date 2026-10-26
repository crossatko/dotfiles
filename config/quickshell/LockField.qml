import QtQuick

// The lock screen's password input: no visible field. A FieldBox kept invisible holds the keyboard focus and the text
// (key auto-repeat dropped, Esc clears); what shows is LockDots, the typed characters as glass beads, centred. Feedback
// is the beads: pop in while typing, a soft pulse while `busy`, `reject()` = red, shake, clear.
Item {
    id: lf
    property alias text: box.text
    property alias busy: beads.busy
    property alias beadSize: beads.beadSize
    property alias backdrop: beads.backdrop
    property alias sharpBackdrop: beads.sharpBackdrop
    property alias sharpInset: beads.sharpInset
    property point origin: Qt.point(0, 0)
    property alias backdropSize: beads.backdropSize
    readonly property bool focused: box.focused
    signal accepted()
    signal cancelled()
    function focusField() { box.focusField() }
    function reject(n) { beads.reject(n) }

    implicitHeight: beadSize * 2

    FieldBox {
        id: box
        anchors.fill: parent
        opacity: 0                // keeps focus and keys while invisible
        dropRepeat: true
        onAccepted: lf.accepted()
        onCancelled: lf.cancelled()
        Component.onCompleted: input.echoMode = TextInput.Password
    }
    LockDots {
        id: beads
        anchors.fill: parent
        count: lf.text.length
        origin: lf.origin
    }
}
