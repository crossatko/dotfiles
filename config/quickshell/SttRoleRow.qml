import QtQuick
import QtQuick.Layouts

// One speech model role row of SttModelsSection: the role's model (muted while not installed, with a yellow mark) and
// an InfoTip about the role. `role` = "live" | "final" (SttModels.value).
SettingRow {
    id: rr
    property string role: "live"
    property string info: ""
    readonly property string name: SttModels.value(role)
    readonly property bool missing: SttModels.loaded && !SttModels.isInstalled(name)
    Label {
        objectName: "role-" + rr.role
        text: SttModels.labelOf(rr.name)
        color: rr.missing ? Theme.muted : Theme.fg
        font.pixelSize: Theme.fontSmall
    }
    Label {
        visible: rr.missing
        text: "not installed"; color: Theme.yellow; font.pixelSize: Theme.fontCaption
    }
    InfoTip { text: rr.info }
    Item { Layout.fillWidth: true }
}
