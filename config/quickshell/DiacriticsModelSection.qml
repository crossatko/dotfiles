import QtQuick
import QtQuick.Layouts

// Settings > Diacritics > Model: which .gguf file of the models folder fixes the text (DropSelect over
// DiacriticsPrefs.models; the saved one stays listed, marked "not found", when its file is gone) and how long it stays
// loaded after the last run (ChoiceRow, DiacriticsPrefs.idleValues). The service applies both to the next run.
ColumnLayout {
    id: sec
    property real titleWidth: 120

    // the files of the folder, then the saved one when it is not among them
    readonly property var modelOptions: {
        const o = DiacriticsPrefs.models.map(n => ({ label: n, name: n }))
        if (!DiacriticsPrefs.models.includes(DiacriticsPrefs.model))
            o.push({ label: DiacriticsPrefs.model, name: DiacriticsPrefs.model, note: "not found", noteTint: Theme.yellow })
        return o
    }
    readonly property int modelIndex: Math.max(0, modelOptions.findIndex(o => o.name === DiacriticsPrefs.model))

    Layout.fillWidth: true
    spacing: Theme.gapRow

    Component.onCompleted: DiacriticsPrefs.refreshModels()

    SectionHead {
        title: "Model"
        detail: DiacriticsPrefs.overridden("model") || DiacriticsPrefs.overridden("idle_timeout_s") ? "changed" : ""
        InfoTip { text: "The .gguf files in the diacritics models folder (the data folder of the user, outside the repo). A smaller model is faster and uses less memory. Loaded on the first run, unloaded after the idle time." }
    }
    SettingRow {
        title: "Model"; titleWidth: sec.titleWidth; titleTopAt: 15
        DropSelect {
            objectName: "diac-model"
            Layout.preferredWidth: 400; Layout.alignment: Qt.AlignTop
            options: sec.modelOptions
            currentIndex: sec.modelIndex
            emptyText: "No model files found"
            onToggled: open => { if (open) DiacriticsPrefs.refreshModels() }
            onPicked: i => DiacriticsPrefs.set("model", sec.modelOptions[i].name)
        }
        Item { Layout.fillWidth: true }
    }
    ChoiceRow {
        objectName: "diac-idle"
        title: "Unload model"; titleWidth: sec.titleWidth
        values: DiacriticsPrefs.idleValues; labels: DiacriticsPrefs.idleLabels
        current: DiacriticsPrefs.idleTimeoutS
        info: "How long the model stays in memory after the last run. Unloading frees the memory; the next run loads it again."
        onPicked: v => DiacriticsPrefs.set("idle_timeout_s", v)
    }
}
