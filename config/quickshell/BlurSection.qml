pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings > Look & feel > Blur: pick any blur variant this Hyprland has (stock v0.57: kawase, frost, ripple, drops, water,
// fluid jar, prism, heat shimmer, acrylic, aurora, haze; the fork adds solid glass) and tune that variant's options, then
// the options every variant shares in a fold. Table-driven: BlurTuneCtl.variants / .opts describe everything, a new variant
// or option is a table entry there (and in managed.lua, which re-applies the saved values at config load).
// The shell's own glass (Theme.glass) is on only for solid glass; with any other variant the cards fall back to the plain
// translucent fills over the blur, exactly as on stock Hyprland.
ColumnLayout {
    id: bs
    readonly property var ctl: BlurTuneCtl
    property real titleW: 120
    readonly property int valueW: 62
    readonly property bool dragging: dragHold.running
    Timer { id: dragHold; interval: 300 }
    readonly property var cur: ctl.variantById(ctl.variant)
    readonly property var own: ctl.variantOpts(ctl.variant)
    readonly property bool solid: ctl.variant === "solid_glass"
    spacing: 12

    SectionHead {
        title: "Blur"
        Layout.topMargin: 6
        detail: bs.cur ? bs.cur.label : ""
        InfoTip { text: "The compositor blur behind translucent windows. Variants are Hyprland's own blur styles; some animate and cost GPU. The shell's glass look (lenses, rims) is only on with Solid glass." }
    }

    Label {
        visible: !bs.ctl.ready
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: GlassTuneCtl.guard === "error" ? GlassTuneCtl.guardError : "Reading the blur options from Hyprland…"
        color: Theme.muted; font.pixelSize: Theme.fontCaption
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 12
        enabled: bs.ctl.ready
        opacity: bs.ctl.ready ? 1 : 0.4

        SettingRow {
            title: "Variant"
            titleWidth: bs.titleW
            titleTopAt: 13
            Flow {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: bs.ctl.available
                    Btn {
                        required property var modelData
                        objectName: "blur-variant-" + modelData.id
                        text: modelData.label
                        active: bs.ctl.variant === modelData.id
                        outerRadius: Theme.radiusPage; inset: 9
                        implicitHeight: 26
                        onClicked: bs.ctl.setVariant(modelData.id)
                    }
                }
            }
        }
        Label {
            Layout.fillWidth: true
            Layout.leftMargin: bs.titleW + 10
            visible: bs.cur !== undefined
            wrapMode: Text.WordWrap
            text: bs.cur ? bs.cur.note : ""
            color: Theme.muted; font.pixelSize: Theme.fontCaption
        }

        // the chosen variant's own options
        Repeater {
            model: bs.own
            delegate: BlurOptRow {
                required property var modelData
                o: modelData
                titleW: bs.titleW
                valueW: bs.valueW
                onDragged: dragHold.restart()
            }
        }
        Label {
            visible: !bs.solid && bs.own.length === 0 && bs.cur !== undefined
            Layout.leftMargin: bs.titleW + 10
            text: "No options of its own: it uses the shared ones below."
            color: Theme.muted; font.pixelSize: Theme.fontCaption
        }
        RowLayout {
            visible: bs.own.length > 0
            Layout.fillWidth: true
            Btn {
                objectName: "btn-reset-blur-variant"
                text: "Reset " + (bs.cur ? bs.cur.label.toLowerCase() : "") + " options"
                outerRadius: Theme.radiusPage; inset: 9; implicitHeight: 26
                enabledLook: bs.ctl.changedCount(bs.own) > 0
                onClicked: bs.ctl.resetGroup(bs.ctl.variant)
            }
            Item { Layout.fillWidth: true }
        }
        Label {
            visible: bs.solid
            Layout.fillWidth: true
            Layout.leftMargin: bs.titleW + 10
            wrapMode: Text.WordWrap
            text: "Solid glass is tuned under Glass > Customise… above."
            color: Theme.muted; font.pixelSize: Theme.fontCaption
        }

        AdvancedFold {
            objectName: "fold-blur-shared"
            label: "Shared blur options…"
            visible: bs.ctl.sharedAny.length > 0
            detail: bs.ctl.changedCount(bs.ctl.sharedAny) > 0 ? bs.ctl.changedCount(bs.ctl.sharedAny) + " changed" : ""
            Repeater {
                model: bs.ctl.sharedGroups.filter(g => bs.ctl.sharedOpts(g).length > 0)
                ColumnLayout {
                    id: grp
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 12
                    SectionHead { title: grp.modelData; Layout.topMargin: grp.index > 0 ? 6 : 0 }
                    Repeater {
                        model: bs.ctl.sharedOpts(grp.modelData)
                        delegate: BlurOptRow {
                            required property var modelData
                            o: modelData
                            titleW: bs.titleW
                            valueW: bs.valueW
                            onDragged: dragHold.restart()
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Btn {
                    objectName: "btn-reset-blur-shared"
                    text: "Reset shared options"
                    outerRadius: Theme.radiusPage; inset: 9; implicitHeight: 26
                    enabledLook: bs.ctl.changedCount(bs.ctl.sharedAny) > 0
                    onClicked: bs.ctl.resetGroup("shared")
                }
                InfoTip { text: "Reset writes Hyprland's built-in defaults, which may differ from the values in settings.lua. Changes are applied live and saved in glass.json." }
                Label { visible: bs.ctl.status !== ""; Layout.fillWidth: true; elide: Text.ElideRight; text: bs.ctl.status; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                Item { Layout.fillWidth: true }
            }
        }
    }
}
