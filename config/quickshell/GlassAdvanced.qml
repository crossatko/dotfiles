pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings > Look & feel > Glass style > Customise…: every decoration:blur:solid_glass:* option of the Hyprland fork,
// grouped as Lens / Light / Material, the tint (A / R / G / B), the shell-only options (group Shell: flat card edge,
// pointer rim), the Lua copy / reset actions, and below them the per-surface profiles (GlassSurfacesSection).
// The shell's own glass (slider / toggle / OSD lenses, glass lettering, flat card edge) uses these values too, so the
// section is also there without solid_glass (stock Hyprland): it then edits and saves them for the shell only.
// The values are those of the active light / dark mode; each mode keeps its own (GlassTuneCtl, glass.json).
// Everything goes through the GlassTuneCtl singleton: a drag is applied live (throttled `hyprctl eval`) and saved
// (debounced) in glass.json, which hypr/hyprland/managed.lua applies at every config load on top of settings.lua.
// A moved slider turns the Glass style choice above into Custom; a preset click puts every value back to a named set.
ColumnLayout {
    id: ga
    readonly property var tune: GlassTuneCtl
    // true for a moment after every slider move: Settings.qml stops the page Flickable from stealing the drag
    readonly property bool dragging: dragHold.running
    Timer { id: dragHold; interval: 300 }
    property real titleW: 120          // label column, so the sliders line up
    readonly property int valueW: 62
    spacing: 12

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

    RowLayout {
        visible: ga.tune.guard === "error" && !ga.tune.unsupported
        spacing: Theme.controlGap
        Icon { text: Icons.warning; font.pixelSize: Theme.iconSm; color: Theme.red }
        Label { Layout.fillWidth: true; elide: Text.ElideRight; text: ga.tune.guardError; color: Theme.red; font.pixelSize: Theme.fontCaption }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 12
        enabled: ga.tune.editable
        opacity: ga.tune.editable ? 1 : 0.4

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
                    Layout.topMargin: grp.index > 0 ? 6 : 0
                    InfoTip { visible: grp.modelData === "Shell"; text: "Drawn by the shell itself (card edge, pointer rim); never sent to Hyprland." }
                }
                Repeater {
                    model: ga.tune.opts.filter(o => o.group === grp.modelData)
                    delegate: optRow
                }

                // tint: swatch + A / R / G / B channels (alpha = absorption)
                SettingRow {
                    visible: grp.modelData === "Material"
                    title: "Tint"
                    titleWidth: ga.titleW
                    Rectangle {
                        implicitWidth: 44; implicitHeight: 20
                        radius: Math.min(5, Theme.radiusDeep)
                        color: "#808080"
                        clip: true
                        border.width: 1; border.color: Theme.alpha(Theme.fg, 0.3)
                        Rectangle { anchors.fill: parent; color: ga.tintColor }
                        Rectangle { width: parent.width / 2; height: parent.height; color: Qt.rgba(ga.tintColor.r, ga.tintColor.g, ga.tintColor.b, 1) }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: ga.tune.fmt("tint", ga.tune.values.tint)
                        color: Theme.fgDim; font.pixelSize: Theme.fontSmall
                    }
                    ResetBtn {
                        objectName: "reset-tint"
                        set: ga.tune.isChanged("tint")
                        onClicked: ga.tune.reset("tint")
                    }
                }
                // the colour follows the theme background (on) or is the user's own (off, the channels below)
                SettingRow {
                    visible: grp.modelData === "Material"
                    title: "Tint colour"
                    titleWidth: ga.titleW
                    Toggle {
                        objectName: "toggle-tint-from-bg"
                        checked: ga.tune.tintFromBg
                        onToggled: want => ga.tune.setTintFromBg(want)
                    }
                    Label {
                        Layout.fillWidth: true
                        text: ga.tune.tintFromBg ? "From the theme background" : "Own"
                        color: Theme.fgDim; font.pixelSize: Theme.fontSmall
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
                        titleWidth: ga.titleW
                        readonly property int cur: ga.tintChannel(modelData.s)
                        Slider {
                            wheel: false
                            objectName: "slider-tint-" + trow.modelData.s
                            Layout.fillWidth: true
                            value: trow.cur / 255
                            notches: [((GlassTuneCtl.tintDef >>> trow.modelData.s) & 255) / 255]   // the default tint's channel
                            onMoved: v => ga.setTint(trow.modelData.s, v * 255)
                        }
                        Label { text: trow.cur; Layout.preferredWidth: ga.valueW; horizontalAlignment: Text.AlignRight; color: Theme.fg; font.pixelSize: Theme.fontSmall }
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
            Btn { objectName: "btn-copy-changed"; visible: ga.tune.ready; glyph: Icons.copy; text: "Copy Lua"; outerRadius: Theme.radiusPage; inset: 9; implicitHeight: 26; onClicked: ga.tune.copy(true) }
            Btn { objectName: "btn-copy-all"; visible: ga.tune.ready; glyph: Icons.copy; text: "Copy all"; outerRadius: Theme.radiusPage; inset: 9; implicitHeight: 26; onClicked: ga.tune.copy(false) }
            Btn { objectName: "btn-reset-all"; text: "Reset glass"; outerRadius: Theme.radiusPage; inset: 9; implicitHeight: 26; enabledLook: ga.anyChanged; onClicked: ga.tune.reset("all") }
            InfoTip { text: ga.tune.ready ? "Changed values are applied to Hyprland while you drag and saved in glass.json, which wins over settings.lua at every config load. Copy Lua = the changed values as a settings.lua snippet." + (ga.tune.nestedOnly ? " (nested dev instance only)" : "")
                                          : "Saved in glass.json; applied to the shell's own glass at once." }
            Label { visible: ga.tune.status !== ""; Layout.fillWidth: true; elide: Text.ElideRight; text: ga.tune.status; color: Theme.muted; font.pixelSize: Theme.fontCaption }
            Item { Layout.fillWidth: true }
        }
    }

    GlassSurfacesSection {
        Layout.fillWidth: true
        titleW: ga.titleW
        valueW: ga.valueW
        onDragged: dragHold.restart()
    }

    // one option: title | slider | value | reset
    Component {
        id: optRow
        GlassOptRow {
            id: row
            required property var modelData
            o: modelData
            cur: ga.tune.values[modelData.key]
            title: modelData.label
            titleWidth: ga.titleW
            valueW: ga.valueW
            changed: ga.tune.isChanged(modelData.key)
            onMoved: v => ga.slide(row.modelData.key, v)
            onReset: ga.tune.reset(row.modelData.key)
        }
    }
}
