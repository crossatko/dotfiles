import QtQuick

// Settings > Voice > Pill: PillSection over DictationPrefs with the real dictation card (DictationPillCard) playing a sample
// dictation: listening, then a sentence arriving word by word while the level moves (SpeechDemoLevel), then again.
PillSection {
    id: sec
    store: DictationPrefs
    fullH: demoCard.fullH

    readonly property var words: ["Dobrý", "den,", "tohle", "je", "ukázka", "diktování."]
    property int step: 0                      // 0..2 listening, then one word per step, a few steps holding the full line
    readonly property int shown: Math.max(0, Math.min(words.length, step - 2))
    Timer {
        interval: 450
        repeat: true
        running: sec.visible
        onTriggered: sec.step = (sec.step + 1) % (sec.words.length + 7)
    }
    SpeechDemoLevel { id: demoLevel; running: sec.visible; talking: sec.shown > 0 && sec.shown < sec.words.length }

    card: DictationPillCard {
        id: demoCard
        objectName: "pill-preview-card"
        openMotion: sec.motion
        fromTop: sec.atTop
        flip: !sec.atTop
        width: sec.cardW
        look: sec.shown > 0 ? "speaking" : "listening"
        mode: "cs"
        caption: sec.words.slice(0, sec.shown).join(" ")
        level: demoLevel.level
        running: sec.visible
    }
}
