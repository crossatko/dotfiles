pragma ComponentBehavior: Bound
import QtQuick

// Settings > Voice / Diacritics > Pill: the live preview of a pill (PillSection). The real pill card goes in as `card`
// (DictationPillCard / DiacPillCard with demo state, re-parented here; bind `openMotion: <preview>.motion`, `fromTop: <preview>.atTop`,
// `width: <preview>.cardW`). A 1:1 window onto the monitor (`screen`; ScreenBackdrop: its wallpaper still and a sketch of its bar)
// around the card (clamped to the screen), the card itself at actual size; Hyprland's reserved side strips (pinned video) veiled.
// Under the card: ScreenBackdrop's `frost`, a sketch of the compositor's glass (the Settings window cannot show it there).
// It reads the real geometry (PillPlacement over the same prefs), so the preview cannot drift from the real pill.
//   store   DictationPrefs or DiacriticsPrefs (the pill_* keys)        screen  the monitor drawn (PillSection: the saved one, else
//   the one picked in Settings)
// The strip is as tall as the card now shows (at most maxCardH), never the pill's real maximum: the Settings page stays small.
Item {
    id: pv
    property var store: null
    property var screen: Monitors.selected
    readonly property real maxCardH: 280     // hard cap (px) on the card height the strip makes room for
    property Item card: null
    onCardChanged: if (card) card.parent = slot
    readonly property OpenMotion motion: om
    readonly property PillPlacement placement: place     // the geometry it draws (PillPositionRows reads the edge and gap unit)
    readonly property bool atTop: place.atTop
    readonly property int cardW: place.cardW
    readonly property Item cardItem: card

    // qmllint disable missing-property
    readonly property real sw: screen && screen.width > 0 ? screen.width : 1920
    readonly property real sh: screen && screen.height > 0 ? screen.height : 1080
    // qmllint enable missing-property
    // the card's distance from its screen edge (physical px): its anchored edge plus what the bar's exclusive zone adds
    readonly property real cardH: cardItem ? cardItem.height : 0
    readonly property real roomH: Math.min(Math.ceil(cardH), maxCardH)     // the slot: the card's current height, capped
    readonly property real dist: place.edgeInset + place.zoneShift
    readonly property real stripPad: Theme.pad + Theme.gapRow     // at least this much screen around the actual-size card

    implicitHeight: strip.height

    PillPlacement { id: place; screen: pv.screen; prefs: pv.store; pillW: pv.card ? pv.card.placeW : 0 }   // qmllint disable missing-property
    Component.onCompleted: place.refresh()
    OpenMotion { id: om; open: true; t: 1 }      // always fully open: the card's own idle look

    Column {
        width: parent.width

        // a window onto the screen around the card
        ScreenFrame {
            id: strip
            objectName: "pill-preview-actual"
            width: parent.width
            height: Math.min(pv.sh, pv.roomH + 2 * pv.stripPad)
            virtualW: width
            virtualH: height
            // the slot = the room for the card as it shows now (it hangs from its edge, as in the real window); its top-left on the screen
            readonly property real slotY: pv.atTop ? pv.dist : pv.sh - pv.dist - slot.height
            // the part of the screen shown: centred on the slot, kept inside the screen
            readonly property real viewX: Math.max(0, Math.min(pv.sw - width, place.left + (pv.cardItem ? pv.cardItem.x + pv.cardItem.width / 2 : pv.cardW / 2) - width / 2))
            readonly property real viewY: Math.max(0, Math.min(pv.sh - height, slotY + slot.height / 2 - height / 2))
            Item {
                x: -Math.round(strip.viewX)
                y: -Math.round(strip.viewY)
                width: pv.sw
                height: pv.sh
                // only the part in view (its own decode: the still is never loaded at the full screen size)
                ScreenBackdrop {
                    x: Math.round(strip.viewX)
                    y: Math.round(strip.viewY)
                    width: strip.width
                    height: strip.height
                    view: Qt.rect(x, y, width, height)
                    screen: pv.screen
                    reserved: place.reserved
                    frost: pv.cardItem ? Qt.rect(slot.x + pv.cardItem.x, slot.y + pv.cardItem.y, pv.cardItem.width, pv.cardH) : Qt.rect(0, 0, 0, 0)
                }
                Item {
                    id: slot
                    x: place.left
                    y: Math.round(strip.slotY)
                    width: pv.cardW
                    height: pv.roomH
                }
            }
        }
    }
    // the card hangs from the slot's edge on the pill's side, as in the real window
    Binding { target: pv.cardItem; property: "y"; value: pv.atTop ? 0 : slot.height - pv.cardH; when: pv.cardItem !== null }
}
