import QtQuick
import Quickshell.Hyprland
import "launcher/js/PillPos.js" as P

// Where a pill card sits (DictationPill, DiacPill and their Settings preview, PillPreview): the position keys of `prefs`
// (DictationPrefs or DiacriticsPrefs: pillEdge / pillGap / pillX / pillScreen, launcher/js/PillPos.js) on `screen`, with the
// bar's tokens: past the bar by `pillGap` x its popup gap (BarConfig.popupGapOf, never below the docked bar's), or `pillGap`
// x the edge gap from a bare edge (BarConfig.edgeGapOf, never below the docked one); horizontally inside the usable width (the
// screen minus Hyprland's reserved left / right, e.g. the pinned-video strip: Monitors.reservedOf), the edge gap from its sides.
// Follows the gap / edge gap / floating settings. Pure geometry: the window sets its anchors, margins and size from these.
// The reserved area comes from Hyprland's last monitor report: the pills call Hyprland.refreshMonitors() when they open.
//   atTop      the card hangs from the top edge         edgeInset  its distance from that edge (px, layout space: a zone-0
//   onBar      that edge is the bar's                                window starts past the bar's exclusive zone)
//   left       the card's left edge (px from the screen's left)    cardW  its width (pillW, less on a narrow screen)
//   margin     the window's left margin (BarZone 0 = "respect reserved": from the usable area's left, else from the screen's)
//   zoneShift  what the compositor adds to edgeInset (BarZone 0: the reserved area on that edge, the bar's exclusive zone at
//              least): edgeInset + zoneShift = the distance from the physical screen edge (the preview draws it there)
//   reserved   Monitors.reservedOf(screen)
//   gapUnit    the px one step of pillGap is on this edge (the Settings gap slider shows px)
//   maxH       the tallest a card may get here (a growing caption): from its edge to the far edge of the usable screen, less the
//              bar if that sits on the far edge, and one edge gap
//   refresh()  asks Hyprland for a new monitor report (the reserved area)
//   pick()     refresh() and the screen a pill opening now goes to: pillScreen when connected (Monitors.byKey), else the focused monitor
QtObject {
    id: place
    property var screen
    property var prefs: null
    property int pillW: 336

    // qmllint disable missing-property
    readonly property string screenName: screen ? screen.name : ""
    readonly property int screenW: screen ? screen.width : 0
    readonly property int screenH: screen ? screen.height : 0
    readonly property string barEdge: Popups.barEdgeOf(screenName)
    readonly property bool inUsable: BarConfig.respectReserved(screen)          // the pills' BarZone: exclusive zone 0
    readonly property var reserved: Monitors.reservedOf(screen)
    readonly property var geo: P.place({
        edge: prefs ? prefs.pillEdge : P.DEFAULTS.pill_edge,
        barEdge: barEdge,
        gap: prefs ? prefs.pillGap : P.DEFAULTS.pill_gap,
        x: prefs ? prefs.pillX : P.DEFAULTS.pill_x,
        screenW: screenW,
        pillW: pillW,
        side: BarConfig.edgeGapOf(screen),
        barInset: Popups.cardInsetOf(screen) - BarConfig.popupGapOf(screen),       // screen edge -> the bar's far edge
        gapBar: gapBar,
        gapEdge: gapEdge,
        resL: reserved.left,
        resR: reserved.right,
        inUsable: inUsable
    })
    readonly property real gapBar: Math.max(BarConfig.popupGapOf(screen), BarConfig.popupGapDocked)   // one gap token past a bar
    readonly property real gapEdge: Math.max(BarConfig.edgeGapOf(screen), BarConfig.edgeGapDocked)    // one from a bare edge
    readonly property real gapUnit: onBar || barEdge === "" ? gapBar : gapEdge                         // the one pillGap counts here
    readonly property bool atTop: geo.atTop
    readonly property bool onBar: geo.onBar
    readonly property real edgeInset: geo.inset
    readonly property int left: geo.left
    readonly property int margin: geo.margin
    readonly property int cardW: geo.cardW
    readonly property real zoneShift: inUsable ? Math.max(atTop ? reserved.top : reserved.bottom, onBar ? BarConfig.zoneOf(screen) : 0) : 0
    readonly property real barInset: Popups.cardInsetOf(screen) - BarConfig.popupGapOf(screen)       // screen edge -> the bar's far edge
    readonly property real farClear: (barEdge !== "" && barEdge !== (atTop ? "top" : "bottom") ? barInset : 0)
        + (inUsable ? (atTop ? reserved.bottom : reserved.top) : 0) + gapEdge
    readonly property real maxH: Math.max(0, screenH - edgeInset - zoneShift - farClear)
    // qmllint enable missing-property

    function refresh() { Hyprland.refreshMonitors() }      // a fresh reserved area (the pinned-video strip comes and goes)
    function pick() { refresh(); return Monitors.byKey(prefs ? prefs.pillScreen : "") || Popups.focusedScreen() }
}
