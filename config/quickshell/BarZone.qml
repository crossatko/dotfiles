import QtQuick

// exclusiveZone for a small overlay that hangs off the bar and hops between screens (OSD, toasts, dictation pill): 0 = laid out
// inside the monitor's reserved area like the bar ("respect reserved", Settings > Bar), -1 = from the physical screen
// edge (the pinned-video strip ignored). Usage: `BarZone { id: zone; screen: win.screen }` + `exclusiveZone: zone.zone`.
// Set a moment after the screen / the option changed: a zone changed in the same tick as the screen was not applied
// to the re-created layer surface.
Item {
    id: bz
    property var screen: null
    readonly property bool respect: BarConfig.respectReserved(screen)
    property int zone: -1
    visible: false
    onRespectChanged: timer.restart()
    onScreenChanged: timer.restart()
    Component.onCompleted: zone = respect ? 0 : -1
    Timer { id: timer; interval: 80; onTriggered: bz.zone = bz.respect ? 0 : -1 }
}
