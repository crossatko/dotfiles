import QtQuick

// Settings > Voice / Diacritics > Model: how long the model stays loaded after its last use. `store` = DictationPrefs or
// DiacriticsPrefs (idleValues / idleLabels / idleTimeoutS / set("idle_timeout_s", v); a saved other value shows Custom).
ChoiceRow {
    id: row
    property var store: null
    property string use: "run"            // the word for one use in the tip ("dictation", "run")
    property string extra: ""             // a last sentence for the tip
    title: "Unload model"
    values: store ? store.idleValues : []
    labels: store ? store.idleLabels : []
    current: store ? store.idleTimeoutS : 0
    info: "How long the model stays in memory after the last " + use + ". Unloading frees the memory; the next " + use + " loads it again." + (extra !== "" ? " " + extra : "")
    onPicked: v => row.store.set("idle_timeout_s", v)
}
