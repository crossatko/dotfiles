import QtQuick
import Quickshell
import Quickshell.Wayland

// One per screen. While a popup / launcher / Settings / tray menu is open on ANOTHER monitor, an invisible
// full-screen layer here swallows the next click and closes it (the open thing's own window handles
// clicks on its own monitor). Never takes keyboard focus.
// PanelWindow is an uncreatable interface type in Quickshell's qmltypes (the real window exists at runtime)
// qmllint disable uncreatable-type
PanelWindow {
    id: catcher

    required property var modelData
    screen: modelData

    visible: Popups.anyOpen && Popups.ownerScreen !== "" && Popups.ownerScreen !== modelData.name
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-catcher"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { left: true; right: true; top: true; bottom: true }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: Popups.closeAll()
    }
}
