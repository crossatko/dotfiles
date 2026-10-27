pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// The one monitor chooser of the Settings pages that edit a single monitor's settings (Wallpaper, Bar, Lock screen,
// Desktop clock, Look & feel > Shape): a strip of monitor chips in Monitors.ordered order (primary first). A chip =
// the monitor's wallpaper still in its real aspect + its model (connector when it has none) over the connector and an
// optional page status (`subtitleFor`), the PrimaryTag on the primary and an optional accent glyph (`markFor`, e.g. the
// palette source). The choice is the shared Settings pick (Monitors.selected / Monitors.select): switching on one page
// carries to the others while Settings is open. Hidden with fewer than two monitors (nothing to choose).
// Options: `allEntry` = an "All" chip first (picked("") ; the page owns `allCurrent`); `linkable` = a MonitorLinkButton
// between neighbouring chips (`linkedAt(i)` / `linkToggled(i)`, `groupedFor(screen)` = linked to the current one: accent
// outline without the fill). Trailing items (page actions) go inside, at the right end; they move under the chips when
// the row is too narrow. Keyboard: Tab focuses the strip, Left / Right pick the neighbour; link buttons take Tab + Space.
// On / off per monitor is never here: that lives on Settings > Monitors. objectNames `monitor-chip-<conn>`, `monitor-chip-all`,
// `monitor-link-<i>`.
Item {
    id: mc
    property var screens: Monitors.ordered.filter(s => s.width > 0 && s.height > 0)
    property string current: Monitors.selected ? Monitors.selected.name : ""
    property bool shared: true                      // picking a chip also moves the shared Settings pick
    property bool allEntry: false
    property bool allCurrent: false
    property string allLabel: "All"
    property bool linkable: false
    property var linkedAt: function (i) { return false }
    property var linkTip: function (i) { return "" }
    property var groupedFor: function (s) { return false }
    property var subtitleFor: function (s) { return "" }
    property var markFor: function (s) { return "" }   // an Icons glyph after the name, "" = none
    property var markTipFor: function (s) { return "" }
    property var thumbFor: function (s) { return LockWallpapers.stillFor(s) }
    signal picked(string name)                      // "" = the All chip
    signal linkToggled(int i)
    default property alias trailing: tail.data

    readonly property bool shown: screens.length > 1
    readonly property int chipH: 40                  // two lines (fontSmall + fontCaption) + padding
    readonly property int chipMax: 240               // widest a chip gets (long model names elide)
    readonly property int thumbH: 18                 // the wallpaper still; its width follows the monitor's aspect
    readonly property int linkSize: 22               // MonitorLinkButton between two chips
    readonly property var entries: (allEntry ? [null] : []).concat(screens)
    readonly property int linkCount: linkable ? Math.max(0, screens.length - 1) : 0
    readonly property real fixedW: linkCount * (linkSize + 2 * Theme.gapTight) + (entries.length - 1 - linkCount) * Theme.controlGap
    readonly property bool stack: tail.implicitWidth > 0 && chipsNatural + Theme.pad + tail.implicitWidth > width
    readonly property real chipsAvail: (stack || tail.implicitWidth === 0 ? width : width - tail.implicitWidth - Theme.pad) - fixedW
    // the chips' natural width (without the cap; naturalWidth never depends on `stack`, so no loop)
    readonly property real chipsNatural: {
        void rep.count
        let w = fixedW
        for (let i = 0; i < rep.count; i++) { const e = rep.itemAt(i); if (e) w += e.chip.naturalWidth }   // qmllint disable missing-property
        return w
    }
    // the widest a chip may get: chips that need less than an equal share keep their width, the rest share what is left
    readonly property real chipCap: {
        void rep.count
        const n = []
        for (let i = 0; i < rep.count; i++) { const e = rep.itemAt(i); if (e) n.push(e.chip.naturalWidth) }   // qmllint disable missing-property
        n.sort((a, b) => a - b)
        let left = chipsAvail
        for (let i = 0; i < n.length; i++) {
            const share = left / (n.length - i)
            if (n[i] > share) return Math.floor(share)
            left -= n[i]
        }
        return chipMax
    }

    function isCurrent(s) { return s === null ? allEntry && allCurrent : !allCurrent && s.name === current }
    function pick(s) {
        if (s !== null && shared) Monitors.select(s.name)
        picked(s === null ? "" : s.name)
    }
    function step(d) {
        const i = entries.findIndex(s => isCurrent(s))
        const n = Math.max(0, Math.min(entries.length - 1, (i < 0 ? 0 : i + d)))
        if (n !== i) pick(entries[n])
    }

    visible: shown
    implicitHeight: shown ? (stack ? chipH + Theme.gapRow + tail.implicitHeight : Math.max(chipH, tail.implicitHeight)) : 0
    Layout.fillWidth: true
    activeFocusOnTab: shown
    Keys.onLeftPressed: step(-1)
    Keys.onRightPressed: step(1)
    Accessible.role: Accessible.PageTabList
    Accessible.name: "Monitor"

    // the selected chip's marker glides between the chips (as Segmented)
    GlideHighlight {
        target: { void rep.count; const i = mc.entries.findIndex(s => mc.isCurrent(s)); return i < 0 ? null : rep.itemAt(i) ? rep.itemAt(i).chip : null }   // qmllint disable missing-property
        radius: Theme.inner(Theme.radiusPage, 0)
        color: Theme.accentFill
        border.width: 1
        border.color: mc.activeFocus ? Theme.accent : Theme.accentEdge
    }
    Row {
        id: chips
        y: mc.stack ? 0 : Math.round((mc.implicitHeight - mc.chipH) / 2)
        spacing: 0
        Repeater {
            id: rep
            model: mc.entries
            Row {
                id: ent
                required property var modelData
                required property int index
                readonly property Item chip: chipBox
                readonly property int si: mc.allEntry ? index - 1 : index      // index among the screens (-1 = All)
                spacing: 0
                // between two entries: a link button (linkable, two screens) or a plain gap
                Item {
                    visible: ent.index > 0
                    width: lnk.visible ? mc.linkSize + 2 * Theme.gapTight : Theme.controlGap
                    height: mc.chipH
                    MonitorLinkButton {
                        id: lnk
                        visible: mc.linkable && ent.si > 0
                        objectName: "monitor-link-" + (ent.si - 1)
                        anchors.centerIn: parent
                        implicitWidth: mc.linkSize; implicitHeight: mc.linkSize
                        linked: visible && mc.linkedAt(ent.si - 1)
                        tip: visible ? mc.linkTip(ent.si - 1) : ""
                        onToggled: mc.linkToggled(ent.si - 1)
                    }
                }
                MonitorChip {
                    id: chipBox
                    screen: ent.modelData
                    allLabel: mc.allLabel
                    selected: mc.isCurrent(ent.modelData)
                    grouped: ent.modelData !== null && !selected && mc.groupedFor(ent.modelData)
                    subtitle: ent.modelData !== null ? mc.subtitleFor(ent.modelData) : ""
                    mark: ent.modelData !== null ? mc.markFor(ent.modelData) : ""
                    markTip: ent.modelData !== null ? mc.markTipFor(ent.modelData) : ""
                    thumb: ent.modelData !== null ? mc.thumbFor(ent.modelData) : ""
                    height: mc.chipH
                    maxWidth: Math.min(mc.chipMax, mc.chipCap)
                    onClicked: mc.pick(ent.modelData)
                }
            }
        }
    }

    // focus ring around the strip while it has the keyboard focus
    Rectangle {
        x: -3; y: chips.y - 3
        width: chips.width + 6; height: mc.chipH + 6
        radius: Theme.inner(Theme.radiusPage, -3)
        color: Theme.alpha(Theme.fg, 0)
        border.width: 1
        border.color: Theme.alpha(Theme.fg, 0.5)
        visible: mc.activeFocus
    }
    RowLayout {
        id: tail
        spacing: Theme.controlGap
        anchors.right: parent.right
        y: mc.stack ? mc.chipH + Theme.gapRow : Math.round((mc.implicitHeight - implicitHeight) / 2)
    }
}
