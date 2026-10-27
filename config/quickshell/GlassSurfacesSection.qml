pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings > Glass > Surfaces: a glass profile per surface type (GlassSurfaces is the engine), one GlassSurfaceProfile
// fold each, a "Differentiated" preset and a reset of all profiles. Disabled with an explanation when the compositor
// has no per-surface glass (stock Hyprland, older fork builds).
ColumnLayout {
    id: sec
    property real titleW: 120
    property real valueW: 62
    signal dragged()

    readonly property var gs: GlassSurfaces
    spacing: 12

    SectionHead {
        title: "Surfaces"
        detail: sec.gs.available && sec.gs.totalCount > 0 ? sec.gs.totalCount + " overrides" : ""
        Layout.topMargin: 6
        InfoTip { visible: !sec.gs.available; icon: Icons.lock; text: sec.gs.unavailableReason }
        InfoTip { visible: sec.gs.available; text: "A profile per surface: each value either follows the global glass above or overrides it for that surface only." }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 12
        enabled: sec.gs.available
        opacity: sec.gs.available ? 1 : 0.4

        // the primary choice: one glass everywhere, or the "Differentiated" set (a flatter bar, deeper popups and OSD);
        // anything else saved in the profiles = Custom (kept until a choice is made; the folds below show it)
        ChoiceRow {
            title: "Profiles"
            titleWidth: sec.titleW
            values: ["uniform", "differentiated"]
            labels: ["Uniform", "Differentiated"]
            objectNames: ["btn-surfaces-reset", "btn-preset-differentiated"]
            current: sec.gs.current
            onPicked: v => v === "uniform" ? sec.gs.reset("all") : sec.gs.applyPreset(v)
        }
        Repeater {
            model: sec.gs.surfaces
            GlassSurfaceProfile {
                required property var modelData
                surface: modelData
                Layout.fillWidth: true
                titleW: sec.titleW
                valueW: sec.valueW
                onDragged: sec.dragged()
            }
        }
        Label {
            visible: sec.gs.status !== ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Theme.red
            font.pixelSize: Theme.fontCaption
            text: sec.gs.status
        }
    }
}
