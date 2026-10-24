pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell

// Settings -> Appearance: corner radius, window gaps, window border, docked / floating bar and smart gaps
// (one switch for all monitors, plus one per monitor when there are several).
// Writes only through the Appearance singleton (appearance.json overrides, debounced save, then Hyprland is
// poked); shows the EFFECTIVE values from Theme (override, else the theme default). Everything in the shell
// and Hyprland follows at once, so the previews below are only a guide.
Item {
    id: pg
    implicitHeight: col.implicitHeight

    // true for a moment after every slider move: Settings.qml stops the page Flickable from stealing the drag
    readonly property bool dragging: dragHold.running
    Timer { id: dragHold; interval: 300 }

    // effective value of a numeric key
    function eff(key) {
        if (key === "radius") return Theme.radius
        if (key === "gap") return Theme.gap
        if (key === "edgeGap") return Theme.gapOut
        if (key === "border") return Theme.borderSize
        return 0
    }
    function slide(key, v, max, step) {
        dragHold.restart()
        Appearance.set(key, Math.round(v * max / step) * step)
    }
    readonly property bool anyOverride: Appearance.keys.some(k => Appearance.overridden(k))
    readonly property bool multiMonitor: Quickshell.screens.length > 1
    // with one monitor the "all monitors" switch is the only one: it shows that monitor's effective value
    // (a leftover entry of its own, e.g. from a docked laptop, wins in Hyprland) and clears it when used
    readonly property string soleKey: !multiMonitor && Quickshell.screens.length === 1 ? Appearance.monitorKey(Quickshell.screens[0]) : ""

    readonly property int titleW: 120          // label column, so the sliders line up
    readonly property int noteW: 64            // "(default)" column

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 12

        // ---- shape ----
        SectionHead { title: "Shape" }
        Repeater {
            model: [
                { key: "radius", title: "Corner radius", max: 24, step: 1 },
                { key: "border", title: "Window border", max: 4, step: 1 }
            ]
            delegate: sliderRow
        }

        // ---- gaps ----
        SectionHead { title: "Gaps"; Layout.topMargin: 6 }
        Repeater {
            model: [{ key: "gap", title: "Window gap", max: 32, step: 2 }]
            delegate: sliderRow
        }
        SettingRow {
            titleWidth: pg.titleW
            Toggle {
                objectName: "toggle-edgeGap"
                checked: Appearance.overridden("edgeGap")
                onToggled: want => want ? Appearance.set("edgeGap", Theme.gapOut) : Appearance.unset("edgeGap")
            }
            Label { text: "Separate edge gap"; color: Theme.fgDim; font.pixelSize: Theme.fontSmall }
            Label { text: "gap at the screen edges"; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
        Repeater {
            model: [{ key: "edgeGap", title: "Edge gap", max: 40, step: 1 }]
            delegate: sliderRow
        }
        SettingRow {
            titleWidth: pg.titleW
            // all monitors: sets the default (also for monitors connected later) and clears the rows below
            Toggle {
                objectName: "toggle-smartGaps"
                checked: pg.soleKey !== "" ? Appearance.smartFor(pg.soleKey, Theme.smartGaps) : Theme.smartGaps
                onToggled: want => Appearance.setSmartAll(want)
            }
            Label { text: "No gaps for a single window"; color: Theme.fgDim; font.pixelSize: Theme.fontSmall }
            Label {
                text: pg.multiMonitor ? "a lone tiled window fills the screen · all monitors" : "a lone tiled window fills the screen"
                color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true; wrapMode: Text.WordWrap
            }
            Label {
                visible: !Appearance.overridden("smartGaps") && !(pg.soleKey !== "" && Appearance.smartOverridden(pg.soleKey))
                text: "(default)"; color: Theme.muted; font.pixelSize: Theme.fontCaption
            }
        }
        // one row per monitor (only with 2+ monitors): its own switch, "(default)" = follows the one above
        Repeater {
            model: pg.multiMonitor ? Quickshell.screens : []
            delegate: SettingRow {
                id: srow
                required property var modelData
                readonly property string key: Appearance.monitorKey(modelData)
                readonly property bool own: key !== "" && Appearance.smartOverridden(key)
                titleWidth: pg.titleW
                Toggle {
                    objectName: "toggle-smart-" + srow.modelData.name
                    checked: Appearance.smartFor(srow.key, Theme.smartGaps)
                    enabledLook: srow.key !== ""
                    onToggled: want => Appearance.setSmartFor(srow.key, want)
                }
                Icon { text: "\uf390"; font.pixelSize: 12; color: Theme.fgDim; Layout.preferredWidth: 16; horizontalAlignment: Text.AlignHCenter }
                Label { text: srow.modelData.model || srow.modelData.name; color: Theme.fgDim; font.pixelSize: Theme.fontSmall; elide: Text.ElideRight; Layout.maximumWidth: 220 }
                Label { text: srow.modelData.name; color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true; elide: Text.ElideRight }
                Label { text: srow.own ? "" : "(default)"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
            }
        }

        // ---- bar ----
        SectionHead { title: "Bar"; Layout.topMargin: 6 }
        SettingRow {
            title: "Bar mode"
            titleWidth: pg.titleW
            Segmented {
                values: [false, true]
                labels: ["Docked", "Floating"]
                objectNames: ["btn-docked", "btn-floating"]
                current: Theme.barFloating
                inset: 18
                segHeight: 24
                segWidth: 78
                onPicked: v => Appearance.set("barFloating", v)
            }
            Label {
                text: Theme.barFloating ? "edge gap from the screen edges, corner radius" : "flush with the screen edge, square"
                color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true; elide: Text.ElideRight
            }
            Label { visible: !Appearance.overridden("barFloating"); text: "(default)"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
        }

        // ---- previews ----
        SectionHead { title: "Preview"; detail: "outer " + Theme.radius + " / inner " + Theme.radiusItem + " / inner " + Theme.radiusDeep; Layout.topMargin: 6 }
        Flow {
            Layout.fillWidth: true
            spacing: 16

            // (1) real size: card (R) > item (inner(R, 12)) > chip (inner(item, 8))
            Rectangle {
                id: sample
                width: 220; height: Math.min(170, mini.height)
                radius: Theme.radius
                color: Theme.alpha(Theme.bg, 0.9)
                border.width: 1
                border.color: Theme.alpha(Theme.overlay, 0.6)
                Label { x: 12; y: 6; height: 16; text: "card · " + Theme.radius; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                Rectangle {
                    anchors { fill: parent; margins: 12; topMargin: 24 }
                    radius: Theme.radiusItem
                    color: Theme.alpha(Theme.fg, 0.07)
                    border.width: 1
                    border.color: Theme.alpha(Theme.overlay, 0.5)
                    Label { x: 8; y: 4; height: 16; text: "item · " + Theme.radiusItem; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                    Rectangle {
                        anchors { fill: parent; margins: 8; topMargin: 22 }
                        radius: Theme.radiusDeep
                        color: Theme.alpha(Theme.accent, 0.22)
                        border.width: 1
                        border.color: Theme.alpha(Theme.accent, 0.7)
                        Label { anchors.centerIn: parent; text: "chip · " + Theme.radiusDeep; color: Theme.accent; font.pixelSize: Theme.fontCaption }
                    }
                }
            }

            // (2) scaled desktop: bar on the top edge, two tiled windows (Hyprland layout math, see Theme.qml)
            Rectangle {
                id: mini
                readonly property var scr: (pg.Window.window as Window)?.screen
                readonly property real sw: scr ? scr.width : 2560
                readonly property real sh: scr ? scr.height : 1440
                readonly property real k: Math.min(0.2, (col.width - 2) / sw)
                function s(v) { return v * k }
                // a nonzero border stays visible at this scale
                function sb(v) { return v <= 0 ? 0 : Math.max(1, v * k) }
                width: Math.round(sw * k); height: Math.round(sh * k)
                color: Theme.bgAlt
                border.width: 1
                border.color: Theme.alpha(Theme.overlay, 0.6)
                clip: true

                Image {
                    anchors.fill: parent
                    source: Theme.wallpaper ? "file://" + Theme.wallpaper : ""
                    sourceSize.width: 640
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                // bar
                Rectangle {
                    x: mini.s(Theme.barGap); y: mini.s(Theme.barGap)
                    width: mini.width - 2 * x; height: mini.s(Theme.barHeight)
                    radius: mini.s(Theme.barRadius)
                    color: Theme.surface2
                    Row {
                        anchors { left: parent.left; leftMargin: mini.s(Theme.barPad); verticalCenter: parent.verticalCenter }
                        spacing: mini.s(6)
                        Repeater {
                            model: [60, 40, 40]
                            Rectangle {
                                required property int modelData
                                width: mini.s(modelData); height: mini.s(Theme.barHeight - 2 * Theme.barPad)
                                radius: mini.s(Theme.radiusChip)
                                color: Theme.alpha(Theme.fg, 0.16)
                            }
                        }
                    }
                }

                // two tiled windows: gaps_out at the screen edges, 2 * gaps_in between, border inside the box
                Repeater {
                    model: 2
                    Rectangle {
                        required property int index
                        readonly property real wy: Theme.barReserve + Theme.gapOut
                        readonly property real areaW: mini.sw - 2 * Theme.gapOut
                        readonly property real w: (areaW - 2 * Theme.gapIn) / 2
                        x: mini.s(Theme.gapOut + index * (w + 2 * Theme.gapIn))
                        y: mini.s(wy)
                        width: mini.s(w)
                        height: mini.s(mini.sh - wy - Theme.gapOut)
                        radius: mini.s(Theme.radius)
                        color: Theme.bg
                        border.width: mini.sb(Theme.borderSize)
                        border.color: index === 0 ? Theme.accent : Theme.overlay
                        Column {
                            x: mini.s(40); y: mini.s(36)
                            spacing: mini.s(22)
                            Repeater {
                                model: [0.55, 0.8, 0.4, 0.7]
                                Rectangle {
                                    required property real modelData
                                    width: mini.s(1100) * modelData; height: mini.s(10)
                                    radius: height / 2
                                    color: Theme.alpha(Theme.fg, 0.18)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- reset + footnote ----
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 12
            Btn { objectName: "btn-reset"; text: "Reset to theme defaults"; inset: 18; implicitHeight: 26; enabledLook: pg.anyOverride; onClicked: if (pg.anyOverride) Appearance.reset() }
            Label {
                Layout.fillWidth: true
                text: "Changes apply to Hyprland and the shell immediately and survive wallpaper changes."
                color: Theme.muted; font.pixelSize: Theme.fontCaption
                wrapMode: Text.WordWrap
            }
        }
    }

    // one labelled slider: title | slider | value | "(default)" while the key is not overridden
    Component {
        id: sliderRow
        SettingRow {
            id: row
            required property var modelData
            readonly property int cur: pg.eff(modelData.key)
            readonly property bool own: Appearance.overridden(modelData.key)
            title: modelData.title
            titleWidth: pg.titleW
            visible: modelData.key !== "edgeGap" || own
            Slider {
                wheel: false
                objectName: "slider-" + row.modelData.key
                Layout.fillWidth: true
                value: row.cur / row.modelData.max
                onMoved: v => pg.slide(row.modelData.key, v, row.modelData.max, row.modelData.step)
            }
            Label { text: row.cur + " px"; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight; color: Theme.fg; font.pixelSize: Theme.fontSmall }
            Label { text: row.own ? "" : "(default)"; Layout.preferredWidth: pg.noteW; color: Theme.muted; font.pixelSize: Theme.fontCaption }
        }
    }
}
