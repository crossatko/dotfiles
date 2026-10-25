import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

// Audio popup (click the volume chip in the bar): output + input volume and device selection, then the AirPods
// section while AirPods are connected.
ColumnLayout {
    spacing: 12

    PanelHeader { title: "Audio" }
    AudioSection { Layout.fillWidth: true }
    AirPodsSection {
        Layout.fillWidth: true
        Layout.topMargin: 4
        // connected AirPods, or (daemon down, so nothing is known) an AirPods-looking default output: then the notice
        visible: AirPods.connected || (!AirPods.daemon && AirPods.looksLike(Pipewire.defaultAudioSink))
    }
}
