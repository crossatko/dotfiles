pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Pipewire

// Current audio device with a dropdown of all the others (hardware only: no streams, monitors or
// filters). Choosing one sets Pipewire's preferred default, i.e. what `wpctl set-default` does.
// A DropSelect fed with the Pipewire nodes.
DropSelect {
    id: dp

    property bool isSink: true

    readonly property var pwCurrent: isSink ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource
    readonly property string wantClass: isSink ? "Audio/Sink" : "Audio/Source"
    readonly property var devices: Pipewire.nodes.values.filter(n =>   // qmllint disable missing-property
        !n.isStream && n.isSink === isSink && n.properties && n.properties["media.class"] === wantClass)

    function label(n) { return n ? (n.description || n.nickname || n.name) : "No device" }

    options: devices.map(n => ({ label: label(n) }))
    currentIndex: pwCurrent ? devices.findIndex(n => n.id === pwCurrent.id) : -1
    emptyText: label(pwCurrent)
    // the default node may be missing from the list (a filter): still show its name in the head
    headText: currentIndex < 0 && pwCurrent ? label(pwCurrent) : ""
    onPicked: i => {
        if (isSink) Pipewire.preferredDefaultAudioSink = devices[i]
        else Pipewire.preferredDefaultAudioSource = devices[i]
    }

    // properties (media.class, ...) are only filled in for nodes something is bound to
    PwObjectTracker { objects: Pipewire.nodes.values }   // qmllint disable missing-property
}
