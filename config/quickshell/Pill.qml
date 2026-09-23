import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: pillRoot

    default property alias contentChildren: inner.data
    property alias radius: bg.radius

    color: "transparent"
    exclusiveZone: 0

    Rectangle {
        id: bg
        anchors.fill: parent
        // Hyprland's layer-shell blur has no rounding concept (renderdata.decorate
        // is hardcoded false for layers in Renderer.cpp -- confirmed in source, not
        // a config gap), so blur always bleeds into the corners outside whatever
        // shape we draw here. Keeping this small (not a full height/2 capsule) so
        // that bleed area stays small/subtle instead of very visible.
        radius: 10 // matches theme.glass.window_rounding
        color: "transparent" // no tint at all -- purely relying on Hyprland's blur
    }

    Item {
        id: inner
        anchors.fill: parent
    }
}
