import QtQuick
import QtQuick.Layouts

// Settings row: which GPU the dictation worker uses (DictationPrefs.gpuDevice), from GpuDevices (the worker's own list). The first
// GPU is the default; an integrated one gets a warning (slow, for testing). Without a list (worker missing or built before
// --list-devices) the row says so and keeps the saved index; the saved index is also shown when its GPU is not listed.
SettingRow {
    id: row

    readonly property var options: {
        const o = []
        for (const d of GpuDevices.devices)
            o.push(d.type === "integrated" ? { label: d.name, note: "integrated", noteTint: Theme.yellow } : { label: d.name })
        const i = DictationPrefs.gpuDevice
        if (GpuDevices.state === "ok" && !GpuDevices.byIndex(i)) o.push({ label: "GPU " + i, note: "not found", noteTint: Theme.yellow })
        return o
    }
    readonly property int index: Math.max(0, options.findIndex((o, n) => n < GpuDevices.devices.length ? GpuDevices.devices[n].index === DictationPrefs.gpuDevice : true))
    readonly property var chosen: GpuDevices.byIndex(DictationPrefs.gpuDevice)
    readonly property bool slow: chosen !== null && chosen.type === "integrated"
    readonly property string headText: GpuDevices.state === "ok" ? ""
        : GpuDevices.state === "loading" || GpuDevices.state === "idle" ? "Reading the list..."
        : DictationPrefs.gpuDevice === 0 ? "First GPU (worker not built or too old)" : "GPU " + DictationPrefs.gpuDevice + " (the list needs a rebuilt worker)"

    objectName: "dict-gpu-device"
    title: "GPU device"
    titleTopAt: 15
    Component.onCompleted: GpuDevices.refresh()

    DropSelect {
        objectName: "dict-gpu-device-select"
        Layout.preferredWidth: 340; Layout.alignment: Qt.AlignTop
        options: row.options
        currentIndex: row.index
        headText: row.headText
        onToggled: open => { if (open) GpuDevices.refresh() }
        onPicked: i => DictationPrefs.set("gpu_device", GpuDevices.devices[i]?.index ?? DictationPrefs.gpuDevice)
    }
    InfoTip {
        objectName: "info-gpu-device-warn"
        Layout.alignment: Qt.AlignTop
        visible: row.slow
        icon: Icons.warning; color: Theme.yellow
        text: "For testing: much slower, the pill preview will lag."
    }
    InfoTip {
        objectName: "info-gpu-device"
        Layout.alignment: Qt.AlignTop
        visible: !row.slow
        text: GpuDevices.state === "unavailable"
            ? "The list comes from the dictation worker, which is missing or too old: build it with config/dictation/worker/build.sh. The default (first) GPU is used."
            : "The first GPU is the fast one. Another one is for testing; a change applies to the next dictation (the models reload)."
    }
    Item { Layout.fillWidth: true }
}
