pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings > Look & feel > Motion > Customise…: the bar popups (speed, curve, style, launcher; PopupHost via the
// Theme.popup* tokens) and Hyprland (on/off, speed, curve for every animation, plus per-category on/off, speed and
// curve). Writes only through the Motion singleton (animations.json overrides, debounced save; Hyprland is poked with
// anim_apply() from hypr/hyprland/managed.lua). Everything applies live. Every row ends in the same two columns as the
// other folds (GlassOptRow / PrefSlider): the value and a reset glyph, lit while the key is set. A change here turns the
// Motion choice above into Custom.
ColumnLayout {
    id: ma
    // true for a moment after every slider move: Settings.qml stops the page Flickable from stealing the drag
    readonly property bool dragging: dragHold.running
    Timer { id: dragHold; interval: 300 }
    property real titleW: 120
    readonly property int valueW: 62        // the value column of every slider row (PrefSlider.valueWidth)
    spacing: 12

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
    // "Config" = each animation keeps its own curve from animations.lua
    readonly property var hyprCurveLabels: ["Config", "Smooth", "Snappy", "Overshoot", "Linear", "Spring"]
    function hyprCurveLabel(id) { const i = Motion.hyprCurves.indexOf(id); return i < 0 ? "Global" : ma.hyprCurveLabels[i] }

    // the reset glyph at the end of a row (GlassOptRow's): lit while any of `keys` is set
    component KeysReset: ResetBtn {
        property var keys: []
        readonly property bool own: { void Motion.data; return keys.some(k => Motion.overridden(k)) }
        set: own
        onClicked: if (own) keys.forEach(k => Motion.unset(k))
    }
    component ValueLabel: Label {
        Layout.preferredWidth: ma.valueW
        horizontalAlignment: Text.AlignRight
        color: Theme.fg
        font.pixelSize: Theme.fontSmall
    }

    // ---------------------------------------------------------------- bar popups
    SectionHead { title: "Shell"; detail: Theme.popupOpenMs + " ms"; InfoTip { text: "Popups, launcher and every shell transition. 1× = " + Motion.baseMs + " ms." } }
    SettingRow {
        title: "Speed"
        titleWidth: ma.titleW
        Slider {
            wheel: false
            objectName: "slider-popupSpeed"
            Layout.fillWidth: true
            mark: ma.oneX
            value: ma.toNorm(Motion.popupSpeed)
            onMoved: v => ma.slide("popupSpeed", v)
        }
        ValueLabel { text: ma.fmtSpeed(Motion.popupSpeed) }
        KeysReset { objectName: "reset-popupSpeed"; keys: ["popupSpeed"] }
    }
    SettingRow {
        id: popupCurveRow
        title: "Curve"
        titleWidth: ma.titleW
        Segmented {
            id: popupCurveSeg
            // shrinks on a narrow page: never wider than the row leaves (the buttons then split that width)
            readonly property real natural: naturals.reduce((a, b) => a + b, 0) + spacing * (naturals.length - 1)
            Layout.fillWidth: true; Layout.preferredWidth: natural; Layout.maximumWidth: natural
            fillWidth: width
            values: Motion.popupCurves
            labels: ma.popupCurveLabels
            objectNames: Motion.popupCurves.map(v => "btn-popupCurve-" + v)
            current: Motion.popupCurve
            outerRadius: Theme.radiusPage; inset: 9; segHeight: 24
            onPicked: v => Motion.set("popupCurve", v)
        }
        KeysReset { objectName: "reset-popupCurve"; keys: ["popupCurve"] }
    }
    SettingRow {
        title: "Style"
        titleWidth: ma.titleW
        Segmented {
            values: Motion.popupStyles
            labels: ma.popupStyleLabels
            objectNames: Motion.popupStyles.map(v => "btn-popupStyle-" + v)
            current: Motion.popupStyle
            outerRadius: Theme.radiusPage; inset: 9; segHeight: 24
            onPicked: v => Motion.set("popupStyle", v)
        }
        Item { Layout.fillWidth: true }
        KeysReset { objectName: "reset-popupStyle"; keys: ["popupStyle"] }
    }
    SettingRow {
        title: "Launcher"
        titleWidth: ma.titleW
        Segmented {
            values: [false, true]
            labels: ["Hyprland only", "Like popups"]
            objectNames: ["btn-launcher-off", "btn-launcher-on"]
            current: Motion.launcherMotion
            outerRadius: Theme.radiusPage; inset: 9; segHeight: 24
            onPicked: v => v ? Motion.set("launcherMotion", true) : Motion.unset("launcherMotion")
        }
        Item { Layout.fillWidth: true }
        KeysReset { objectName: "reset-launcherMotion"; keys: ["launcherMotion"] }
    }

    // ---------------------------------------------------------------- Hyprland
    SectionHead {
        title: "Hyprland"
        Layout.topMargin: 6
        detail: Motion.value("hyprEnabled") ? Math.round(Motion.baseMs / Motion.value("hyprSpeed")) + " ms" : "off"
        InfoTip { text: "Windows, workspaces, fades: scales the curves and speeds of hypr/hyprland/animations.lua (Config keeps each one's own curve; Spring is time-scaled). Saved in animations.json." }
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
        opacity: enabled ? 1 : Theme.disabledOpacity

        SettingRow {
            title: "Speed"
            titleWidth: ma.titleW
            Slider {
                wheel: false
                objectName: "slider-hyprSpeed"
                Layout.fillWidth: true
                mark: ma.oneX
                value: ma.toNorm(Motion.value("hyprSpeed"))
                onMoved: v => ma.slide("hyprSpeed", v)
            }
            ValueLabel { text: ma.fmtSpeed(Motion.value("hyprSpeed")) }
            KeysReset { objectName: "reset-hyprSpeed"; keys: ["hyprSpeed"] }
        }
        SettingRow {
            id: hyprCurveRow
            title: "Curve"
            titleWidth: ma.titleW
            Segmented {
                id: hyprCurveSeg
                readonly property real natural: naturals.reduce((a, b) => a + b, 0) + spacing * (naturals.length - 1)
                Layout.fillWidth: true; Layout.preferredWidth: natural; Layout.maximumWidth: natural
                fillWidth: width
                values: Motion.hyprCurves
                labels: ma.hyprCurveLabels
                objectNames: Motion.hyprCurves.map(v => "btn-hyprCurve-" + v)
                current: Motion.value("hyprCurve")
                outerRadius: Theme.radiusPage; inset: 9; segHeight: 24
                onPicked: v => v === "config" ? Motion.unset("hyprCurve") : Motion.set("hyprCurve", v)
            }
            KeysReset { objectName: "reset-hyprCurve"; keys: ["hyprCurve"] }
        }

        SectionHead { title: "Per category"; Layout.topMargin: 6; InfoTip { text: "Speed × the Hyprland speed above. Click a curve button to cycle, right-click to go back." } }
        // one row per category: on/off | curve | speed | value | reset
        Repeater {
            model: Motion.groups
            delegate: SettingRow {
                id: catRow
                required property var modelData
                readonly property string gid: modelData.id
                readonly property bool on: Motion.value(gid + "Enabled")
                title: modelData.label
                titleWidth: ma.titleW
                Toggle {
                    objectName: "toggle-" + catRow.gid + "Enabled"
                    checked: catRow.on
                    onToggled: want => want ? Motion.unset(catRow.gid + "Enabled") : Motion.set(catRow.gid + "Enabled", false)
                }
                // curve: "" = follows the global curve; click cycles forward, right-click back
                Btn {
                    objectName: "btn-" + catRow.gid + "Curve"
                    readonly property string cur: Motion.value(catRow.gid + "Curve")
                    text: ma.hyprCurveLabel(cur)
                    active: cur !== ""
                    implicitHeight: 24; implicitWidth: 96
                    outerRadius: Theme.radiusPage; inset: 9
                    enabledLook: catRow.on
                    onClicked: mouse => {
                        const list = [""].concat(Motion.hyprCurves)
                        const step = mouse.button === Qt.RightButton ? list.length - 1 : 1
                        const next = list[(list.indexOf(cur) + step) % list.length]
                        next === "" ? Motion.unset(catRow.gid + "Curve") : Motion.set(catRow.gid + "Curve", next)
                    }
                }
                Slider {
                    wheel: false
                    objectName: "slider-" + catRow.gid + "Speed"
                    Layout.fillWidth: true
                    dim: !catRow.on
                    mark: ma.oneX
                    value: ma.toNorm(Motion.value(catRow.gid + "Speed"))
                    onMoved: v => ma.slide(catRow.gid + "Speed", v)
                }
                ValueLabel { text: ma.fmtSpeed(Motion.value(catRow.gid + "Speed")); opacity: catRow.on ? 1 : Theme.disabledOpacity }
                KeysReset { objectName: "reset-" + catRow.gid; keys: [catRow.gid + "Enabled", catRow.gid + "Speed", catRow.gid + "Curve"] }
            }
        }
    }
}
