import QtQuick

// The diacritics pill's card (DiacPill, and the Settings > Diacritics preview through PillSection): the glass card (MotionCard)
// with the dot picture (DiacDots, 300 x 50 = 78 x 13 dots of 3.85 px; the 7-row base band on the card's centre line). Pure view:
// kind / phase / text / partial / replayText / running go straight to DiacDots (see there); `dots` for busy / restart().
// Fixed height (cardH); width from the user.
MotionCard {
    id: card
    property alias kind: dots.kind
    property alias phase: dots.phase
    property alias text: dots.text
    property alias partial: dots.partial
    property alias replayText: dots.replayText
    property alias running: dots.running
    readonly property alias dots: dots

    // ---- geometry (Theme tokens; the sizes are this card's own) ----
    readonly property int pillW: 336          // the card's width (the window's; shrinks only on a narrow screen)
    readonly property int dotsW: 300          // 78 dots
    readonly property int dotsH: 50           // 13 rows; the 7-row base band is rows 3..9, on the card's centre line
    readonly property int rowH: 40            // the dictation pill's swoosh row: the dots are centred on it
    readonly property real cardH: 2 * Theme.pad + rowH

    height: cardH
    clip: true

    DiacDots {
        id: dots
        x: Math.round((card.width - card.dotsW) / 2)
        y: Math.round((card.height - card.dotsH) / 2)
        width: card.dotsW
        height: card.dotsH
    }
}
