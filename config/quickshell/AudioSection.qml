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

    LevelRow {
        icon: Icons.volumeGlyph(!au.sink || au.sink.muted, au.sink ? au.sink.volume : 0)
        iconColor: au.sink && au.sink.muted ? Theme.muted : Theme.accent
        iconClickable: true
        onIconClicked: if (au.sink) au.sink.muted = !au.sink.muted
        value: au.sink ? au.sink.volume : 0
        dim: !au.sink || au.sink.muted
        onMoved: v => { if (au.sink) { au.sink.muted = false; au.sink.volume = v } }
        valueText: au.sink ? Math.round(au.sink.volume * 100) + "%" : "–"
    }
    DevicePicker { Layout.fillWidth: true; isSink: true }
    BtProfilePicker { Layout.fillWidth: true }

    LevelRow {
        Layout.topMargin: 4
        visible: au.source !== null
        icon: au.source && au.source.muted ? "\uf131" : "\uf130"
        iconColor: au.source && au.source.muted ? Theme.muted : Theme.accent
        iconClickable: true
        onIconClicked: if (au.source) au.source.muted = !au.source.muted
        value: au.source ? au.source.volume : 0
        dim: !au.source || au.source.muted
        onMoved: v => { if (au.source) { au.source.muted = false; au.source.volume = v } }
        valueText: au.source ? Math.round(au.source.volume * 100) + "%" : "–"
    }
    DevicePicker { Layout.fillWidth: true; isSink: false; visible: au.source !== null }
}
