import QtQuick
import QtQuick.Layouts

// Audio popup (click the volume chip in the bar): output + input volume and device selection.
ColumnLayout {
    spacing: Theme.pad

    PanelHeader { title: "Audio" }
    AudioSection { Layout.fillWidth: true }
}
