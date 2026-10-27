pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

// Settings -> Bar: per-monitor look and layout editor (BarWidgets). The MonitorChooser only picks whose bar is edited
// (the shared Settings pick) and links neighbours; bar on / off per monitor lives on Settings > Monitors ("On / off"). Drag widget chips between
// Left / Center / Right / Hidden to move, reorder or hide them; the eye button hides / shows a chip in place.
// The control center chip can be moved but not hidden.
Item {
    id: ed
    implicitHeight: col.implicitHeight

    // ---- which monitor ----
    readonly property var sel: Monitors.selected
    readonly property bool barOn: sel ? BarConfig.enabled(sel) : false
    readonly property string look: Presets.barLookOf(sel)
    // the wallpaper behind the picked monitor's bar: what the look previews draw on
    readonly property string wallpaper: LockWallpapers.stillFor(sel)
    readonly property string key: sel ? BarWidgets.keyOf(sel) : ""
    readonly property var lay: BarWidgets.layoutFor(key)
    readonly property bool own: BarWidgets.hasOwn(key)
    // monitors linked to the picked one (BarConfig.links): they share on/off, edge and this layout, so every edit below goes to all of them
    readonly property var group: BarConfig.groupKeys(key)
    readonly property var groupScreens: group.map(k => BarConfig.screenFor(k)).filter(s => s !== null)
    readonly property bool linkedGroup: groupScreens.length > 1
    function toggleLink(i) {
        const a = Monitors.ordered[i], b = Monitors.ordered[i + 1]
        if (!a || !b) return
        const ka = BarConfig.keyOf(a), kb = BarConfig.keyOf(b)
        if (BarConfig.linked(ka, kb)) { BarConfig.unlink(ka, kb); return }
        // linking: the group takes the picked monitor's on/off, edge and layout (the left card's when it is on neither side)
        const from = BarConfig.groupKeys(ka).concat(BarConfig.groupKeys(kb)).indexOf(key) >= 0 ? key : ka
        BarConfig.link(ka, kb, from)
        BarWidgets.syncGroup(from)
    }
    function screenTitle(s) { return Monitors.title(s) }

    // ---- drag state (the proxy below follows the pointer; DropAreas are the section boxes) ----
    property string dragId: ""
    readonly property bool dragging: dragId !== ""
    function startDrag(id, chip, px, py) {
        const p = chip.mapToItem(ed, 0, 0)
        proxy.width = chip.width
        proxy.text = BarWidgets.info(id).title
        proxy.icon = BarWidgets.info(id).icon
        proxy.Drag.hotSpot.x = px - p.x
        proxy.Drag.hotSpot.y = py - p.y
        proxy.x = p.x; proxy.y = p.y
        dragId = id
    }
    function dragTo(px, py) { proxy.x = px - proxy.Drag.hotSpot.x; proxy.y = py - proxy.Drag.hotSpot.y }
    function endDrag() { if (dragging) proxy.Drag.drop(); dragId = "" }

    // concentric radii: monitor chips, section boxes and the preview are page-level (Theme.radiusPage);
    // chips sit 8 px inside a section box; preview minis sit 6 px inside the preview strip (like bar chips)
    readonly property int chipRadius: Theme.inner(Theme.radiusPage, 8)

    component Mini: Rectangle {
        property string glyph: ""
        width: 26; height: 22
        radius: Theme.inner(Theme.radiusPage, 6)
        color: Theme.itemFill
        Icon { anchors.centerIn: parent; text: parent.glyph; font.pixelSize: Theme.iconSm; color: Theme.fgDim }
    }

    component Mb: Btn {
        implicitWidth: 22; implicitHeight: 22
        outerRadius: Theme.inner(Theme.radiusPage, 8)    // inside a 34 px chip (chipRadius)
        inset: 6
        icon: true
        visible: enabledLook
    }

    // one chip in a section box: drag handle + icon + title + eye (hide / show)
    component WChip: Rectangle {
        id: chip
        required property string wid
        required property string section
        property var editor
        readonly property var w: BarWidgets.info(wid)
        // an L1 item: fill only, one ink; a hidden chip is muted
        readonly property bool hidden: section === "hidden"
        implicitHeight: 34
        radius: editor.chipRadius
        color: chipGlow.hovered ? Theme.itemHover : Theme.itemFill
        opacity: editor.dragId === wid ? 0.35 : 1

        HoverGlow { id: chipGlow; area: chipArea; radius: chip.radius }
        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: chip.editor.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property real sx: 0
            property real sy: 0
            onPressed: mouse => { const p = mapToItem(chip.editor, mouse.x, mouse.y); sx = p.x; sy = p.y }
            onPositionChanged: mouse => {
                if (!pressed) return
                const p = mapToItem(chip.editor, mouse.x, mouse.y)
                if (!chip.editor.dragging && Math.abs(p.x - sx) + Math.abs(p.y - sy) > 6) chip.editor.startDrag(chip.wid, chip, sx, sy)
                if (chip.editor.dragging) chip.editor.dragTo(p.x, p.y)
            }
            onReleased: chip.editor.endDrag()
            onCanceled: chip.editor.dragId = ""
        }
        RowLayout {
            anchors { fill: parent; leftMargin: Theme.gapRow; rightMargin: Theme.controlGap }
            spacing: Theme.controlGap
            Icon { text: Icons.grip; font.pixelSize: Theme.iconSm; color: Theme.muted }
            Icon { text: chip.w.icon; font.pixelSize: Theme.iconMd; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: Theme.iconLg; color: chip.hidden ? Theme.muted : Theme.fg }
            Label { text: chip.w.title; Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: Theme.fontSmall; color: chip.hidden ? Theme.muted : Theme.fg }
            Mb {
                text: chip.hidden ? Icons.eye : Icons.eyeOff
                enabledLook: chip.wid !== BarWidgets.pinnedId        // the control center can't be hidden
                onClicked: chip.section === "hidden" ? BarWidgets.show(chip.editor.key, chip.wid) : BarWidgets.hide(chip.editor.key, chip.wid)
            }
        }
    }

    // a drop target holding one section's chips; the accent line shows where a dropped chip lands
    component SectionBox: Rectangle {
        id: box
        required property string section
        required property string title
        property var editor
        readonly property var ids: editor.lay[section]
        readonly property bool horizontal: section === "hidden"
        property int dropIndex: -1

        implicitHeight: content.implicitHeight + 16
        radius: Theme.radiusPage
        color: drop.containsDrag ? Theme.alpha(Theme.accent, 0.10) : Theme.alpha(Theme.fg, 0.03)
        border.width: 1
        border.color: drop.containsDrag ? Theme.alpha(Theme.accent, 0.8) : Theme.alpha(Theme.overlay, 0.45)

        function indexAt(x, y) {
            if (horizontal) return -1                        // hidden is unordered: append
            const p = list.mapFromItem(box, x, y)
            let i = 0
            for (const c of list.children) if (c.wid !== undefined && c.y + c.height / 2 < p.y) i++
            return i
        }

        DropArea {
            id: drop
            anchors.fill: parent
            keys: ["barwidget"]
            onPositionChanged: d => box.dropIndex = box.indexAt(d.x, d.y)
            onExited: box.dropIndex = -1
            onDropped: d => {
                BarWidgets.move(box.editor.key, box.editor.dragId, box.section, box.indexAt(d.x, d.y))
                box.dropIndex = -1
                d.accept()
            }
        }

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                Label { text: box.title.toUpperCase(); font.pixelSize: Theme.fontCaption; font.bold: true; font.letterSpacing: 1.2; color: Theme.fgDim; Layout.fillWidth: true }
                Label { text: box.ids.length; font.pixelSize: Theme.fontCaption; color: Theme.muted }
            }
            Item {
                Layout.fillWidth: true
                implicitHeight: box.horizontal ? flow.implicitHeight : Math.max(34, list.implicitHeight)
                Column {
                    id: list
                    visible: !box.horizontal
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: box.horizontal ? [] : box.ids
                        WChip { required property string modelData; wid: modelData; section: box.section; editor: box.editor; width: list.width }
                    }
                }
                Label {
                    visible: !box.horizontal && box.ids.length === 0
                    anchors.centerIn: parent
                    text: "drop here"; color: Theme.muted; font.pixelSize: Theme.fontCaption
                }
                Flow {
                    id: flow
                    visible: box.horizontal
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: box.horizontal ? box.ids : []
                        WChip { required property string modelData; wid: modelData; section: box.section; editor: box.editor; width: 200 }
                    }
                    Label { visible: box.ids.length === 0; text: "drop here"; color: Theme.muted; font.pixelSize: Theme.fontCaption; height: 34 }
                }
                Rectangle {                   // insertion marker
                    visible: drop.containsDrag && !box.horizontal
                    x: 0; width: parent.width; height: 2
                    radius: box.editor.chipRadius > 0 ? 1 : 0
                    color: Theme.accent
                    y: {
                        const kids = []
                        for (const c of list.children) if (c.wid !== undefined) kids.push(c)
                        const i = Math.max(0, box.dropIndex)
                        if (kids.length === 0) return 0
                        return i < kids.length ? kids[i].y - 4 : kids[kids.length - 1].y + kids[kids.length - 1].height + 2
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 12


        // ---- monitors: the chooser picks the bar edited below (on / off: Settings > Monitors) ----
        MonitorChooser {
            objectName: "bar-monitors"
            screens: Monitors.ordered                   // toggleLink indexes the same list
            linkable: true
            linkedAt: i => Monitors.ordered[i + 1] ? BarConfig.linked(BarConfig.keyOf(Monitors.ordered[i]), BarConfig.keyOf(Monitors.ordered[i + 1])) : false
            linkTip: i => (linkedAt(i) ? "Unlink " : "Link ") + ed.screenTitle(Monitors.ordered[i]) + " and " + ed.screenTitle(Monitors.ordered[i + 1])
            onLinkToggled: i => ed.toggleLink(i)
            groupedFor: s => ed.group.indexOf(BarConfig.keyOf(s)) >= 0
            subtitleFor: s => BarConfig.enabled(s) ? "" : "no bar"
            Btn {
                objectName: "btn-bar-monitors"
                text: "On / off"
                outerRadius: Theme.radiusPage; inset: 9; implicitHeight: 26
                onClicked: Popups.settingsRequest("open", "monitors")
            }
        }

        // ---- bar look of the picked monitor (bars.json floating / transparentFlush; linked monitors share it) ----
        SectionHead {
            Layout.topMargin: 6
            title: "Look"
            detail: ed.barOn ? (ed.linkedGroup ? "linked" : "") : "bar off"
            Icon { visible: !ed.barOn; text: Icons.lock; font.pixelSize: 11; color: Theme.yellow }
        }
        PresetCards {
            id: lookCards
            Layout.fillWidth: true
            objectPrefix: "barlook"
            model: Presets.barLook
            current: ed.look
            enabled: ed.barOn
            opacity: ed.barOn ? 1 : 0.45
            previewHeight: Math.round(cardW * 9 / 16)
            preview: BarLookSample {
                wallpaper: ed.wallpaper
                edge: ed.sel ? BarConfig.edge(ed.sel) : "top"
                contrast: ed.sel ? BarConfig.contrast(ed.sel) : "auto"
            }
            onPicked: id => Presets.applyBarLook(ed.sel, id)
        }
        ChoiceRow {
            title: "Edge"
            titleWidth: 120
            values: ["top", "bottom"]
            labels: ["Top", "Bottom"]
            objectNames: ["bar-edge-top", "bar-edge-bottom"]
            segWidth: 70
            current: ed.sel ? BarConfig.edge(ed.sel) : "top"
            enabled: ed.barOn
            opacity: ed.barOn ? 1 : 0.45
            onPicked: v => { if (ed.sel && ed.barOn) BarConfig.set(ed.sel, "edge", v) }
        }
        ChoiceRow {
            id: ctrRow
            readonly property string mode: ed.sel ? BarConfig.contrast(ed.sel) : "auto"
            visible: ed.look === "transparent"
            title: "Text"
            titleWidth: 120
            values: BarConfig.contrastModes
            labels: ["Auto", "Dark", "Light", "Theme"]
            objectNames: ["bar-text-auto", "bar-text-dark", "bar-text-light", "bar-text-off"]
            segWidth: 70
            current: mode
            hint: ""
            onPicked: v => { if (ed.sel && ed.barOn) BarConfig.set(ed.sel, "contrast", v) }
        }
        SettingRow {
            visible: ed.look !== "transparent"
            title: "Text"
            titleWidth: 120
            opacity: 0.55
            Label { text: "Theme"; color: Theme.fgDim; font.pixelSize: Theme.fontSmall }
            InfoTip { icon: Icons.lock; text: "Text follows the theme. Pick Transparent to adapt it to the wallpaper." }
        }
        AdvancedFold {
            objectName: "fold-bar"
            label: "Customise…"
            detail: ""
            SettingRow {
                title: "Reserved area"
                titleWidth: 120
                opacity: ed.barOn ? 1 : 0.45
                Toggle {
                    checked: ed.sel ? BarConfig.respectReserved(ed.sel) : false
                    enabledLook: ed.barOn
                    onToggled: want => { if (ed.sel && ed.barOn) BarConfig.set(ed.sel, "respectReserved", want) }
                }
                InfoTip { objectName: "tip-reserved"; text: "Sit inside the reserved margins, not at the screen edge." }
                Item { Layout.fillWidth: true }
            }
            // padding of a docked transparent bar: Auto = 3 x the window gap, or a manual total
            SettingRow {
                id: padRow
                readonly property bool active: ed.sel ? BarConfig.flushMode(ed.sel) : false
                readonly property bool auto: ed.sel ? BarConfig.flushPadding(ed.sel) === "auto" : true
                readonly property int total: ed.sel ? BarConfig.padTotal(ed.sel) : 0
                title: "Bar padding"
                titleWidth: 120
                opacity: active ? 1 : 0.45
                Segmented {
                    values: [true, false]
                    labels: ["Auto", "Manual"]
                    objectNames: ["btn-pad-auto", "btn-pad-manual"]
                    current: padRow.auto
                    enabledLook: padRow.active
                    outerRadius: Theme.radiusPage; inset: 9
                    segHeight: 26
                    segWidth: 70
                    onPicked: v => { if (padRow.active && ed.sel) BarConfig.set(ed.sel, "flushPadding", v ? "auto" : padRow.total) }
                }
                Slider {
                    wheel: false
                    objectName: "slider-pad"
                    Layout.fillWidth: true
                    dim: padRow.auto || !padRow.active
                    value: padRow.total / BarConfig.flushPadManualMax
                    onMoved: v => { if (padRow.active && ed.sel) BarConfig.set(ed.sel, "flushPadding", Math.round(v * BarConfig.flushPadManualMax / 2) * 2) }
                }
                Label { text: padRow.total + " px"; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight; color: Theme.fg; font.pixelSize: Theme.fontSmall }
                InfoTip { icon: padRow.active ? Icons.info : Icons.lock; text: "Transparent look only. Auto is 3x the window gap; Manual is 0 to 48 px." }
            }
            SettingRow {
                id: sensRow
                readonly property bool active: ed.barOn && ctrRow.mode === "auto" && ed.look === "transparent"
                readonly property real sens: ed.sel ? BarConfig.contrastSens(ed.sel) : 50
                title: "Switch point"
                titleWidth: 120
                opacity: active ? 1 : 0.45
                Slider {
                    wheel: false
                    objectName: "slider-contrast-sens"
                    Layout.fillWidth: true
                    dim: !sensRow.active
                    value: sensRow.sens / 100
                    onMoved: v => { if (sensRow.active && ed.sel) BarConfig.set(ed.sel, "contrastSens", Math.round(v * 100)) }
                }
                Label { text: sensRow.sens < 40 ? "light text" : sensRow.sens > 60 ? "dark text" : "balanced"; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; color: Theme.fg; font.pixelSize: Theme.fontSmall }
                InfoTip { icon: sensRow.active ? Icons.info : Icons.lock; text: "How readily dark text is picked on a mid-tone wallpaper. Needs Transparent look with Auto text." }
            }
            SettingRow {
                id: fillRow
                readonly property bool active: ed.barOn && ed.look === "transparent"
                readonly property real fill: ed.sel ? BarConfig.hoverFill(ed.sel) : 35
                title: "Hover fill"
                titleWidth: 120
                opacity: active ? 1 : 0.45
                Slider {
                    wheel: false
                    objectName: "slider-hover-fill"
                    Layout.fillWidth: true
                    dim: !fillRow.active
                    value: fillRow.fill / 100
                    onMoved: v => { if (fillRow.active && ed.sel) BarConfig.set(ed.sel, "hoverFill", Math.round(v * 100)) }
                }
                Label { text: fillRow.fill + " %"; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; color: Theme.fg; font.pixelSize: Theme.fontSmall }
                InfoTip { icon: fillRow.active ? Icons.info : Icons.lock; text: "Fill of a hovered chip when the bar has no backdrop. Transparent look only." }
            }
        }

        // ---- layout of the picked monitor: actions, preview, editor ----
        SectionHead {
            Layout.topMargin: 6
            title: "Layout"
            detail: (ed.linkedGroup ? "linked · " : "") + (ed.own ? "own" : "default")
            InfoTip { objectName: "tip-layout"; text: "Drag chips between columns to move or reorder, onto Hidden to hide (or use the eye). The control center chip can't be hidden, and the last bar can't be turned off: it is the way back into Settings." }
            Btn { inset: 18; implicitHeight: 24; text: "Reset"; enabledLook: ed.own; onClicked: if (ed.own) BarWidgets.reset(ed.key) }
        }
        // "Copy from <other monitor>": a wrapping row of its own (with 3 monitors the names do not fit next to the head at 920 px)
        Flow {
            visible: copyRep.count > 0
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                id: copyRep
                model: Monitors.ordered.filter(s => ed.group.indexOf(BarConfig.keyOf(s)) < 0)   // copying from a linked monitor would change nothing
                Btn {
                    required property var modelData
                    inset: 18                 // page level, like the monitor chips (radiusPage)
                    implicitHeight: 24
                    text: "Copy from " + ed.screenTitle(modelData)
                    onClicked: BarWidgets.copyFrom(ed.key, BarWidgets.keyOf(modelData))
                }
            }
        }
        RowLayout {
            visible: ed.sel ? !BarConfig.enabled(ed.sel) : false
            spacing: 6
            Icon { text: Icons.lock; font.pixelSize: 11; color: Theme.yellow }
            Label { text: "bar off"; color: Theme.fgDim; font.pixelSize: Theme.fontCaption }
            InfoTip { text: "The layout is kept for when the bar is back on." }
        }

        // ---- preview ----
        Rectangle {
            id: preview
            Layout.fillWidth: true
            implicitHeight: 34
            radius: BarConfig.floating(ed.sel) ? Theme.radiusPage : 0     // docked bar = square, like the real one
            color: Theme.alpha(Theme.bg, Theme.barFill)
            border.width: 1
            border.color: Theme.alpha(Theme.overlay, 0.55)
            Row {
                id: pvLeft
                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                spacing: 3
                Repeater { model: ed.lay.left; Mini { required property string modelData; glyph: BarWidgets.info(modelData).icon } }
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(pvLeft.x + pvLeft.width + 6, Math.min((preview.width - width) / 2, pvRight.x - 6 - width))
                spacing: 3
                Repeater { model: ed.lay.center; Mini { required property string modelData; glyph: BarWidgets.info(modelData).icon } }
            }
            Row {
                id: pvRight
                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                spacing: 3
                Repeater { model: ed.lay.right; Mini { required property string modelData; glyph: BarWidgets.info(modelData).icon } }
            }
        }

        // ---- editor ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            SectionBox { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; section: "left";   title: "Left";   editor: ed }
            SectionBox { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; section: "center"; title: "Center"; editor: ed }
            SectionBox { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; section: "right";  title: "Right";  editor: ed }
        }
        SectionBox { Layout.fillWidth: true; section: "hidden"; title: "Hidden"; editor: ed }


    }

    // drag proxy: floats above everything while a chip is being dragged
    Rectangle {
        id: proxy
        property string text: ""
        property string icon: ""
        visible: ed.dragging
        z: 100
        height: 34
        radius: ed.chipRadius
        color: Theme.alpha(Theme.accent, 0.30)
        border.width: 1
        border.color: Theme.accent
        Drag.active: ed.dragging
        Drag.keys: ["barwidget"]
        Row {
            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: Theme.padSm }
            spacing: Theme.gapRow
            Icon { text: proxy.icon; font.pixelSize: Theme.iconMd; color: Theme.accent }
            Label { text: proxy.text; font.pixelSize: Theme.fontSmall; color: Theme.accent }
        }
    }
}
