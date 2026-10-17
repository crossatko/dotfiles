import QtQuick
import Quickshell
import Quickshell.Wayland

// Invisible strip whose only job is reserving the bar's space for tiled windows. The visible bar
// itself uses exclusiveZone -1 so it ignores the monitor's reserved_area (the pinned-video strip,
// scripts/pip-reserve.lua) and keeps its full width; this surface may be squeezed, that is fine.
PanelWindow {
    id: strip
    required property var modelData
    property bool atTop: false
    screen: modelData
    anchors { left: true; right: true; top: atTop; bottom: !atTop }
    implicitHeight: Theme.barHeight
    exclusiveZone: Theme.barHeight
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "qs-reserve"
}
