pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// The speech model part of a Settings page (dictation): which model does the live passes and which one the final pass
// and translation (shown first), then every catalog model (SttModelRow) with its size, VRAM, translation and Czech
// marks, Download / Cancel / Resume / Delete, and the Live / Final buttons that assign the roles. A role a model cannot
// take is refused with the reason in red (the final pass translates: a model that cannot translate is refused). With no
// model installed it says to download one; nothing downloads by itself. All state is SttModels (roles in its prefs
// file, `changed` / `resetAll()` for the page's PageReset). Drop it into a page: `SttModelsSection { titleWidth: ... }`.
ColumnLayout {
    id: sec
    property int titleWidth: 120

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

    SttRoleRow {
        title: "Live passes"; titleWidth: sec.titleWidth; role: "live"
        info: "Typing as you speak. Any model; a faster one keeps up better."
    }
    SttRoleRow {
        title: "Final pass"; titleWidth: sec.titleWidth; role: "final"
        info: "The corrected text after you release the key, and Czech to English translation. Only models that can translate."
    }
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
