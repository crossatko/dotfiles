import QtQuick
import QtQuick.Layouts

// The virtual machine chip (Bar.qml widget "vm"): hidden unless a VM runs or a download / install prep job exists
// (VmService). Shows the VM icon + number of running VMs; while a job runs also a thin progress bar and the
// percentage (the name is in the popup) (or its phase while the size is unknown), "+N" for more jobs.
Chip {
    id: chip
    readonly property var job: VmService.activeJob
    show: VmService.busy
    readonly property int meterW: 48       // width of the job progress bar

    BarIcon { text: Icons.vm; color: chip.job || VmService.vms.length > 0 ? chip.ink.accent : chip.ink.muted }
    Meter {
        visible: chip.job !== null
        Layout.preferredWidth: chip.meterW; Layout.preferredHeight: Theme.gapTight; Layout.alignment: Qt.AlignVCenter
        implicitHeight: Theme.gapTight
        value: chip.job && chip.job.pct >= 0 ? chip.job.pct / 100 : 0
        fillColor: chip.ink.accent
        animMs: Motion.emphasisMs
    }
    BarLabel { visible: chip.job !== null && chip.job.pct >= 0; text: chip.job ? Math.floor(chip.job.pct) + "%" : ""; color: chip.ink.fgDim }
    BarLabel { visible: chip.job !== null && chip.job.pct < 0; text: chip.job ? chip.job.phase : ""; color: chip.ink.fgDim; elide: Text.ElideRight; Layout.maximumWidth: 90 }
    BarLabel { visible: VmService.runningJobs.length > 1; text: "+" + (VmService.runningJobs.length - 1); color: chip.ink.fgDim }
    BarLabel { visible: VmService.vms.length > 0; text: String(VmService.vms.length); color: chip.ink.fg; Layout.leftMargin: chip.job ? Theme.chipGap : 0 }
}
