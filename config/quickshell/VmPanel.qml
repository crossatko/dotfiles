pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Virtual machine popup (VM chip): running quickemu VMs with a live preview, CPU / memory / uptime and Show / Shut down,
// plus the background downloads (progress, speed, ETA, Cancel). Data: VmService.qml. Sampling and previews run only
// while this panel exists (it is created on open and destroyed on close).
ColumnLayout {
    id: vp
    spacing: 10

    Binding { target: VmService; property: "panelOpen"; value: true }
    property real nowMs: Date.now()                  // for the preview age; ticks only while the panel exists
    Timer { interval: 1000; repeat: true; running: true; onTriggered: vp.nowMs = Date.now() }
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
            readonly property var vm: VmService.vmByName(modelData) || ({ name: modelData, monitor: false, ram: 0, rss: 0, cpu: -1, cores: 0, uptime: 0, display: "" })
            Layout.fillWidth: true
            implicitHeight: body.implicitHeight + 24
            radius: Theme.radiusItem
            color: Theme.alpha(Theme.fg, 0.06)
            border.width: 1
            border.color: Theme.alpha(Theme.overlay, 0.6)

            readonly property real memFrac: vm.ram > 0 ? Math.min(1, vm.rss / vm.ram) : 0
            readonly property real cpuFrac: vm.cpu >= 0 && vm.cores > 0 ? Math.min(1, vm.cpu / 100 / vm.cores) : 0

            RowLayout {
                id: body
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                spacing: 12

                // preview: QEMU's monitor screendump (`vm-ctl shot`), nothing else is ever captured. Live = captured in the last few seconds;
                // otherwise the last good frame (kept on disk, dropped when the VM restarts) is shown dimmed with its age and the reason.
                Rectangle {
                    id: pv
                    readonly property var info: VmService.shotInfo[card.vm.name] || null
                    readonly property real capAt: VmService.shotAt(card.vm.name)
                    readonly property bool have: capAt > 0
                    readonly property real age: have ? Math.max(0, vp.nowMs - capAt) : 0
                    readonly property bool live: have && info !== null && info.ok && age < 9000
                    readonly property bool stale: have && !live && info !== null      // (before the first attempt of this open nothing is claimed)
                    Layout.preferredWidth: 150; Layout.preferredHeight: 94
                    Layout.alignment: Qt.AlignTop
                    radius: Math.max(2, Theme.radiusItem - 6)
                    color: Theme.alpha(Theme.bg, 0.8)
                    clip: true
                    border.width: 1; border.color: Theme.alpha(Theme.overlay, 0.5)
                    Image {
                        id: shot
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false
                        sourceSize.width: 300
                        source: pv.have ? VmService.previewUrl(card.vm.name) : ""
                        visible: status === Image.Ready
                        opacity: pv.live || (pv.info === null && pv.age < 9000) ? 1 : 0.4
                    }
                    Label {
                        visible: !shot.visible
                        anchors.centerIn: parent
                        text: "\uf108"; font.family: Theme.iconFont; font.styleName: "Regular"
                        font.pixelSize: 26; color: Theme.muted
                    }
                    Rectangle {                          // keeps the note readable over a frame
                        visible: note.visible && shot.visible
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: note.implicitHeight + 10
                        color: Theme.alpha(Theme.bg, 0.8)
                    }
                    Label {
                        id: note
                        readonly property string reason: VmService.shotReason(card.vm.name)
                        visible: text !== ""
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 5 }
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                        font.pixelSize: Theme.fontCaption
                        color: pv.stale ? Theme.orange : Theme.muted
                        text: pv.info === null ? (pv.have ? "from " + VmService.fmtDuration(pv.age / 1000) + " ago" : "capturing...")
                            : pv.live ? (pv.info.same >= 10 ? "unchanged for " + VmService.fmtDuration(pv.info.same * 3) : "")
                            : (pv.have ? "from " + VmService.fmtDuration(pv.age / 1000) + " ago" + (reason ? "\n" : "") : "") + reason
                    }
                }

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
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Label { text: "CPU"; color: Theme.fgDim; font.pixelSize: Theme.fontCaption; Layout.preferredWidth: 28 }
                        Meter { Layout.fillWidth: true; value: card.cpuFrac; animMs: 300; implicitHeight: 4 }
                        Label {
                            text: card.vm.cpu >= 0 ? Math.round(card.vm.cpu) + "%" : "…"
                            font.pixelSize: Theme.fontCaption; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 36
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Label { text: "RAM"; color: Theme.fgDim; font.pixelSize: Theme.fontCaption; Layout.preferredWidth: 28 }
                        Meter { Layout.fillWidth: true; value: card.memFrac; animMs: 300; implicitHeight: 4; fillColor: Theme.accent2 }
                        Label {
                            text: VmService.fmtBytes(card.vm.rss) + (card.vm.ram > 0 ? " / " + VmService.fmtBytes(card.vm.ram) : "")
                            font.pixelSize: Theme.fontCaption; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 96
                        }
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
