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
    function setTint(shift, argb) {
        dragHold.restart()
        if (shift !== 24 && tune.tintFromBg) tune.setTintFromBg(false)   // a colour of its own
        tune.set("tint", argb)
    }
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
                ArgbRow {
                    visible: grp.modelData === "Material"
                    title: "Tint"
                    alphaName: "Absorption (A)"
                    objectPrefix: "tint"
                    titleW: ga.titleW
                    valueW: ga.valueW
                    value: ga.tune.values.tint
                    defaultValue: GlassTuneCtl.tintDef
                    changed: ga.tune.isChanged("tint")
                    onReset: ga.tune.reset("tint")
                    onEdited: (shift, argb) => ga.setTint(shift, argb)
                    // the colour follows the theme background (on) or is the user's own (off, the channels below)
                    SettingRow {
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
