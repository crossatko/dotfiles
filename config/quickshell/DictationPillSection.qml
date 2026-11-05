import QtQuick

// Settings > Voice > Pill: PillSection over DictationPrefs with the real dictation card (DictationPillCard) playing a sample
// dictation: listening, then a sentence arriving word by word while the level moves (SpeechDemoLevel), then again. Below the
// preview: the lines setting (PillLinesRow); the sample is long enough to show how many lines the pill grows to.
PillSection {
    id: sec
    store: DictationPrefs

    readonly property var words: ("Dobrý den, tohle je ukázka diktování. Mluvím tak dlouho, aby text přetekl přes první řádek, "
        + "pak přes druhý a nakonec i přes třetí, a nejstarší slova se z pilulky vytratí nahoru. Až pustíš klávesu, "
        + "napíše se celý text najednou.").split(" ")
    property int step: 0                      // 0..2 listening, then one word per step, a few steps holding the full line
    readonly property int shown: Math.max(0, Math.min(words.length, step - 2))
    Timer {
        interval: 260
        repeat: true
        running: sec.visible
        onTriggered: sec.step = (sec.step + 1) % (sec.words.length + 7)
    }
    PillLinesRow { titleWidth: sec.titleWidth }
    SpeechDemoLevel { id: demoLevel; running: sec.visible; talking: sec.shown > 0 && sec.shown < sec.words.length }

    card: DictationPillCard {
        id: demoCard
        objectName: "pill-preview-card"
        openMotion: sec.motion
        fromTop: sec.atTop
        flip: !sec.atTop
        slotW: sec.cardW
        slotAlign: DictationPrefs.pillX
        previewLines: DictationPrefs.pillPreviewLines
        maxH: sec.maxH
        look: sec.shown > 0 ? "speaking" : "listening"
        mode: "cs"
        caption: sec.words.slice(0, sec.shown).join(" ")
        level: demoLevel.level
        running: sec.visible
    }
}
