import QtQuick
import QtQuick.Layouts

// Settings -> Animations: bar popups (speed, curve, style; PopupHost via the Theme.popup* tokens) and Hyprland
// (on/off, speed, curve for every animation, plus per-category on/off, speed and curve).
// Writes only through the Motion singleton (animations.json overrides, debounced save; Hyprland is poked with
// anim_apply() from hypr/hyprland/managed.lua). Everything applies live; "(default)" = key not set.
Item {
    id: pg
    implicitHeight: col.implicitHeight

    // true for a moment after every slider move: Settings.qml stops the page Flickable from stealing the drag
    readonly property bool dragging: dragHold.running
    Timer { id: dragHold; interval: 300 }

    readonly property int titleW: 120
    readonly property int valueW: 52
    readonly property int noteW: 64

    // EVERY speed slider (popups, Hyprland, categories): log scale over Motion.speedRange (0.25 .. 10), so the same
    // position is the same multiplier everywhere and 1x sits at ~38 % (tick mark); snaps to 1x within 1.5 % of the
    // track; steps 0.05 below 2x, 0.1 below 5x, 0.25 above
    function toNorm(v) { const r = Motion.speedRange; return Math.log(v / r[0]) / Math.log(r[1] / r[0]) }
    readonly property real oneX: toNorm(1)
    function fromNorm(n) {
        if (Math.abs(n - oneX) < 0.015) return 1
        const r = Motion.speedRange
        const v = r[0] * Math.pow(r[1] / r[0], n)
        const step = v < 2 ? 0.05 : v < 5 ? 0.1 : 0.25
        return Math.max(r[0], Math.min(r[1], Math.round(v / step) * step))
    }
    function slide(key, n) { dragHold.restart(); Motion.set(key, fromNorm(n)) }
    function fmtSpeed(v) { return v.toFixed(2) + "×" }

    readonly property var popupCurveLabels: ["Cubic", "Quint", "Expo", "Back", "Linear"]
    readonly property var popupStyleLabels: ["Scale", "Slide", "Fade", "None"]
    readonly property var hyprCurveLabels: ["As configured", "Smooth", "Snappy", "Overshoot", "Linear", "Spring"]
    function hyprCurveLabel(id) { const i = Motion.hyprCurves.indexOf(id); return i < 0 ? "Global" : pg.hyprCurveLabels[i] }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 12

        // ---------------------------------------------------------------- bar popups
        SectionHead { title: "Bar popups"; detail: "1× = " + Motion.baseMs + " ms · now " + Theme.popupOpenMs + " ms" }
        SettingRow {
            title: "Speed"
            titleWidth: pg.titleW
            Slider {
                objectName: "slider-popupSpeed"
                Layout.fillWidth: true
                mark: pg.oneX
                value: pg.toNorm(Motion.popupSpeed)
                onMoved: v => pg.slide("popupSpeed", v)
            }
            Label { text: pg.fmtSpeed(Motion.popupSpeed); Layout.preferredWidth: pg.valueW; horizontalAlignment: Text.AlignRight; color: Theme.fg; font.pixelSize: Theme.fontSmall }
            Label { text: Motion.overridden("popupSpeed") ? "" : "(default)"; Layout.preferredWidth: pg.noteW; color: Theme.muted; font.pixelSize: Theme.fontCaption }
        }
        SettingRow {
            title: "Curve"
            titleWidth: pg.titleW
            Segmented {
                values: Motion.popupCurves
                labels: pg.popupCurveLabels
                objectNames: Motion.popupCurves.map(v => "btn-popupCurve-" + v)
                current: Motion.popupCurve
                inset: 18; segHeight: 24
                onPicked: v => Motion.set("popupCurve", v)
            }
            Item { Layout.fillWidth: true }
            Label { text: Motion.overridden("popupCurve") ? "" : "(default)"; Layout.preferredWidth: pg.noteW; color: Theme.muted; font.pixelSize: Theme.fontCaption }
        }
        SettingRow {
            title: "Style"
            titleWidth: pg.titleW
            Segmented {
                values: Motion.popupStyles
                labels: pg.popupStyleLabels
                objectNames: Motion.popupStyles.map(v => "btn-popupStyle-" + v)
                current: Motion.popupStyle
                inset: 18; segHeight: 24
                onPicked: v => Motion.set("popupStyle", v)
            }
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                color: Theme.muted; font.pixelSize: Theme.fontCaption
                text: ({ scale: "fade + grow from the chip", slide: "fade + slide from the bar", fade: "fade only", none: "no animation" })[Motion.popupStyle] || ""
            }
            Label { text: Motion.overridden("popupStyle") ? "" : "(default)"; Layout.preferredWidth: pg.noteW; color: Theme.muted; font.pixelSize: Theme.fontCaption }
        }

        SettingRow {
            title: "Launcher"
            titleWidth: pg.titleW
            Segmented {
                values: [false, true]
                labels: ["Hyprland only", "Like popups"]
                objectNames: ["btn-launcher-off", "btn-launcher-on"]
                current: Motion.launcherMotion
                inset: 18; segHeight: 24
                onPicked: v => v ? Motion.set("launcherMotion", true) : Motion.unset("launcherMotion")
            }
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                color: Theme.muted; font.pixelSize: Theme.fontCaption
                text: Motion.launcherMotion ? "card uses the speed, curve and style above" : "only Hyprland's layer fade, as before"
            }
            Label { text: Motion.overridden("launcherMotion") ? "" : "(default)"; Layout.preferredWidth: pg.noteW; color: Theme.muted; font.pixelSize: Theme.fontCaption }
        }

        // preview: a mock bar + card that replays close -> open with the same tokens as PopupHost
        SettingRow {
            title: "Preview"
            titleWidth: pg.titleW
            Rectangle {
                id: demo
                Layout.preferredWidth: 260
                Layout.preferredHeight: 110
                radius: Theme.radiusItem
                color: Theme.alpha(Theme.fg, 0.04)
                border.width: 1
                border.color: Theme.alpha(Theme.overlay, 0.5)
                clip: true
                property real t: 1
                Rectangle {
                    id: demoBar
                    x: 8; y: 8; width: parent.width - 16; height: 18
                    radius: Theme.radiusChip
                    color: Theme.surface2
                    Rectangle { id: demoChip; x: 150; y: 3; width: 40; height: 12; radius: Math.min(4, Theme.radiusChip); color: Theme.alpha(Theme.accent, demo.t > 0.5 ? 0.5 : 0.2) }
                }
                Rectangle {
                    id: demoCard
                    width: 130; height: 66
                    x: demoBar.x + demoChip.x + demoChip.width / 2 - width / 2
                    y: demoBar.y + demoBar.height + 6
                    radius: Theme.radiusItem
                    color: Theme.alpha(Theme.bg, 0.95)
                    border.width: 1
                    border.color: Theme.alpha(Theme.overlay, 0.6)
                    opacity: demo.t
                    transform: [
                        Scale {
                            origin.x: demoCard.width / 2; origin.y: 0
                            xScale: Theme.popupScaleFrom + (1 - Theme.popupScaleFrom) * demo.t
                            yScale: Theme.popupScaleFrom + (1 - Theme.popupScaleFrom) * demo.t
                        },
                        Translate { y: -(1 - demo.t) * Theme.popupSlidePx }
                    ]
                    Column {
                        x: 10; y: 10; spacing: 8
                        Repeater {
                            model: [0.7, 0.5, 0.85]
                            Rectangle { required property real modelData; width: 110 * modelData; height: 8; radius: 4; color: Theme.alpha(Theme.fg, 0.18) }
                        }
                    }
                }
                SequentialAnimation {
                    id: replay
                    NumberAnimation { target: demo; property: "t"; to: 0; duration: Theme.popupCloseMs; easing.type: Theme.popupEaseClose }
                    PauseAnimation { duration: 260 }
                    NumberAnimation { target: demo; property: "t"; to: 1; duration: Theme.popupOpenMs; easing.type: Theme.popupEaseOpen }
                }
                MouseArea { anchors.fill: parent; onClicked: replay.restart() }
            }
            Label { Layout.fillWidth: true; text: "click to replay"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
        }
        Connections {
            target: Motion
            function onPopupSpeedChanged() { replayLater.restart() }
            function onPopupCurveChanged() { replayLater.restart() }
            function onPopupStyleChanged() { replayLater.restart() }
        }
        Timer { id: replayLater; interval: 350; onTriggered: replay.restart() }

        // ---------------------------------------------------------------- Hyprland
        SectionHead {
            title: "Hyprland"
            Layout.topMargin: 6
            detail: Motion.value("hyprEnabled") ? "1× = " + Motion.baseMs + " ms (same base) · now " + Math.round(Motion.baseMs / Motion.value("hyprSpeed")) + " ms" : "animations off"
            Toggle {
                objectName: "toggle-hyprEnabled"
                checked: Motion.value("hyprEnabled")
                onToggled: want => want ? Motion.unset("hyprEnabled") : Motion.set("hyprEnabled", false)
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            enabled: Motion.value("hyprEnabled")
            opacity: enabled ? 1 : 0.45

            SettingRow {
                title: "Speed"
                titleWidth: pg.titleW
                Slider {
                    objectName: "slider-hyprSpeed"
                    Layout.fillWidth: true
                    mark: pg.oneX
                value: pg.toNorm(Motion.value("hyprSpeed"))
                    onMoved: v => pg.slide("hyprSpeed", v)
                }
                Label { text: pg.fmtSpeed(Motion.value("hyprSpeed")); Layout.preferredWidth: pg.valueW; horizontalAlignment: Text.AlignRight; color: Theme.fg; font.pixelSize: Theme.fontSmall }
                Label { text: Motion.overridden("hyprSpeed") ? "" : "(default)"; Layout.preferredWidth: pg.noteW; color: Theme.muted; font.pixelSize: Theme.fontCaption }
            }
            SettingRow {
                title: "Curve"
                titleWidth: pg.titleW
                Segmented {
                    values: Motion.hyprCurves
                    labels: pg.hyprCurveLabels
                    objectNames: Motion.hyprCurves.map(v => "btn-hyprCurve-" + v)
                    current: Motion.value("hyprCurve")
                    inset: 18; segHeight: 24
                    onPicked: v => v === "config" ? Motion.unset("hyprCurve") : Motion.set("hyprCurve", v)
                }
                Item { Layout.fillWidth: true }
                Label { text: Motion.overridden("hyprCurve") ? "" : "(default)"; Layout.preferredWidth: pg.noteW; color: Theme.muted; font.pixelSize: Theme.fontCaption }
            }

            SectionHead { title: "Per category"; detail: "speed × the one above · click the curve to cycle, right-click back"; Layout.topMargin: 6 }
            Repeater {
                model: Motion.groups
                delegate: SettingRow {
                    id: grow
                    required property var modelData
                    readonly property string gid: modelData.id
                    readonly property bool on: Motion.value(gid + "Enabled")
                    readonly property bool own: Motion.overridden(gid + "Enabled") || Motion.overridden(gid + "Speed") || Motion.overridden(gid + "Curve")
                    title: modelData.label
                    titleWidth: pg.titleW
                    Toggle {
                        objectName: "toggle-" + grow.gid + "Enabled"
                        checked: grow.on
                        onToggled: want => want ? Motion.unset(grow.gid + "Enabled") : Motion.set(grow.gid + "Enabled", false)
                    }
                    Slider {
                        objectName: "slider-" + grow.gid + "Speed"
                        Layout.fillWidth: true
                        dim: !grow.on
                        mark: pg.oneX
                value: pg.toNorm(Motion.value(grow.gid + "Speed"))
                        onMoved: v => pg.slide(grow.gid + "Speed", v)
                    }
                    Label { text: pg.fmtSpeed(Motion.value(grow.gid + "Speed")); Layout.preferredWidth: pg.valueW; horizontalAlignment: Text.AlignRight; color: Theme.fg; font.pixelSize: Theme.fontSmall }
                    // curve: "" = follows the global curve; click cycles forward, right-click back
                    Btn {
                        objectName: "btn-" + grow.gid + "Curve"
                        readonly property string cur: Motion.value(grow.gid + "Curve")
                        text: pg.hyprCurveLabel(cur)
                        active: cur !== ""
                        implicitHeight: 24; implicitWidth: 104
                        inset: 18
                        onClicked: mouse => {
                            const list = [""].concat(Motion.hyprCurves)
                            const step = mouse.button === Qt.RightButton ? list.length - 1 : 1
                            const next = list[(list.indexOf(cur) + step) % list.length]
                            next === "" ? Motion.unset(grow.gid + "Curve") : Motion.set(grow.gid + "Curve", next)
                        }
                    }
                    Btn {
                        objectName: "reset-" + grow.gid
                        icon: true; text: ""
                        implicitHeight: 20; implicitWidth: 24
                        outerRadius: Theme.radius; inset: 12
                        enabledLook: grow.own
                        onClicked: { Motion.unset(grow.gid + "Enabled"); Motion.unset(grow.gid + "Speed"); Motion.unset(grow.gid + "Curve") }
                    }
                }
            }
        }

        // ---------------------------------------------------------------- reset + footnote
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 8
            Btn { objectName: "btn-reset-popup"; text: "Reset popups"; inset: 18; implicitHeight: 26; enabledLook: Motion.anyOverridden("popup"); onClicked: Motion.reset("popup") }
            Btn { objectName: "btn-reset-hypr"; text: "Reset Hyprland"; inset: 18; implicitHeight: 26; enabledLook: Motion.anyOverridden("hypr"); onClicked: Motion.reset("hypr") }
            Item { Layout.fillWidth: true }
        }
        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Theme.muted
            font.pixelSize: Theme.fontCaption
            text: "Applies immediately. Saved in animations.json; Hyprland scales the hand-written curves and speeds of hypr/hyprland/animations.lua (\"As configured\" keeps each one's own curve; Spring is time-scaled by the speed)."
        }
    }
}
