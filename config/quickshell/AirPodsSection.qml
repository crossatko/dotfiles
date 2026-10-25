pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "launcher/js/AirPods.js" as Pods

// AirPods section of the Bluetooth popup (top, above the device list), shown while the AirPods are connected (state
// and controls: AirPods singleton). Order: the model name (AirPods.title) as a PanelHeader; battery rings (left /
// right / case, BudRing + PodIcon; the case level is fetched on demand while the section is on screen and greyed
// with its age when stale); a Conversation awareness section head with its Toggle (the only on/off feature);
// listening mode as captioned icon tiles (ModeTiles, only the modes the model reports) with the adaptive level
// slider while Adaptive is active; ear detection as a three-way choice (its behaviour is not an on/off, so no
// toggle). Without the daemon (`AirPods.daemon` false) the block is just the header and a setup notice, since there
// is no state to show or change.
ColumnLayout {
    id: ap
    spacing: 10

    readonly property bool live: AirPods.daemon && AirPods.connected

    // case level on demand: one refresh when the section comes on screen, then every 45 s while it stays there
    property real now: Date.now() / 1000
    Timer {
        running: ap.visible && ap.live && AirPods.canRefreshCase
        interval: 45000
        repeat: true
        triggeredOnStart: true
        onTriggered: AirPods.refreshCase()
    }
    Timer { running: ap.visible && ap.live; interval: 30000; repeat: true; triggeredOnStart: true; onTriggered: ap.now = Date.now() / 1000 }

    PanelHeader { title: AirPods.title }    // same title style as the popup's own ("Bluetooth" below)

    Notice {
        visible: !AirPods.daemon
        Label {
            Layout.fillWidth: true
            text: "AirPods controls need the librepods service"
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSmall
        }
        Label {
            Layout.fillWidth: true
            text: "systemctl --user enable --now librepods"
            color: Theme.fgDim
            font.family: "monospace"
            font.pixelSize: Theme.fontCaption
            wrapMode: Text.WrapAnywhere
        }
    }

    // battery: one ring per part, spread evenly over the row
    RowLayout {
        visible: ap.live
        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: 0
        Item { Layout.fillWidth: true }
        BudRing { visible: !AirPods.headset; part: "left"; name: "Left"; level: AirPods.left.level; charging: AirPods.left.charging; inEar: AirPods.left.inEar }
        Item { visible: !AirPods.headset; Layout.fillWidth: true }
        BudRing { visible: !AirPods.headset; part: "right"; name: "Right"; level: AirPods.right.level; charging: AirPods.right.charging; inEar: AirPods.right.inEar }
        Item { visible: !AirPods.headset; Layout.fillWidth: true }
        BudRing { visible: !AirPods.headset; part: "case"; name: "Case"; level: AirPods.box.level; charging: AirPods.box.charging; age: Pods.age(AirPods.caseSeenAt, ap.now) }
        BudRing { visible: AirPods.headset; part: "headset"; name: "Headset"; level: AirPods.max.level; charging: AirPods.max.charging }
        Item { Layout.fillWidth: true }
    }

    // the on/off feature as a section head with its toggle, under the rings (like Wireless / Tailscale in the
    // network popup)
    SectionHead {
        visible: ap.live && AirPods.canAware
        Layout.topMargin: 4          // 14 px above it in all, like the network popup's section heads
        title: "Conversation awareness"
        Toggle {
            checked: AirPods.aware
            onToggled: on => AirPods.setAware(on)
        }
    }

    // listening mode: captioned icon tiles (only the modes the model reports)
    Item {
        id: modeBox
        visible: ap.live && AirPods.modes.length > 0
        Layout.fillWidth: true
        implicitHeight: modeTiles.implicitHeight     // no implicit width: the tiles follow the box (no layout loop)
        ModeTiles {
            id: modeTiles
            model: AirPods.modes
            current: AirPods.mode
            fillWidth: modeBox.width
            onPicked: v => AirPods.setMode(v)
        }
    }

    // adaptive level: icon column like the volume rows above, so the sliders line up
    LevelRow {
        visible: ap.live && AirPods.mode === 3
        icon: "\ue75d"            // ear-waveform
        iconColor: Theme.fgDim
        value: AirPods.adaptive / 100
        valueText: AirPods.adaptive + "%"
        onMoved: v => AirPods.setAdaptive(v * 100)
    }

    // ear detection: what happens when a bud comes out (three behaviours, not an on/off)
    RowLayout {
        visible: ap.live
        Layout.fillWidth: true
        spacing: 10
        Label { text: "Auto-pause"; color: Theme.fgDim; font.pixelSize: Theme.fontSmall }
        Item {
            id: earBox
            Layout.fillWidth: true
            implicitHeight: earSeg.implicitHeight
            Segmented {
                id: earSeg
                values: AirPods.earOptions.map(e => e.value)
                labels: AirPods.earOptions.map(e => e.label)
                current: AirPods.ear
                fillWidth: earBox.width
                onPicked: v => AirPods.setEar(v)
            }
        }
    }

    Label {
        visible: AirPods.error !== ""
        Layout.fillWidth: true
        text: AirPods.error
        color: Theme.red
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontCaption
    }

}
