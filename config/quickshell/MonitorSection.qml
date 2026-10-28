pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// THE monitor section of the Settings pages: the first row of every page with per-monitor settings (Wallpaper, Bar, Lock
// screen, Desktop clock) and the smart gaps row of Look & feel > Shape, laid out the same everywhere: one MonitorChip per
// connected monitor in Monitors.ordered order (primary first), all the same width on a constant 28 px seam (so a chip
// sits at the same place on every page), then "All" and the page actions at the row's right end. A chip = the still,
// model / connector, the PrimaryTag dot, an optional badge and, on a page with a per-monitor on / off, the state cell
// (eye / eye-slash) at its end. Options (one component, the pages only turn parts on):
//   selection (default)  click the body / Left / Right = the monitor this page edits: the shared Settings pick
//                        (Monitors.selected / Monitors.select), so switching on one page carries to the others while
//                        Settings is open. `selectable: false` = no selection (the Shape row): the chip itself is the switch.
//   `switchable`         the page has a per-monitor on / off: each chip carries its MonitorStateCell (`onFor(s)`,
//                        `switchEnabledFor(s)`, `switchTipFor(s)`; act on `switched(screen, want)`, never flipped here), an
//                        off chip dims, and an "All" tile (LabelSwitch with the page's `allIcon`, the same cell) sits at the
//                        strip's end (`allOn`, `allSwitched(want)`, `allTip`). `glyphOn` / `glyphOff` = the cells' glyph pair
//                        (default eye / eye-slash). Space / Enter / T toggle the selected (focused) chip.
//   `linkable`           a MonitorLink bridge on the seam between neighbouring chips (`linkedAt(i)` / `linkToggled(i)` /
//                        `linkTip(i)`): an accent chain + connector while linked, a faint chain while not; a pair split by a row break
//                        shows a chain badge on both chips instead. `groupedFor(screen)` = linked to the current one: accent
//                        outline without the fill.
//   `markFor(s)`         an accent badge glyph on a chip (`markTipFor`), e.g. the palette source.
//   `thumbFor(s)`        the still a chip shows (default: what the monitor shows now).
//   children             page actions (MonitorAction) at the strip's end, after "All"; the tail moves under the chips when
//                        the row is too narrow, and chips that do not fit compact in one row wrap.
// One monitor: hidden, unless `showSingle` and switchable (then that monitor's chip with its cell, no "All", no tag).
// objectNames `monitor-chip-<conn>` (+ "-switch"), `<objectName>-all`, `monitor-link-<i>`.
Item {
    id: mc
    property var screens: Monitors.ordered.filter(s => s.width > 0 && s.height > 0)
    property string current: Monitors.selected ? Monitors.selected.name : ""
    property bool shared: true                      // picking a chip also moves the shared Settings pick
    property bool selectable: true
    property bool switchable: false
    property var onFor: function (s) { return true }
    property var switchEnabledFor: function (s) { return true }
    property var switchTipFor: function (s) { return "" }
    property bool allOn: false
    property string allIcon: Icons.monitor
    property string allTip: ""
    property string glyphOn: Icons.eye
    property string glyphOff: Icons.eyeOff
    property bool showSingle: false
    property bool linkable: false
    property var linkedAt: function (i) { return false }
    property var linkTip: function (i) { return "" }
    property var groupedFor: function (s) { return false }
    property var markFor: function (s) { return "" }   // an Icons glyph after the name, "" = none
    property var markTipFor: function (s) { return "" }
    property var thumbFor: function (s) { return LockWallpapers.stillFor(s) }
    signal picked(string name)
    signal switched(var screen, bool want)
    signal allSwitched(bool want)
    signal linkToggled(int i)
    default property alias trailing: actions.data

    readonly property bool multi: screens.length > 1
    readonly property bool shown: multi || (showSingle && switchable && screens.length === 1)
    readonly property bool allShown: switchable && multi
    readonly property int chipH: Theme.rowH             // a two-line chip (fontSmall + fontCaption) with its cell
    readonly property int chipMax: 240                  // widest a chip gets (long model names elide)
    readonly property int gapX: 28                      // the seam between two chips, on every page (the MonitorLink bridge sits in it)
    readonly property real tailW: tail.implicitWidth
    // every chip is as wide as the widest wants (capped), or what an equal share of the row allows, never under the
    // compact width: chips that do not fit compact in one row wrap onto more rows (4 monitors in a narrow window)
    readonly property real wantW: { void rep.count; let w = 0; for (let i = 0; i < rep.count; i++) { const e = rep.itemAt(i); if (e) w = Math.max(w, e.chip.naturalWidth) } return Math.min(chipMax, w) }   // qmllint disable missing-property
    readonly property real leastW: { void rep.count; let w = 0; for (let i = 0; i < rep.count; i++) { const e = rep.itemAt(i); if (e) w = Math.max(w, e.chip.compactWidth) } return w }   // qmllint disable missing-property
    readonly property int perRow: Math.max(1, Math.min(screens.length, Math.floor((width + gapX) / (leastW + gapX))))
    readonly property int rows: Math.ceil(screens.length / Math.max(1, perRow))
    readonly property bool stack: tailW > 0 && (rows > 1 || screens.length * wantW + (screens.length - 1) * gapX + Theme.pad + tailW > width)
    readonly property real chipsAvail: (stack || tailW === 0 ? width : width - tailW - Theme.pad) - (perRow - 1) * gapX
    readonly property real chipW: Math.max(leastW, Math.min(wantW, Math.floor(chipsAvail / perRow)))

    // keyboard cursor: the selected chip, or (selectable: false) a cursor of its own
    property int cursor: 0
    readonly property int currentIndex: selectable ? screens.findIndex(s => s.name === current) : Math.min(cursor, screens.length - 1)
    function pick(s) {
        if (shared) Monitors.select(s.name)
        picked(s.name)
    }
    function step(d) {
        const i = currentIndex
        const n = Math.max(0, Math.min(screens.length - 1, (i < 0 ? 0 : i + d)))
        if (n === i) return
        if (selectable) pick(screens[n]); else cursor = n
    }
    function flipCurrent() {
        const e = rep.itemAt(currentIndex)
        if (e) e.chip.flip()   // qmllint disable missing-property
    }

    visible: shown
    implicitHeight: shown ? chips.height + (stack ? Theme.gapRow + chipH : 0) : 0
    Layout.fillWidth: true
    activeFocusOnTab: shown
    Keys.onLeftPressed: step(-1)
    Keys.onRightPressed: step(1)
    Keys.onPressed: e => {
        if (switchable && (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_T)) {
            flipCurrent(); e.accepted = true
        }
    }
    Accessible.role: selectable ? Accessible.PageTabList : Accessible.List
    Accessible.name: "Monitor"

    // the selected chip's marker glides between the chips (as Segmented)
    GlideHighlight {
        visible: mc.selectable
        target: { void rep.count; const i = mc.currentIndex; return i < 0 || !mc.selectable ? null : rep.itemAt(i) ? rep.itemAt(i).chip : null }   // qmllint disable missing-property
        radius: Theme.radiusPage
        color: Theme.accentFill
        border.width: 1
        border.color: mc.activeFocus ? Theme.accent : Theme.accentEdge
    }
    Item {
        id: chips
        width: mc.perRow * mc.chipW + (mc.perRow - 1) * mc.gapX
        height: mc.rows * mc.chipH + (mc.rows - 1) * Theme.gapRow
        Repeater {
            id: rep
            model: mc.screens
            Row {
                id: ent
                required property var modelData
                required property int index
                readonly property Item chip: chipBox
                readonly property int col: index % mc.perRow
                spacing: 0
                x: col * (mc.chipW + mc.gapX) - (col > 0 ? mc.gapX : 0)
                y: Math.floor(index / mc.perRow) * (mc.chipH + Theme.gapRow)
                // the seam before a chip: the link bridge (linkable) or a plain gap (a row break has neither)
                Item {
                    visible: ent.col > 0
                    width: mc.gapX
                    height: mc.chipH
                    MonitorLink {
                        visible: mc.linkable && ent.col > 0
                        objectName: "monitor-link-" + (ent.index - 1)
                        anchors.fill: parent
                        linked: visible && mc.linkedAt(ent.index - 1)
                        tip: visible ? mc.linkTip(ent.index - 1) : ""
                        onToggled: mc.linkToggled(ent.index - 1)
                    }
                }
                MonitorChip {
                    id: chipBox
                    screen: ent.modelData
                    selectable: mc.selectable
                    selected: mc.selectable && ent.index === mc.currentIndex
                    focused: !mc.selectable && mc.activeFocus && ent.index === mc.currentIndex
                    grouped: !selected && mc.groupedFor(ent.modelData)
                    // a link that has no seam (its pair sits on another row): a chain badge on both chips
                    linkBadge: mc.linkable && ((ent.col === 0 && ent.index > 0 && mc.linkedAt(ent.index - 1))
                        || (ent.col === mc.perRow - 1 && ent.index < mc.screens.length - 1 && mc.linkedAt(ent.index)))
                    showPrimary: mc.multi
                    mark: mc.markFor(ent.modelData)
                    markTip: mc.markTipFor(ent.modelData)
                    thumb: mc.thumbFor(ent.modelData)
                    switchable: mc.switchable
                    on: mc.switchable && mc.onFor(ent.modelData)
                    switchEnabled: mc.switchEnabledFor(ent.modelData)
                    switchTip: mc.switchable ? mc.switchTipFor(ent.modelData) : ""
                    glyphOn: mc.glyphOn
                    glyphOff: mc.glyphOff
                    height: mc.chipH
                    width: mc.chipW
                    onClicked: mc.pick(ent.modelData)
                    onSwitched: want => mc.switched(ent.modelData, want)
                }
            }
        }
    }

    // focus ring around the chips while the strip has the keyboard focus
    Rectangle {
        x: -3; y: -3
        width: chips.width + 6; height: chips.height + 6
        radius: Theme.inner(Theme.radiusPage, -3)
        color: Theme.alpha(Theme.fg, 0)
        border.width: 1
        border.color: Theme.alpha(Theme.fg, 0.5)
        visible: mc.activeFocus
    }
    // the strip's end: "All" (switchable pages), then the page actions
    RowLayout {
        id: tail
        spacing: Theme.controlGap
        anchors.right: parent.right
        y: mc.stack ? chips.height + Theme.gapRow : 0
        height: mc.chipH
        LabelSwitch {
            visible: mc.allShown
            objectName: mc.objectName + "-all"
            Layout.preferredHeight: mc.chipH
            icon: mc.allIcon
            label: "All"
            checked: mc.allOn
            tip: mc.allTip
            glyphOn: mc.glyphOn
            glyphOff: mc.glyphOff
            onToggled: want => mc.allSwitched(want)
        }
        RowLayout { id: actions; visible: implicitWidth > 0; spacing: Theme.controlGap }
    }
}
