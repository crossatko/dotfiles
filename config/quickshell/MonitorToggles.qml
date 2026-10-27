pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

// Settings rows: one toggle per connected monitor (model name + connector), keyed by Appearance.monitorKey, for a
// "show on these monitors" map (Settings > Desktop clock, Settings > Lock screen "Screens"). `isOn(key)` reads it,
// `toggled(key, on)` asks for a change; a monitor not in the map is on (hot-plugged ones too). `idPrefix` names the
// toggles' objectName ("<idPrefix>-<connector>").
ColumnLayout {
    id: mt
    property var isOn: key => true
    property bool enabledLook: true
    property string idPrefix: "toggle-monitor"
    property real titleWidth: 120
    signal toggled(string key, bool on)
    readonly property var monitors: Quickshell.screens.filter(s => s && s.width > 0)
    spacing: 12
    Repeater {
        model: mt.monitors
        delegate: SettingRow {
            id: mrow
            required property var modelData
            readonly property string key: Appearance.monitorKey(modelData)
            Layout.fillWidth: true
            titleWidth: mt.titleWidth
            Toggle {
                objectName: mt.idPrefix + "-" + mrow.modelData.name
                checked: mt.isOn(mrow.key)
                enabledLook: mrow.key !== "" && mt.enabledLook
                onToggled: want => mt.toggled(mrow.key, want)
            }
            Icon { text: "\uf390"; font.pixelSize: 12; color: Theme.fgDim; Layout.preferredWidth: 16; horizontalAlignment: Text.AlignHCenter }
            Label { text: mrow.modelData.model || mrow.modelData.name; color: Theme.fgDim; font.pixelSize: Theme.fontSmall; elide: Text.ElideRight; Layout.maximumWidth: 220 }
            Label { text: mrow.modelData.name; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true; elide: Text.ElideRight }
        }
    }
}
