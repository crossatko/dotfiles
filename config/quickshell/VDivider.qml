import QtQuick

// A vertical hairline between two groups of controls in a row (e.g. MediaPanel's volume | session actions): as tall as a
// control (Theme.controlH), the line inset by `inset` at both ends. The caller hides it while a neighbouring group is hidden.
Item {
    property int inset: Theme.gapTight
    implicitWidth: 1
    implicitHeight: Theme.controlH
    Rectangle { x: 0; y: parent.inset; width: 1; height: parent.height - 2 * parent.inset; color: Theme.edge }
}
