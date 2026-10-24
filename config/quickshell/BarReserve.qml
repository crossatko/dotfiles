import QtQuick
import Quickshell
import Quickshell.Wayland

// Invisible strip whose only job is reserving the bar's space for tiled windows. The visible bar
// itself uses exclusiveZone -1 so it ignores the monitor's reserved_area (the pinned-video strip,
// scripts/pip-reserve.lua) and keeps its full width; this surface may be squeezed, that is fine.
// PanelWindow is an uncreatable interface type in Quickshell's qmltypes (the real window exists at runtime)
// qmllint disable uncreatable-type
PanelWindow {
    id: strip
    required property var modelData
    property bool atTop: false
    screen: modelData
    anchors { left: true; right: true; top: atTop; bottom: !atTop }
    // bar height, plus the floating bar's gap to the screen edge (Theme.barReserve); Hyprland then adds its
    // gaps_out beyond this, so the visible bar <-> window gap is gapOut, the same as at the other edges
    implicitHeight: Theme.barReserve
    exclusiveZone: Theme.barReserve
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "qs-reserve"
}
