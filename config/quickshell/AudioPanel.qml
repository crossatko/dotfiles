import QtQuick
import QtQuick.Layouts

// Audio popup (click the volume chip in the bar): output + input volume and device selection.
ColumnLayout {
    spacing: 12
    implicitHeight: 200

    Label { text: "Audio"; font.pixelSize: 17; font.bold: true }
    AudioSection { Layout.fillWidth: true }
}
