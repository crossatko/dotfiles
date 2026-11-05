pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// The speech model part of a Settings page (dictation): per language mode (English, Czech, Czech to English) the Fast
// (live) and the Full (final) model (SttModeGroup, shown first), then every catalog model (SttModelRow) with its size,
// VRAM, translation and Czech marks, Download / Cancel / Resume / Delete (a local model is added by hand: the row says
// where to copy it). A model that cannot serve a mode is not offered there (English-only ones serve English only; the
// full pass of translation needs a model that can translate); a refused change shows its reason in red. With no
// model installed it says to download one; nothing downloads by itself. After the roles: how long the models stay loaded
// (IdleUnloadRow over DictationPrefs, as the Diacritics page's Model section). All state is SttModels (roles in its prefs
// file, `changed` / `resetAll()` for the page's PageReset) and DictationPrefs (the idle time). Drop it into a page: `SttModelsSection { titleWidth: ... }`.
ColumnLayout {
    id: sec
    property int titleWidth: 120
    readonly property bool dragging: idle.dragging      // the idle slider: the page must not scroll

    Layout.fillWidth: true
    spacing: Theme.gapRow

    Component.onCompleted: SttModels.refresh()

    SectionHead {
        title: "Speech models"
        detail: SttModels.loaded && SttModels.modelsDir !== "" ? "stored outside the config" : ""
        InfoTip { text: SttModels.modelsDir !== "" ? "Downloaded to " + SttModels.modelsDir + ", checked against the official checksum." : "" }
    }

    EmptyState {
        visible: SttModels.noneInstalled
        objectName: "models-none"
        icon: Icons.download
        text: "No speech model installed"
        hint: SttModels.missingMessage
    }

    Repeater {
        model: SttModels.modes
        SttModeGroup {
            required property var modelData
            mode: modelData.key; title: modelData.label; info: modelData.info ?? ""; titleWidth: sec.titleWidth
        }
    }
    IdleUnloadRow { id: idle; objectName: "dict-idle"; titleWidth: sec.titleWidth; store: DictationPrefs; use: "dictation" }
    Label {
        objectName: "role-notice"
        visible: SttModels.notice !== ""
        Layout.fillWidth: true
        text: SttModels.notice
        color: Theme.red; font.pixelSize: Theme.fontCaption
        wrapMode: Text.WordWrap
    }
    Label {
        visible: SttModels.listError !== ""
        Layout.fillWidth: true
        text: SttModels.listError
        color: Theme.red; font.pixelSize: Theme.fontCaption
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.gapTight
        Repeater {
            model: SttModels.models
            SttModelRow {
                required property var modelData
                Layout.fillWidth: true
                m: modelData
            }
        }
    }
}
