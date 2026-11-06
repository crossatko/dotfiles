import QtQuick
import QtQuick.Layouts

// A Settings row choosing one installed font family (Fonts.qml): title | a scrolling DropSelect whose entries are drawn
// in their own font | info tip. kind "ui" lists the families the shell can use, "mono" the monospaced ones only.
SettingRow {
    id: row
    property string kind: "ui"
    property string info: ""
    readonly property var families: kind === "mono" ? Fonts.monoList : Fonts.uiList
    readonly property string chosen: kind === "mono" ? Fonts.mono : Fonts.ui

    titleTopAt: Theme.controlH / 2

    DropSelect {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        objectName: "font-" + row.kind
        maxListHeight: 7 * (Theme.controlH + Theme.gapTight)
        options: row.families.map(f => ({ label: f, family: f }))
        currentIndex: row.families.indexOf(row.chosen)
        headText: row.families.length === 0 ? row.chosen : ""
        onPicked: i => Fonts.set(row.kind, row.families[i])
    }
    InfoTip { Layout.alignment: Qt.AlignTop; Layout.topMargin: Math.round((Theme.controlH - 16) / 2); text: row.info }
}
