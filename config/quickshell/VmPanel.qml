pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Virtual machine popup (VM chip): running quickemu VMs with CPU / memory / disk / uptime and Show / Shut down,
// plus the background downloads (progress, speed, ETA, Cancel). Data: VmService.qml. Sampling runs only
// while this panel exists (it is created on open and destroyed on close).
ColumnLayout {
    id: vp
    spacing: 10

    Binding { target: VmService; property: "panelOpen"; value: true }
    Component.onCompleted: VmService.poll()

    PanelHeader {
        title: "Virtual machines"
        showStatus: true
        status: VmService.vms.length + " running"
    }

    // downloads / installation prep
    Repeater {
        model: VmService.jobIds
        delegate: Notice {
            id: jc
            required property string modelData
            readonly property var job: VmService.jobByKey(modelData) || ({ id: "", label: "", state: "done", pct: -1, speed: 0, eta: -1, bytes: 0, total: 0, name: "", error: "", phase: "" })
            readonly property bool running: job.state === "running"
            danger: job.state === "failed"
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Label { text: ""; font.family: Theme.iconFont; font.styleName: "Regular"; color: Theme.accent; font.pixelSize: 14 }
                Label { text: jc.job.label; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                Btn {
                    text: jc.running ? "Cancel" : "Dismiss"
                    outerRadius: Theme.radiusItem; inset: 12
                    implicitHeight: 24
                    onClicked: VmService.cancel(jc.job.id)
                }
            }
            Meter {
                visible: jc.running || jc.job.state === "done"
                Layout.fillWidth: true
                value: jc.job.pct >= 0 ? jc.job.pct / 100 : 0
                fillColor: jc.job.state === "done" ? Theme.green : Theme.accent
                animMs: 300
            }
            Label {
                Layout.fillWidth: true
                text: VmService.jobDetail(jc.job) + (jc.running && jc.job.total > 0 ? "  ·  " + VmService.fmtBytes(jc.job.bytes) + " of " + VmService.fmtBytes(jc.job.total) : "")
                color: jc.job.state === "failed" ? Theme.red : Theme.fgDim
                font.pixelSize: Theme.fontCaption
                wrapMode: Text.Wrap
            }
        }
    }

    // running VMs
    Repeater {
        model: VmService.vmNames
        delegate: Rectangle {
            id: card
            required property string modelData
            readonly property var vm: VmService.vmByName(modelData) || ({ name: modelData, monitor: false, ram: 0, rss: 0, cpu: -1, cores: 0, uptime: 0, display: "", diskUsed: 0, diskTotal: 0 })
            Layout.fillWidth: true
            implicitHeight: body.implicitHeight + 24
            radius: Theme.radiusItem
            color: Theme.alpha(Theme.fg, 0.06)
            border.width: 1
            border.color: Theme.alpha(Theme.overlay, 0.6)

            readonly property real memFrac: vm.ram > 0 ? Math.min(1, vm.rss / vm.ram) : 0
            readonly property real diskFrac: vm.diskTotal > 0 ? Math.min(1, vm.diskUsed / vm.diskTotal) : 0
            readonly property real cpuFrac: vm.cpu >= 0 && vm.cores > 0 ? Math.min(1, vm.cpu / 100 / vm.cores) : 0

            RowLayout {
                id: body
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 4; color: Theme.green }
                        Label { text: card.vm.name; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    Label {
                        text: "Running " + VmService.fmtDuration(card.vm.uptime) + (card.vm.display === "headless" ? "  ·  headless" : "")
                        color: Theme.fgDim; font.pixelSize: Theme.fontCaption
                    }
                    VmMeterRow {
                        Layout.fillWidth: true
                        label: "CPU"; value: card.cpuFrac
                        text: card.vm.cpu >= 0 ? Math.round(card.vm.cpu) + "%" : "…"
                    }
                    VmMeterRow {
                        Layout.fillWidth: true
                        label: "RAM"; value: card.memFrac; fillColor: Theme.accent2
                        text: VmService.fmtBytes(card.vm.rss) + (card.vm.ram > 0 ? " / " + VmService.fmtBytes(card.vm.ram) : "")
                    }
                    VmMeterRow {
                        visible: card.vm.diskTotal > 0
                        Layout.fillWidth: true
                        label: "Disk"; value: card.diskFrac; fillColor: Theme.green
                        text: VmService.fmtBytes(card.vm.diskUsed) + " / " + VmService.fmtBytes(card.vm.diskTotal)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Label {
                            Layout.fillWidth: true
                            text: card.vm.cores > 0 ? card.vm.cores + " vCPU" : ""
                            color: Theme.muted; font.pixelSize: Theme.fontCaption
                        }
                        Btn {
                            text: "Show"; outerRadius: Theme.radiusItem; inset: 12; implicitHeight: 26
                            onClicked: { VmService.focus(card.vm.name); Popups.close() }
                        }
                        Btn {
                            text: "Shut down"; outerRadius: Theme.radiusItem; inset: 12; implicitHeight: 26
                            onClicked: VmService.stop(card.vm.name)
                        }
                    }
                }
            }
        }
    }

    MissingPackage { bundle: "virtualization" }   // quickemu / quickget not installed: copy the install command

    Notice {
        visible: VmService.vms.length === 0 && VmService.allJobs.length === 0
        Label { text: "Nothing running"; font.bold: true }
    }
}
