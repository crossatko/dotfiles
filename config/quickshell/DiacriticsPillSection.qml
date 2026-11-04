import QtQuick

// Settings > Diacritics > Pill: PillSection over DiacriticsPrefs with the real diacritics card (DiacPillCard) playing a sample run
// (working on the text, the fixed words arriving with their marks, done with the check, then again), and the Text switch:
// the real words or a generic animation (privacy; the preview follows it).
PillSection {
    id: sec
    store: DiacriticsPrefs

    readonly property string sample: "Prilis zlutoucky kun upel dabelske ody"
    readonly property var fixedWords: ["Příliš", "žluťoučký", "kůň", "úpěl", "ďábelské", "ódy"]
    readonly property bool words: DiacriticsPrefs.showText
    property int step: 0                      // 0..1 working, one fixed word per step, done, a pause, again
    readonly property int fixedN: Math.max(0, Math.min(fixedWords.length, step - 1))
    readonly property bool done: step >= fixedWords.length + 2
    Timer {
        interval: 500
        repeat: true
        running: sec.visible
        onTriggered: {
            sec.step = (sec.step + 1) % (sec.fixedWords.length + 8)
            if (sec.step === 0) demoCard.dots.restart()
        }
    }
    onWordsChanged: { step = 0; demoCard.dots.restart() }

    card: DiacPillCard {
        id: demoCard
        objectName: "pill-preview-card"
        openMotion: sec.motion
        fromTop: sec.atTop
        width: sec.cardW
        running: sec.visible
        kind: sec.words ? "words" : "neutral"
        phase: sec.done ? "done" : "working"
        text: sec.words ? sec.sample : ""
        partial: sec.words && !sec.done ? sec.fixedWords.slice(0, sec.fixedN).join(" ") : ""
        replayText: sec.words ? sec.fixedWords.join(" ") : ""
    }

    PrefSwitch {
        title: "Text"; titleWidth: sec.titleWidth
        store: DiacriticsPrefs; key: "show_text"
        hint: "Show the text in the pill"
        info: "On = the pill shows the real words while they are fixed. Off = a generic animation, so nobody looking at the screen can read your text."
    }
}
