pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// One BlurTuneCtl option as a Settings row, by its kind: float / int = GlassOptRow (slider, value, reset), bool = switch
// row, color = ArgbRow. `o` = a BlurTuneCtl.opts entry; the value and every edit go through BlurTuneCtl. dragged() fires
// on every slider move (the page stops the Flickable from stealing the drag).
Loader {
    id: row
    required property var o
    property real titleW: 120
    property real valueW: 62
    readonly property real cur: BlurTuneCtl.values[o.key] ?? o.def
    readonly property bool changed: BlurTuneCtl.isChanged(o.key)
    signal dragged()
    Layout.fillWidth: true
    Layout.preferredHeight: item ? (item as Item).implicitHeight : 0
    Binding { target: row.item; property: "width"; value: row.width; when: row.item !== null }

    sourceComponent: o.kind === "bool" ? boolRow : o.kind === "color" ? colorRow : sliderRow

    Component {
        id: sliderRow
        GlassOptRow {
            o: row.o
            cur: row.cur
            title: row.o.label
            titleWidth: row.titleW
            valueW: row.valueW
            changed: row.changed
            resetName: "reset-blur-" + row.o.key
            onMoved: v => { row.dragged(); BlurTuneCtl.set(row.o.key, v) }
            onReset: BlurTuneCtl.reset(row.o.key)
        }
    }
    Component {
        id: boolRow
        SettingRow {
            title: row.o.label
            titleWidth: row.titleW
            Toggle {
                objectName: "toggle-blur-" + row.o.key
                checked: row.cur >= 0.5
                onToggled: want => BlurTuneCtl.set(row.o.key, want ? 1 : 0)
            }
            Item { Layout.fillWidth: true }
            ResetBtn {
                objectName: "reset-blur-" + row.o.key
                set: row.changed
                onClicked: BlurTuneCtl.reset(row.o.key)
            }
        }
    }
    Component {
        id: colorRow
        ArgbRow {
            title: row.o.label
            objectPrefix: "blur-" + row.o.key.replace(/[:_]/g, "-")
            titleW: row.titleW
            valueW: row.valueW
            value: row.cur
            defaultValue: row.o.def
            onEdited: (shift, argb) => { row.dragged(); BlurTuneCtl.set(row.o.key, argb) }
            onReset: BlurTuneCtl.reset(row.o.key)
        }
    }
}
