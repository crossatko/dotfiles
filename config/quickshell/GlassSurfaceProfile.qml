pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// One surface of Settings > Glass > Surfaces (GlassSurfaces `surfaces` entry): a FoldSection whose head says how many
// keys it overrides, with a reset-to-global button; the body has one GlassOptRow per profile key (moving a slider
// overrides that key, its reset button inherits the global value again). Window borders add an on / off switch and
// the border-size hint.
FoldSection {
    id: sp
    required property var surface
    property real titleW: 120
    property real valueW: 62
    signal dragged()

    readonly property var gs: GlassSurfaces
    readonly property int n: gs.count(surface.id)
    readonly property bool isBorder: surface.id === "border"
    readonly property bool supported: gs.surfaceOk(surface)

    objectName: "surface-" + surface.id      // test hook: `settingsui fold surface-<id> 1`
    title: surface.label
    detail: !supported ? "" : (isBorder ? (gs.borderOn ? "on" : "off") : "") + (n === 0 ? "" : (isBorder ? " · " : "") + n + (n === 1 ? " override" : " overrides"))
    trailing: [
        ResetBtn {
            objectName: "reset-surface-" + sp.surface.id
            set: sp.n > 0
            onClicked: sp.gs.reset(sp.surface.id)
        }
    ]

    RowLayout {
        visible: !sp.supported
        spacing: Theme.controlGap
        Icon { text: Icons.lock; font.pixelSize: Theme.iconSm; color: Theme.muted }
        Label { text: "not in this Hyprland build"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
    }
    SettingRow {
        visible: sp.isBorder
        title: "Glass ring"
        titleWidth: sp.titleW
        Toggle {
            objectName: "toggle-border-glass"
            checked: sp.gs.borderOn
            onToggled: want => sp.gs.setBorder(want)
        }
        InfoTip { icon: Theme.borderSize > 0 ? Icons.info : Icons.warning; color: Theme.borderSize > 0 ? Theme.muted : Theme.yellow
                  text: "Only drawn with a window border (Look & feel > Shape > Customise… > Window border, now " + Theme.borderSize + " px)." }
        Item { Layout.fillWidth: true }
    }
    Repeater {
        model: sp.supported ? sp.gs.keys : []
        GlassOptRow {
            id: kr
            required property string modelData
            o: sp.gs.opt(modelData)
            title: sp.gs.labels[modelData]
            titleWidth: sp.titleW
            valueW: sp.valueW
            cur: sp.gs.value(sp.surface.id, modelData)
            inherited: !sp.gs.isOverridden(sp.surface.id, modelData)
            changed: !inherited
            mark: kr.toNorm(sp.gs.tune.values[kr.modelData])
            resetName: "reset-" + sp.surface.id + "-" + modelData
            onMoved: v => { sp.dragged(); sp.gs.set(sp.surface.id, kr.modelData, v) }
            onReset: sp.gs.unset(sp.surface.id, kr.modelData)
        }
    }
}
