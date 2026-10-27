import QtQuick
import Quickshell

// Double-click on a modal window's header area: back to the centre of its monitor at the default size, nothing is remembered
// (qs_modal_reset in hypr/scripts/modal-windows.lua, through hyprctl; a tiled window is left alone).
// Put it behind the header row's buttons; they keep their own clicks.
MouseArea {
    required property string windowTitle
    acceptedButtons: Qt.LeftButton
    onDoubleClicked: Quickshell.execDetached(["hyprctl", "dispatch",
        "(function() qs_modal_reset(\"" + windowTitle + "\") return hl.dsp.exec_cmd(\"true\") end)()"])
}
