import QtQuick

// Settings > Voice > Pill: how much of the running text the pill shows while you talk (DictationPrefs.pillPreviewLines):
// "Grow" = the pill gets taller (and a little wider) as the text arrives, up to the screen; a number = at most that many lines.
// Either way the newest words stay in view and the oldest lines scroll out.
ChoiceRow {
    title: "Preview lines"
    objectName: "dict-pill-lines"
    values: [0, 1, 2, 3, 4]
    labels: ["Grow", "1", "2", "3", "4"]
    objectNames: values.map(v => "dict-pill-lines-" + v)
    current: DictationPrefs.pillPreviewLines
    info: "How many lines of your words the pill shows while you talk. Grow: the pill gets taller as you speak, up to the screen. A number: at most that many lines, the oldest scroll out. Nothing is typed until you release the key."
    onPicked: v => DictationPrefs.set("pill_preview_lines", v)
}
