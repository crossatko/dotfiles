import QtQuick

// Where a pill card hangs (DictationPill, DiacPill): centred on the bar edge of `screen`, `edgeGapFactor` (2) x the gap tokens
// past the bar (BarConfig.popupGapOf, never below the docked bar's tokens), or on the bottom edge when the bar is not at the top
// or DictationPrefs.pillBottom says so (then `edgeGapFactor` x edgeGapOf from the bare screen edge). It follows the gap / edge gap /
// floating settings. Pure geometry: the window sets its anchors, margins and size from these.
//   atTop       the card hangs from the top edge     edgeInset   its distance from that edge (px)
//   barAtTop    the bar of `screen` is at the top    maxWidth    the widest a card may be (screen minus the edge gaps)
QtObject {
    id: place
    property var screen
    property real edgeGapFactor: 2

    // qmllint disable missing-property
    readonly property string screenName: screen ? screen.name : ""
    readonly property int screenW: screen ? screen.width : 0
    readonly property bool barAtTop: screenName !== "" && Popups.edgeOf(screenName) === "top"
    // the edge the pill hangs from: the bar's, or the bottom edge when Settings > Voice says so
    readonly property bool atTop: barAtTop && !DictationPrefs.pillBottom
    readonly property real barInset: Popups.cardInsetOf(screen) - BarConfig.popupGapOf(screen)       // screen edge -> the bar's far edge (0 without a bar)
    readonly property real gapFromBar: edgeGapFactor * Math.max(BarConfig.popupGapOf(screen), BarConfig.popupGapDocked)
    readonly property real gapFromEdge: edgeGapFactor * Math.max(BarConfig.edgeGapOf(screen), BarConfig.edgeGapDocked)
    // distance of the card's anchored edge from the screen edge: past the bar, or (bottom override, bar at the top) from the bare edge
    readonly property real edgeInset: barAtTop && !atTop ? gapFromEdge : barInset + gapFromBar
    readonly property real maxWidth: screenW - 2 * BarConfig.edgeGapOf(screen)
    // qmllint enable missing-property
}
