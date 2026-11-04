import QtQuick
import Quickshell
import "launcher/js/PillPos.js" as P

// Where a pill card sits (DictationPill, DiacPill and their Settings preview, PillPreview): the position keys of `prefs`
// (DictationPrefs or DiacriticsPrefs: pillEdge / pillGap / pillX / pillScreen, launcher/js/PillPos.js) on `screen`, with the
// bar's tokens: past the bar by `pillGap` x its popup gap (BarConfig.popupGapOf, never below the docked bar's), or `pillGap`
// x the edge gap from a bare edge (BarConfig.edgeGapOf, never below the docked one); horizontally between the side edge gaps.
// Follows the gap / edge gap / floating settings. Pure geometry: the window sets its anchors, margins and size from these.
//   atTop      the card hangs from the top edge         edgeInset  its distance from that edge (px, layout space: a zone-0
//   onBar      that edge is the bar's                                window starts past the bar's exclusive zone)
//   left       the card's left edge (px from the screen's left)    cardW  its width (pillW, less on a narrow screen)
//   zoneShift  what the compositor adds to edgeInset (the bar's exclusive zone, respect-reserved bars): edgeInset + zoneShift
//              = the distance from the physical screen edge (the preview draws it there)
//   gapUnit    the px one step of pillGap is on this edge (the Settings gap slider shows px)
//   pick()     the screen a pill opening now goes to: pillScreen when connected, else the focused monitor
QtObject {
    id: place
    property var screen
    property var prefs: null
    property int pillW: 336

    // qmllint disable missing-property
    readonly property string screenName: screen ? screen.name : ""
    readonly property int screenW: screen ? screen.width : 0
    readonly property int screenH: screen ? screen.height : 0
    readonly property string barEdge: screenName !== "" && Popups.bars[screenName] !== undefined ? Popups.edgeOf(screenName) : ""
    readonly property bool barAtTop: barEdge === "top"
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
        gapEdge: gapEdge
    })
    readonly property real gapBar: Math.max(BarConfig.popupGapOf(screen), BarConfig.popupGapDocked)   // one gap token past a bar
    readonly property real gapEdge: Math.max(BarConfig.edgeGapOf(screen), BarConfig.edgeGapDocked)    // one from a bare edge
    readonly property real gapUnit: onBar || barEdge === "" ? gapBar : gapEdge                         // the one pillGap counts here
    readonly property bool atTop: geo.atTop
    readonly property bool onBar: geo.onBar
    readonly property real edgeInset: geo.inset
    readonly property int left: geo.left
    readonly property int cardW: geo.cardW
    readonly property real zoneShift: onBar ? BarConfig.zoneOf(screen) : 0
    readonly property real maxWidth: screenW - 2 * BarConfig.edgeGapOf(screen)
    // qmllint enable missing-property

    function pick() {
        const key = prefs ? prefs.pillScreen : ""
        if (key !== "") {
            const s = Quickshell.screens.find(x => Appearance.monitorKey(x) === key)
            if (s) return s
        }
        return Popups.focusedScreen()
    }
}
