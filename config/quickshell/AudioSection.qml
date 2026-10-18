import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

// Output + input volume with device pickers. Shared by the control center and the Audio popup.
// Clicking a speaker / microphone icon mutes it.
ColumnLayout {
    id: au
    spacing: 6

    PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }
    readonly property var sink: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
    readonly property var source: Pipewire.defaultAudioSource ? Pipewire.defaultAudioSource.audio : null

    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        Icon {
            text: !au.sink || au.sink.muted ? "\uf6a9" : au.sink.volume < 0.01 ? "\uf026" : au.sink.volume < 0.5 ? "\uf027" : "\uf028"
            horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 24
            font.pixelSize: 17
            color: au.sink && au.sink.muted ? Theme.muted : Theme.accent
            MouseArea { anchors.fill: parent; anchors.margins: -5; cursorShape: Qt.PointingHandCursor; onClicked: if (au.sink) au.sink.muted = !au.sink.muted }
        }
        Slider {
            Layout.fillWidth: true
            value: au.sink ? au.sink.volume : 0
            dim: !au.sink || au.sink.muted
            onMoved: v => { if (au.sink) { au.sink.muted = false; au.sink.volume = v } }
        }
        Label { text: au.sink ? Math.round(au.sink.volume * 100) + "%" : "–"; Layout.preferredWidth: 40; horizontalAlignment: Text.AlignRight; color: Theme.fgDim; font.pixelSize: 12 }
    }
    DevicePicker { Layout.fillWidth: true; isSink: true }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        visible: au.source !== null
        spacing: 10
        Icon {
            text: au.source && au.source.muted ? "\uf131" : "\uf130"
            horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 24
            font.pixelSize: 17
            color: au.source && au.source.muted ? Theme.muted : Theme.accent
            MouseArea { anchors.fill: parent; anchors.margins: -5; cursorShape: Qt.PointingHandCursor; onClicked: if (au.source) au.source.muted = !au.source.muted }
        }
        Slider {
            Layout.fillWidth: true
            value: au.source ? au.source.volume : 0
            dim: !au.source || au.source.muted
            onMoved: v => { if (au.source) { au.source.muted = false; au.source.volume = v } }
        }
        Label { text: au.source ? Math.round(au.source.volume * 100) + "%" : "–"; Layout.preferredWidth: 40; horizontalAlignment: Text.AlignRight; color: Theme.fgDim; font.pixelSize: 12 }
    }
    DevicePicker { Layout.fillWidth: true; isSink: false; visible: au.source !== null }
}
