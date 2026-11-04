pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings > Voice > Dictation: the microphone (the system default source, or one of the PipeWire sources), GPU on / off and which GPU (GpuDeviceRow),
// how long the model stays loaded after the last dictation, and whether the replacement words also go to the recognizer
// as hints, and the pill's edge. All state is DictationPrefs (dictation-prefs.json; the service applies it to the next dictation);
// `changed` / `resetAll()` for the page's PageReset. Drop it into a page: `DictationPrefsSection { titleWidth: ... }`.
ColumnLayout {
    id: sec
    property real titleWidth: 120

    // [System default, the sources, the saved one when it is not plugged in]
    readonly property var micOptions: {
        const o = [{ label: "System default" }]
        for (const s of DictationPrefs.sources) o.push({ label: s.label, name: s.name })
        const m = DictationPrefs.mic
        if (m !== "" && !DictationPrefs.sources.some(s => s.name === m))
            o.push({ label: m, name: m, note: "not found", noteTint: Theme.yellow })
        return o
    }
    readonly property int micIndex: Math.max(0, micOptions.findIndex(o => (o.name ?? "") === DictationPrefs.mic))

    Layout.fillWidth: true
    spacing: Theme.gapRow

    Component.onCompleted: DictationPrefs.refreshSources()

    SectionHead {
        title: "Dictation"
        InfoTip { text: "Saved in dictation-prefs.json next to the other shell settings. A change applies to the next dictation." }
    }

    SettingRow {
        title: "Microphone"; titleWidth: sec.titleWidth; titleTopAt: 15
        DropSelect {
            objectName: "dict-mic"
            Layout.preferredWidth: 340; Layout.alignment: Qt.AlignTop
            options: sec.micOptions
            currentIndex: sec.micIndex
            onToggled: open => { if (open) DictationPrefs.refreshSources() }
            onPicked: i => DictationPrefs.set("mic", sec.micOptions[i].name ?? "")
        }
        InfoTip { Layout.alignment: Qt.AlignTop; text: "System default follows the default input of PipeWire. Pick one to always use that microphone." }
        Item { Layout.fillWidth: true }
    }
    PrefSwitch {
        title: "GPU"; titleWidth: sec.titleWidth
        store: DictationPrefs; key: "gpu"
        hint: "Use the graphics card"
        info: "Vulkan is much faster. Off = the processor does the recognition (slow, but frees the graphics card)."
    }
    GpuDeviceRow { titleWidth: sec.titleWidth; visible: DictationPrefs.gpu }
    ChoiceRow {
        objectName: "dict-idle"
        title: "Unload model"; titleWidth: sec.titleWidth
        values: DictationPrefs.idleValues; labels: DictationPrefs.idleLabels
        current: DictationPrefs.idleTimeoutS
        info: "How long the model stays in memory after the last dictation. Unloading frees the memory (the next dictation loads it again); Never keeps it loaded."
        onPicked: v => DictationPrefs.set("idle_timeout_s", v)
    }
    PrefSwitch {
        title: "Hints"; titleWidth: sec.titleWidth
        store: DictationPrefs; key: "prompt_hints"
        hint: "Use replacement words as recognition hints"
        info: "Gives the replacement words to the recognizer so it spells them right in the first place. May hurt accuracy. Never used when translating."
    }
    PrefSwitch {
        title: "Pill"; titleWidth: sec.titleWidth
        store: DictationPrefs; key: "pill_bottom"
        hint: "Show the pill at the bottom"
        info: "Off = the pill hangs off the bar, on whichever edge the bar is. On = it always sits at the bottom edge of the screen."
    }
}
