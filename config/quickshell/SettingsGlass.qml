pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings -> Glass: the decoration:blur:solid_glass:* options of the Hyprland fork, grouped as Lens / Light /
// Material, plus the tint (A / R / G / B), and the shell-only options (group Shell, e.g. the flat card edge).
// The shell's own glass (slider / toggle / OSD lenses, glass lettering, flat card edge) uses these values too, so the
// page is also there without solid_glass (stock Hyprland): it then edits and saves them for the shell only.
// The values are those of the active light / dark mode; each mode keeps its own (GlassTuneCtl, glass.json).
// Everything goes through the GlassTuneCtl singleton: a drag is applied live (throttled `hyprctl eval`) and saved
// (debounced) in glass.json, which hypr/hyprland/managed.lua applies at every config load on top of settings.lua.
Item {
    id: pg
    implicitHeight: col.implicitHeight

    readonly property var tune: GlassTuneCtl
    // true for a moment after every slider move: Settings.qml stops the page Flickable from stealing the drag
    readonly property bool dragging: dragHold.running
    Timer { id: dragHold; interval: 300 }

    readonly property int titleW: 120          // label column, so the sliders line up
    readonly property int valueW: 62

    // slider position <-> value (curve > 1 gives the low end more travel)
    function toNorm(o, v) { return Math.pow(Math.max(0, Math.min(1, (v - o.min) / (o.max - o.min))), 1 / (o.curve || 1)) }
    function fromNorm(o, n) { return o.min + (o.max - o.min) * Math.pow(n, o.curve || 1) }
    function slide(key, v) { dragHold.restart(); tune.set(key, v) }

    function tintChannel(shift) { return (Math.round(tune.values.tint) >>> shift) & 255 }
    function setTint(shift, v) {
        dragHold.restart()
        const t = Math.round(tune.values.tint) >>> 0
        if (shift !== 24 && tune.tintFromBg) tune.setTintFromBg(false)   // a colour of its own
        tune.set("tint", ((t & ~(255 << shift)) | (Math.round(v) << shift)) >>> 0)
    }
    readonly property color tintColor: Qt.rgba(tintChannel(16) / 255, tintChannel(8) / 255, tintChannel(0) / 255, tintChannel(24) / 255)
    readonly property bool anyChanged: tune.changedKeys.length > 0

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 12

        Label {
            visible: !pg.tune.ready
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: pg.tune.unsupported ? Theme.muted : pg.tune.guard === "error" ? Theme.red : Theme.muted
            font.pixelSize: Theme.fontSmall
            text: pg.tune.unsupported ? "This Hyprland draws no solid_glass: these values only shape the shell's own glass (lenses, glass lettering, flat card edge)."
                : pg.tune.guard === "error" ? "Disabled: " + pg.tune.guardError : "Checking the compositor instance..."
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            enabled: pg.tune.editable
            opacity: pg.tune.editable ? 1 : 0.4

            Repeater {
                model: ["Lens", "Light", "Material", "Shell"]
                ColumnLayout {
                    id: grp
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 12

                    SectionHead {
                        title: grp.modelData
                        detail: grp.modelData === "Shell" ? "drawn by the shell, never sent to Hyprland" : ""
                        Layout.topMargin: grp.index > 0 ? 6 : 0
                    }
                    Repeater {
                        model: pg.tune.opts.filter(o => o.group === grp.modelData)
                        delegate: optRow
                    }

                    // tint: swatch + A / R / G / B channels (alpha = absorption)
                    SettingRow {
                        visible: grp.modelData === "Material"
                        title: "Tint"
                        titleWidth: pg.titleW
                        Rectangle {
                            implicitWidth: 44; implicitHeight: 20
                            radius: Math.min(5, Theme.radiusDeep)
                            color: "#808080"
                            clip: true
                            border.width: 1; border.color: Theme.alpha(Theme.fg, 0.3)
                            Rectangle { anchors.fill: parent; color: pg.tintColor }
                            Rectangle { width: parent.width / 2; height: parent.height; color: Qt.rgba(pg.tintColor.r, pg.tintColor.g, pg.tintColor.b, 1) }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: pg.tune.fmt("tint", pg.tune.values.tint)
                            color: Theme.fgDim; font.pixelSize: Theme.fontSmall
                        }
                        Btn {
                            objectName: "reset-tint"
                            icon: true; text: ""
                            implicitHeight: 20; implicitWidth: 24
                            outerRadius: Theme.radius; inset: 12
                            enabledLook: pg.tune.isChanged("tint")
                            onClicked: pg.tune.reset("tint")
                        }
                    }
                    SettingRow {
                        visible: grp.modelData === "Material"
                        title: "Tint colour"
                        titleWidth: pg.titleW
                        Label {
                            Layout.fillWidth: true
                            text: pg.tune.tintFromBg ? "from the theme background (" + Theme.mode + " mode)" : "own colour (Red / Green / Blue)"
                            color: Theme.fgDim; font.pixelSize: Theme.fontSmall
                        }
                        Toggle {
                            objectName: "toggle-tint-from-bg"
                            checked: pg.tune.tintFromBg
                            onToggled: want => pg.tune.setTintFromBg(want)
                        }
                    }
                    Repeater {
                        model: grp.modelData === "Material" ? [
                            { n: "Absorption (A)", s: 24 },
                            { n: "Red", s: 16 },
                            { n: "Green", s: 8 },
                            { n: "Blue", s: 0 }
                        ] : []
                        SettingRow {
                            id: trow
                            required property var modelData
                            title: modelData.n
                            titleWidth: pg.titleW
                            readonly property int cur: pg.tintChannel(modelData.s)
                            Slider {
                                wheel: false
                                objectName: "slider-tint-" + trow.modelData.s
                                Layout.fillWidth: true
                                value: trow.cur / 255
                                onMoved: v => pg.setTint(trow.modelData.s, v * 255)
                            }
                            Label { text: trow.cur; Layout.preferredWidth: pg.valueW; horizontalAlignment: Text.AlignRight; color: Theme.fg; font.pixelSize: Theme.fontSmall }
                            Item { Layout.preferredWidth: 24 }      // where the reset button sits on the other rows
                        }
                    }
                }
            }

            // ---- actions ----
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 8
                Btn { objectName: "btn-copy-changed"; visible: pg.tune.ready; text: "Copy changed as Lua"; inset: 18; implicitHeight: 26; onClicked: pg.tune.copy(true) }
                Btn { objectName: "btn-copy-all"; visible: pg.tune.ready; text: "Copy all as Lua"; inset: 18; implicitHeight: 26; onClicked: pg.tune.copy(false) }
                Btn { objectName: "btn-reset-all"; text: "Reset all"; inset: 18; implicitHeight: 26; enabledLook: pg.anyChanged; onClicked: pg.tune.reset("all") }
                Item { Layout.fillWidth: true }
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.muted
                font.pixelSize: Theme.fontCaption
                text: (pg.tune.status ? pg.tune.status + "\n" : "")
                    + (pg.tune.nestedOnly ? "Applies to the nested dev instance only\n" : "")
                    + (pg.tune.ready ? "Changes apply to Hyprland while you drag and are saved in glass.json, which overrides the solid_glass block of settings.lua at every config load."
                                     : "Changes apply to the shell at once and are saved in glass.json.")
            }
        }
    }

    // one option: title | slider | value | reset
    Component {
        id: optRow
        SettingRow {
            id: row
            required property var modelData
            readonly property real cur: pg.tune.values[modelData.key]
            title: modelData.label
            titleWidth: pg.titleW
            Slider {
                wheel: false
                objectName: "slider-" + row.modelData.key
                Layout.fillWidth: true
                value: pg.toNorm(row.modelData, row.cur)
                onMoved: v => pg.slide(row.modelData.key, pg.fromNorm(row.modelData, v))
            }
            Label {
                text: row.cur.toFixed(row.modelData.dec) + (row.modelData.unit || "")
                Layout.preferredWidth: pg.valueW
                horizontalAlignment: Text.AlignRight
                color: Theme.fg; font.pixelSize: Theme.fontSmall
            }
            Btn {
                objectName: "reset-" + row.modelData.key
                icon: true; text: ""
                implicitHeight: 20; implicitWidth: 24
                outerRadius: Theme.radius; inset: 12
                enabledLook: pg.tune.isChanged(row.modelData.key)
                onClicked: pg.tune.reset(row.modelData.key)
            }
        }
    }
}
