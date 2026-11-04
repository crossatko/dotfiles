pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings > Voice / Diacritics > Pill: where the pill sits (the pill_* keys of `store`, launcher/js/PillPos.js), the same rows on
// both pages. Primary: Edge (Bar = the bar's edge, Top, Bottom) and Position (GridPick 3 x 2 on a small screen: the lit cell =
// where it sits now; a click on the other row also sets that edge: "bar" when it is the bar's). Customise…: Gap (in the bar's gap tokens, shown in px),
// Horizontal (0 left .. 100 % right), Monitor (the focused one, or always one monitor). `place` = the preview's PillPlacement
// (resolved edge, gap unit).
ColumnLayout {
    id: pr
    property var store: null
    property PillPlacement place: null
    property real titleWidth: 120
    readonly property bool dragging: gap.dragging || horiz.dragging
    readonly property int foldChanged: pr.store ? pr.store.pillKeys.filter(k => k !== "pill_edge" && pr.store.overridden(k)).length : 0
    readonly property bool atTop: place ? place.atTop : true
    readonly property bool offGrid: store ? [0, 0.5, 1].every(v => Math.abs(store.pillX - v) > 0.01) : false

    // [Focused monitor, the connected ones, the saved one when it is not connected]
    readonly property var screenOptions: {
        const o = [{ label: "Focused monitor", key: "" }]
        for (const s of Monitors.ordered) o.push({ label: Monitors.title(s), key: Appearance.monitorKey(s), note: s.name })
        const k = store ? store.pillScreen : ""
        if (k !== "" && !o.some(x => x.key === k)) o.push({ label: k, key: k, note: "not connected", noteTint: Theme.yellow })
        return o
    }
    readonly property int screenIndex: Math.max(0, screenOptions.findIndex(o => o.key === (store ? store.pillScreen : "")))

    Layout.fillWidth: true
    spacing: Theme.gapRow

    ChoiceRow {
        objectName: "pill-edge"
        title: "Edge"; titleWidth: pr.titleWidth
        values: ["bar", "top", "bottom"]
        labels: ["Bar", "Top", "Bottom"]
        objectNames: ["pill-edge-bar", "pill-edge-top", "pill-edge-bottom"]
        current: pr.store ? pr.store.pillEdge : "bar"
        info: "Bar = the edge the bar is on (no bar: the bottom). The pill hangs past the bar there; on the other edge it keeps the edge gap."
        onPicked: v => pr.store.set("pill_edge", v)
    }
    SettingRow {
        title: "Position"; titleWidth: pr.titleWidth
        GridPick {
            objectName: "pill-grid"
            ySteps: [0, 1]
            px: pr.store ? pr.store.pillX : 0.5
            py: pr.atTop ? 0 : 1
            onPicked: (x, y) => {
                pr.store.set("pill_x", x)
                // the bar's row = "bar" (keeps following the bar), the other row = that edge
                const want = y === 0 ? "top" : "bottom"
                if ((y === 0) !== pr.atTop) pr.store.set("pill_edge", pr.place && pr.place.barEdge === want ? "bar" : want)
            }
        }
        CustomTag { visible: pr.offGrid }
        Item { Layout.fillWidth: true }
    }

    AdvancedFold {
        objectName: "fold-pill"
        detail: pr.foldChanged > 0 ? pr.foldChanged + " changed" : ""
        PrefSlider {
            id: gap
            title: "Gap"; titleWidth: pr.titleWidth
            store: pr.store; key: "pill_gap"
            format: v => Math.round(v * (pr.place ? pr.place.gapUnit : 8)) + " px"
        }
        PrefSlider {
            id: horiz
            title: "Horizontal"; titleWidth: pr.titleWidth
            store: pr.store; key: "pill_x"
            format: v => Math.round(v * 100) + " %"
            extras: [0, 1]
        }
        SettingRow {
            title: "Monitor"; titleWidth: pr.titleWidth; titleTopAt: 15
            DropSelect {
                objectName: "pill-screen"
                Layout.preferredWidth: 340; Layout.alignment: Qt.AlignTop
                options: pr.screenOptions
                currentIndex: pr.screenIndex
                onPicked: i => pr.store.set("pill_screen", pr.screenOptions[i].key)
            }
            InfoTip { Layout.alignment: Qt.AlignTop; text: "Focused monitor = the one you are working on when the pill opens. A picked monitor that is not connected falls back to the focused one." }
            Item { Layout.fillWidth: true }
        }
    }
}
