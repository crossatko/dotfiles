import QtQuick
import QtQuick.Layouts

// One model choice of SttModelsSection: the model for `role` ("live" = Fast, "final" = Full) in `mode` ("en" | "cs" |
// "translate", SttModels.modes). A DropSelect lists the installed models that can do the job there (an English-only
// model is not offered for Czech or translation, a model that cannot translate is not offered for the full pass of
// translate mode). A saved choice that is not installed stays listed, marked in yellow, so it is never silently changed.
SettingRow {
    id: rr
    property string mode: "en"
    property string role: "live"
    property string info: ""
    readonly property string name: SttModels.pick(mode, role)
    readonly property var names: {
        const out = SttModels.models.filter(m => m.installed && SttModels.fitProblem(rr.mode, rr.role, m) === "").map(m => m.name)
        if (rr.name !== "" && out.indexOf(rr.name) < 0) out.push(rr.name)
        return out
    }
    readonly property bool missing: SttModels.loaded && !SttModels.isInstalled(name)
    readonly property bool misfit: SttModels.loaded && SttModels.model(name) !== null && SttModels.fitProblem(mode, role, SttModels.model(name)) !== ""

    objectName: "role-" + mode + "-" + role
    titleTopAt: 15
    DropSelect {
        objectName: "role-select-" + rr.mode + "-" + rr.role
        Layout.preferredWidth: 340; Layout.alignment: Qt.AlignTop
        options: rr.names.map(n => (n === rr.name && (rr.missing || rr.misfit))
            ? { label: SttModels.labelOf(n), note: rr.missing ? "not installed" : "cannot do this", noteTint: Theme.yellow }
            : { label: SttModels.labelOf(n), note: n === SttModels.defaultOf(rr.mode, rr.role) ? "default" : "" })
        currentIndex: rr.names.indexOf(rr.name)
        onPicked: i => SttModels.setRole(rr.mode, rr.role, rr.names[i])
    }
    InfoTip { Layout.alignment: Qt.AlignTop; text: rr.info }
    Item { Layout.fillWidth: true }
}
