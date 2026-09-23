import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire

ShellRoot {
    id: root

    // "DP-5" (Dell U2515H) / "Virtual-1" get the bottom bar, "HDMI-A-1" gets the top
    // bar -- mirrors the two blocks in the waybar config this replaces. Quickshell's
    // screen.name is the short connector name, not the EDID description waybar's
    // "output" field matched on ("Dell Inc. DELL U2515H 9X2VY5AK1D5L") -- confirmed
    // via hyprctl monitors that this monitor's connector is DP-5 on this machine. If
    // you move it to a different port, update this list.
    readonly property var targetOutputs: ["DP-5", "Virtual-1", "HDMI-A-1"]

    readonly property color textLight: "#e6ffffff"
    readonly property color accent: "#a6e3a1" // theme.colors.green (M.selected)
    readonly property int pillHeight: 30
    readonly property int gap: 8

    property string cpuText: "0%"
    property string memText: "0%"
    property string notifIconKey: "none"

    readonly property var notifIcons: ({
        "notification": "",
        "none": "",
        "dnd-notification": "",
        "dnd-none": "",
        "inhibited-notification": "",
        "inhibited-none": "",
        "dnd-inhibited-notification": "",
        "dnd-inhibited-none": "",
    })

    function wsLabel(id) {
        const labels = {
            1: "ち", 2: "と", 3: "し", 4: "は", 5: "た", 6: "て",
            7: "い", 8: "す", 9: "つ", 10: "さ", 11: "そ", 12: "ひ",
        }
        return labels[id] || String(id)
    }

    function runDetached(cmd) {
        actionProc.command = ["sh", "-lc", cmd]
        actionProc.startDetached()
    }

    Process { id: actionProc }

    // cpu% -- reused as-is from the previous single-surface experiment, it's a solid
    // dependency-free /proc/stat delta calculation
    Process {
        running: true
        command: ["sh", "-lc", "while :; do awk '/^cpu /{u=$2+$4;t=$2+$4+$5;if(pt>0)printf \"%d%%\\n\",(u-pu)*100/(t-pt);pu=u;pt=t;fflush();}' /proc/stat; sleep 2; done"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => { if (line) root.cpuText = line }
        }
    }

    Process {
        running: true
        command: ["sh", "-lc", "while :; do awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf \"%d%%\\n\",(t-a)*100/t}' /proc/meminfo; sleep 3; done"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => { if (line) root.memText = line }
        }
    }

    // swaync-client -swb prints one JSON line like {"text":"notification", ...} where
    // "text" is a key into the SAME format-icons map waybar's custom/notification uses
    Process {
        running: true
        command: ["sh", "-lc", "while :; do swaync-client -swb 2>/dev/null; sleep 2; done"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (!line)
                    return
                try {
                    const obj = JSON.parse(line)
                    if (obj.text)
                        root.notifIconKey = obj.text
                } catch (e) {}
            }
        }
    }

    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
    }

    Variants {
        model: Quickshell.screens.filter(s => root.targetOutputs.includes(s.name))

        Item {
            id: barSet
            required property var modelData
            readonly property var scr: modelData
            readonly property bool isTop: scr.name === "HDMI-A-1"

            // ---- Workspaces (left) ----
            // This pill alone carries the exclusive zone for the whole bar row.
            // exclusionMode must be set to Normal explicitly -- the default silently
            // ignores a manually-set exclusiveZone value.
            Pill {
                id: wsPill
                screen: barSet.scr
                WlrLayershell.namespace: "qs-workspaces"
                WlrLayershell.layer: WlrLayer.Top
                exclusionMode: ExclusionMode.Normal
                exclusiveZone: root.gap + root.pillHeight
                implicitHeight: root.pillHeight
                implicitWidth: Math.max(wsRow.implicitWidth + root.gap * 2, root.pillHeight)
                anchors { left: true; top: barSet.isTop; bottom: !barSet.isTop }
                margins { left: root.gap; top: root.gap; bottom: root.gap }

                Row {
                    id: wsRow
                    anchors.centerIn: parent
                    spacing: 4

                    Repeater {
                        model: Hyprland.workspaces

                        Rectangle {
                            required property var modelData
                            readonly property bool active: modelData.active || modelData.focused
                            visible: modelData.id > 0
                            implicitWidth: active ? 36 : 26
                            implicitHeight: 26
                            radius: 13
                            color: active ? root.accent : "#33ffffff"

                            Text {
                                anchors.centerIn: parent
                                text: root.wsLabel(parent.modelData.id)
                                color: parent.active ? "#191724" : root.textLight
                                font.family: "TX-02"
                                font.bold: true
                                font.pixelSize: 12
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: parent.modelData.activate()
                            }
                        }
                    }
                }
            }

            // ---- Clock (rightmost) ----
            Pill {
                id: clockPill
                screen: barSet.scr
                WlrLayershell.namespace: "qs-clock"
                WlrLayershell.layer: WlrLayer.Top
                exclusionMode: ExclusionMode.Ignore
                implicitHeight: root.pillHeight
                implicitWidth: Math.max(clockText.implicitWidth + root.gap * 2, root.pillHeight)
                anchors { right: true; top: barSet.isTop; bottom: !barSet.isTop }
                margins { right: root.gap; top: root.gap; bottom: root.gap }

                Text {
                    id: clockText
                    anchors.centerIn: parent
                    text: Qt.formatDateTime(sysClock.date, "yyyy-MM-dd HH:mm")
                    color: root.textLight
                    font.family: "TX-02"
                    font.bold: true
                    font.pixelSize: 13
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.runDetached("thunderbird --calendar")
                }
            }

            // ---- Tray ----
            Pill {
                id: trayPill
                screen: barSet.scr
                WlrLayershell.namespace: "qs-tray"
                WlrLayershell.layer: WlrLayer.Top
                exclusionMode: ExclusionMode.Ignore
                implicitHeight: root.pillHeight
                implicitWidth: Math.max(trayRow.implicitWidth + root.gap * 2, root.pillHeight)
                anchors { right: true; top: barSet.isTop; bottom: !barSet.isTop }
                margins {
                    right: root.gap * 2 + clockPill.implicitWidth
                    top: root.gap
                    bottom: root.gap
                }

                Row {
                    id: trayRow
                    anchors.centerIn: parent
                    spacing: 8

                    Repeater {
                        model: SystemTray.items

                        Item {
                            required property var modelData
                            implicitWidth: 18
                            implicitHeight: 18

                            IconImage {
                                anchors.fill: parent
                                source: parent.modelData.icon
                                implicitSize: 18
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.LeftButton)
                                        parent.modelData.activate()
                                    else
                                        parent.modelData.secondaryActivate()
                                }
                            }
                        }
                    }
                }
            }

            // ---- Audio (pulseaudio + volume) ----
            Pill {
                id: audioPill
                screen: barSet.scr
                WlrLayershell.namespace: "qs-audio"
                WlrLayershell.layer: WlrLayer.Top
                exclusionMode: ExclusionMode.Ignore
                implicitHeight: root.pillHeight
                implicitWidth: Math.max(audioRow.implicitWidth + root.gap * 2, root.pillHeight)
                anchors { right: true; top: barSet.isTop; bottom: !barSet.isTop }
                margins {
                    right: root.gap * 3 + clockPill.implicitWidth + trayPill.implicitWidth
                    top: root.gap
                    bottom: root.gap
                }

                PwObjectTracker {
                    objects: [Pipewire.defaultAudioSink]
                }

                Row {
                    id: audioRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        id: muteIcon
                        text: {
                            const sink = Pipewire.defaultAudioSink
                            if (!sink || !sink.audio)
                                return ""
                            return sink.audio.muted ? "" : ""
                        }
                        color: root.textLight
                        font.family: "TX-02"
                        font.pixelSize: 13

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.runDetached("pavucontrol")
                        }
                    }

                    Slider {
                        id: volSlider
                        implicitWidth: 70
                        implicitHeight: root.pillHeight
                        from: 0
                        to: 1
                        value: {
                            const sink = Pipewire.defaultAudioSink
                            return (sink && sink.audio) ? sink.audio.volume : 0
                        }
                        onMoved: {
                            const sink = Pipewire.defaultAudioSink
                            if (sink && sink.audio)
                                sink.audio.volume = value
                        }

                        background: Rectangle {
                            x: volSlider.leftPadding
                            y: volSlider.topPadding + volSlider.availableHeight / 2 - height / 2
                            width: volSlider.availableWidth
                            height: 4
                            radius: 2
                            color: "#33ffffff"

                            Rectangle {
                                width: volSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 2
                                color: root.accent
                            }
                        }

                        handle: Rectangle {
                            x: volSlider.leftPadding + volSlider.visualPosition * (volSlider.availableWidth - width)
                            y: volSlider.topPadding + volSlider.availableHeight / 2 - height / 2
                            width: 12
                            height: 12
                            radius: 6
                            color: root.textLight
                        }
                    }

                    Text {
                        text: {
                            const sink = Pipewire.defaultAudioSink
                            if (!sink || !sink.audio)
                                return "--%"
                            return Math.round((sink.audio.volume || 0) * 100) + "%"
                        }
                        color: root.textLight
                        font.family: "TX-02"
                        font.pixelSize: 12
                    }
                }
            }

            // ---- CPU + memory cluster ----
            Pill {
                id: sysPill
                screen: barSet.scr
                WlrLayershell.namespace: "qs-system"
                WlrLayershell.layer: WlrLayer.Top
                exclusionMode: ExclusionMode.Ignore
                implicitHeight: root.pillHeight
                implicitWidth: Math.max(sysRow.implicitWidth + root.gap * 2, root.pillHeight)
                anchors { right: true; top: barSet.isTop; bottom: !barSet.isTop }
                margins {
                    right: root.gap * 4 + clockPill.implicitWidth + trayPill.implicitWidth + audioPill.implicitWidth
                    top: root.gap
                    bottom: root.gap
                }

                Row {
                    id: sysRow
                    anchors.centerIn: parent
                    spacing: 10

                    Text {
                        text: " " + root.cpuText
                        color: root.textLight
                        font.family: "TX-02"
                        font.pixelSize: 12
                    }
                    Text {
                        text: " " + root.memText
                        color: root.textLight
                        font.family: "TX-02"
                        font.pixelSize: 12
                    }
                }
            }

            // ---- Idle inhibitor + notification cluster ----
            Pill {
                id: idlePill
                screen: barSet.scr
                WlrLayershell.namespace: "qs-idle-notif"
                WlrLayershell.layer: WlrLayer.Top
                exclusionMode: ExclusionMode.Ignore
                implicitHeight: root.pillHeight
                implicitWidth: Math.max(idleRow.implicitWidth + root.gap * 2, root.pillHeight)
                anchors { right: true; top: barSet.isTop; bottom: !barSet.isTop }
                margins {
                    right: root.gap * 5 + clockPill.implicitWidth + trayPill.implicitWidth + audioPill.implicitWidth + sysPill.implicitWidth
                    top: root.gap
                    bottom: root.gap
                }

                IdleInhibitor {
                    id: inhibitor
                    window: idlePill
                    enabled: false
                }

                Row {
                    id: idleRow
                    anchors.centerIn: parent
                    spacing: 10

                    Text {
                        text: inhibitor.enabled ? "" : ""
                        color: inhibitor.enabled ? root.accent : root.textLight
                        font.family: "TX-02"
                        font.pixelSize: 14

                        MouseArea {
                            anchors.fill: parent
                            onClicked: inhibitor.enabled = !inhibitor.enabled
                        }
                    }

                    Text {
                        text: root.notifIcons[root.notifIconKey] || root.notifIcons["none"]
                        color: root.textLight
                        font.family: "TX-02"
                        font.pixelSize: 14

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.LeftButton)
                                    root.runDetached("swaync-client -t -sw")
                                else
                                    root.runDetached("swaync-client -d -sw")
                            }
                        }
                    }
                }
            }
        }
    }
}
