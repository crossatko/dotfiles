import QtQuick
import QtQuick.Layouts
import "launcher/js/IdleSteps.js" as Steps

// Settings > Voice / Diacritics > Model: how long the model stays loaded after its last use, a stepped slider over the shared
// steps (launcher/js/IdleSteps.js: Immediately, 15 s … 1 h, Never), the step's label and a reset glyph (PrefSlider's anatomy).
// `store` = DictationPrefs or DiacriticsPrefs (idleTimeoutS, defaults.idle_timeout_s, set("idle_timeout_s", v)). A saved value
// that is no step shows as the nearest one and is only rewritten when the slider is moved.
SettingRow {
    id: row
    property var store: null
    property string use: "run"            // the word for one use in the tip ("dictation", "run")
    property string extra: ""             // a last sentence for the tip
    property real valueWidth: 90          // the value column: wider than PrefSlider's 62, "Immediately" fits
    readonly property int last: Steps.VALUES.length - 1
    readonly property int index: Math.max(0, Steps.VALUES.indexOf(Steps.nearest(store ? store.idleTimeoutS : 0)))
    readonly property int defaultIndex: Math.max(0, Steps.VALUES.indexOf(Steps.nearest(store ? store.defaults.idle_timeout_s : 600)))
    readonly property bool own: index !== defaultIndex
    readonly property bool dragging: hold.running
    Timer { id: hold; interval: 300 }
    function pick(i) {
        const v = Steps.VALUES[Math.max(0, Math.min(last, i))]
        if (store && Steps.nearest(store.idleTimeoutS) !== v) store.set("idle_timeout_s", v)
    }

    title: "Unload model"
    Slider {
        wheel: false
        objectName: (row.objectName || "idle") + "-slider"
        Layout.fillWidth: true
        value: row.index / row.last
        step: 1 / row.last
        notches: [{ v: row.defaultIndex / row.last, kind: "default" }]
        resetToNotch: false
        onResetRequested: row.pick(row.defaultIndex)
        onMoved: v => { hold.restart(); row.pick(Math.round(v * row.last)) }
    }
    Label { text: Steps.LABELS[row.index]; Layout.preferredWidth: row.valueWidth; horizontalAlignment: Text.AlignRight; color: Theme.fg; font.pixelSize: Theme.fontSmall }
    ResetBtn { set: row.own; onClicked: if (row.own) row.pick(row.defaultIndex) }
    InfoTip { text: "How long the model stays in memory after the last " + row.use + ". Immediately = unloaded as soon as it is over (the next " + row.use + " loads it again, slower); Never keeps it loaded." + (row.extra !== "" ? " " + row.extra : "") }
}
