pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

// Settings -> Bar: per-monitor layout editor (BarWidgets). Pick a monitor, then drag widget chips between
// Left / Center / Right / Hidden to move, reorder or hide them; the eye button hides / shows a chip in place.
// The control center chip can be moved but not hidden.
Item {
    id: ed
    implicitHeight: col.implicitHeight

    // ---- which monitor ----
    property string selName: (Quickshell.screens.find(s => BarConfig.enabled(s)) || Quickshell.screens[0] || { name: "" }).name
    readonly property var sel: Quickshell.screens.find(s => s.name === selName) || Quickshell.screens[0]
    readonly property string key: sel ? BarWidgets.keyOf(sel) : ""
    readonly property var lay: BarWidgets.layoutFor(key)
    readonly property bool own: BarWidgets.hasOwn(key)
    // monitors linked to the picked one (BarConfig.links): they share on/off, edge and this layout, so every edit below goes to all of them
    readonly property var group: BarConfig.groupKeys(key)
    readonly property var groupScreens: group.map(k => BarConfig.screenFor(k)).filter(s => s !== null)
    readonly property bool linkedGroup: groupScreens.length > 1
    function toggleLink(i) {
        const a = Quickshell.screens[i], b = Quickshell.screens[i + 1]
        if (!a || !b) return
        const ka = BarConfig.keyOf(a), kb = BarConfig.keyOf(b)
        if (BarConfig.linked(ka, kb)) { BarConfig.unlink(ka, kb); return }
        // linking: the group takes the picked monitor's on/off, edge and layout (the left card's when it is on neither side)
        const from = BarConfig.groupKeys(ka).concat(BarConfig.groupKeys(kb)).indexOf(key) >= 0 ? key : ka
        BarConfig.link(ka, kb, from)
        BarWidgets.syncGroup(from)
    }
    function screenTitle(s) { return s.model || s.name }

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

    // concentric radii: monitor cards, section boxes and the preview are page-level (Theme.radiusPage);
    // chips sit 8 px inside a section box; preview minis sit 6 px inside the preview strip (like bar chips)
    readonly property int chipRadius: Theme.inner(Theme.radiusPage, 8)

    component Mini: Rectangle {
        property string glyph: ""
        width: 26; height: 22
        radius: Theme.inner(Theme.radiusPage, 6)
        color: Theme.alpha(Theme.fg, 0.08)
        Icon { anchors.centerIn: parent; text: parent.glyph; font.pixelSize: 12; color: Theme.fgDim }
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
        implicitHeight: 34
        radius: editor.chipRadius
        color: chipGlow.hovered ? Theme.alpha(Theme.fg, 0.12) : Theme.alpha(Theme.fg, 0.06)
        border.width: 1
        border.color: section === "hidden" ? Theme.alpha(Theme.overlay, 0.5) : Theme.alpha(Theme.accent, 0.45)
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
            anchors { fill: parent; leftMargin: 8; rightMargin: 6 }
            spacing: 6
            Icon { text: "\uf58e"; font.pixelSize: 11; color: Theme.muted }
            Icon { text: chip.w.icon; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 18; color: chip.section === "hidden" ? Theme.muted : Theme.accent }
            Label { text: chip.w.title; Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: Theme.fontSmall; color: chip.section === "hidden" ? Theme.fgDim : Theme.fg }
            Mb {
                text: chip.section === "hidden" ? "\uf06e" : "\uf070"
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
                    Label { visible: box.ids.length === 0; text: "Nothing hidden. Drop a chip here to hide it."; color: Theme.muted; font.pixelSize: Theme.fontCaption; height: 34 }
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

        // ---- monitors: one card each = bar on/off + edge; clicking a card picks the layout edited below ----
        SectionHead { title: "Monitors"; detail: BarConfig.enabledCount + " of " + Quickshell.screens.length + " with a bar" }
        MonitorCardRow {
            id: monRow
            Layout.fillWidth: true
            count: Quickshell.screens.length
            minCardW: 260
            cardH: 70
            linkedAt: i => Quickshell.screens[i + 1] ? BarConfig.linked(BarConfig.keyOf(Quickshell.screens[i]), BarConfig.keyOf(Quickshell.screens[i + 1])) : false
            linkTip: i => (linkedAt(i) ? "Unlink " : "Link ") + ed.screenTitle(Quickshell.screens[i]) + " and " + ed.screenTitle(Quickshell.screens[i + 1])
            onLinkToggled: i => ed.toggleLink(i)
            Repeater {
                model: Quickshell.screens
                Rectangle {
                    id: mon
                    required property var modelData
                    required property int index
                    readonly property bool on: BarConfig.enabled(modelData)
                    readonly property bool onlyOne: on && !BarConfig.canDisable(modelData)   // the last bar (or the last linked group with a bar) is the way back into Settings
                    readonly property bool picked: modelData.name === ed.selName
                    readonly property bool grouped: !picked && ed.group.indexOf(BarConfig.keyOf(modelData)) >= 0   // linked to the picked one
                    readonly property string edge: BarConfig.edge(modelData)
                    x: monRow.xOf(index); y: monRow.yOf(index)
                    width: monRow.cardW
                    height: monRow.cardH
                    radius: Theme.radiusPage
                    color: picked ? Theme.alpha(Theme.accent, 0.12) : grouped ? Theme.alpha(Theme.accent, 0.06) : monGlow.hovered ? Theme.alpha(Theme.fg, 0.08) : Theme.alpha(Theme.fg, 0.04)
                    border.width: 1
                    border.color: picked ? Theme.alpha(Theme.accent, 0.85) : grouped ? Theme.alpha(Theme.accent, 0.5) : Theme.alpha(Theme.overlay, 0.45)
                    // round cut-outs for the link buttons (MonitorCardRow)
                    readonly property var notches: monRow.notchesOf(index)
                    layer.enabled: notches.length > 0
                    layer.effect: NotchMask { notches: mon.notches; radius: mon.radius; borderWidth: mon.border.width; borderColor: mon.border.color }

                    HoverGlow { id: monGlow; area: monArea; radius: mon.radius }
                    // below the toggle / edge buttons, so those keep their own clicks
                    MouseArea { id: monArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ed.selName = mon.modelData.name }

                    ColumnLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12; topMargin: 9; bottomMargin: 9 }
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Icon { text: "\uf390"; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 18; color: mon.picked ? Theme.accent : Theme.fgDim; opacity: mon.on ? 1 : 0.55 }
                            Label { text: ed.screenTitle(mon.modelData); Layout.fillWidth: true; elide: Text.ElideRight; font.bold: mon.picked; color: mon.on ? Theme.fg : Theme.fgDim; opacity: mon.on ? 1 : 0.7 }
                            Label { visible: !mon.on; text: "no bar"; font.pixelSize: Theme.fontCaption; color: Theme.muted }
                            Toggle {
                                checked: mon.on
                                enabledLook: !mon.onlyOne
                                onToggled: want => BarConfig.set(mon.modelData, "enabled", want)
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label { text: mon.modelData.name + "  ·  " + mon.modelData.width + "×" + mon.modelData.height; Layout.fillWidth: true; Layout.leftMargin: 26; elide: Text.ElideRight; font.pixelSize: Theme.fontCaption; color: Theme.muted }
                            Segmented {
                                values: ["top", "bottom"]
                                labels: ["Top", "Bottom"]
                                current: mon.on ? mon.edge : ""
                                enabledLook: mon.on
                                outerRadius: Theme.radiusPage
                                inset: 9
                                segHeight: 22
                                segWidth: 58
                                onPicked: v => BarConfig.set(mon.modelData, "edge", v)
                            }
                        }
                    }
                }
            }
        }

        // ---- backdrop of the picked monitor's bar (linked monitors share it, like on/off and edge) ----
        // ---- docked or floating, per bar (bars.json `floating`; linked monitors share it) ----
        SectionHead {
            Layout.topMargin: 6
            title: "Style · " + (ed.linkedGroup ? ed.groupScreens.map(s => ed.screenTitle(s)).join(" + ") : ed.sel ? ed.screenTitle(ed.sel) : "")
        }
        SettingRow {
            title: "Bar mode"
            titleWidth: 120
            opacity: ed.sel && BarConfig.enabled(ed.sel) ? 1 : 0.45
            Segmented {
                values: [true, false]
                labels: ["Floating", "Docked"]
                objectNames: ["btn-floating", "btn-docked"]
                current: ed.sel ? BarConfig.floating(ed.sel) : false
                enabledLook: ed.sel ? BarConfig.enabled(ed.sel) : false
                inset: 18
                segHeight: 24
                segWidth: 78
                onPicked: v => { if (ed.sel && BarConfig.enabled(ed.sel)) BarConfig.set(ed.sel, "floating", v) }
            }
            Label {
                text: ed.sel && BarConfig.floating(ed.sel) ? "gap to the edges, rounded" : "flush, square"
                color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true; elide: Text.ElideRight
            }
        }
        SettingRow {
            title: "Reserved area"
            titleWidth: 120
            opacity: ed.sel && BarConfig.enabled(ed.sel) ? 1 : 0.45
            Toggle {
                checked: ed.sel ? BarConfig.respectReserved(ed.sel) : false
                enabledLook: ed.sel ? BarConfig.enabled(ed.sel) : false
                onToggled: want => { if (ed.sel && BarConfig.enabled(ed.sel)) BarConfig.set(ed.sel, "respectReserved", want) }
            }
            Label {
                text: "inside the reserved margins, not at the screen edge"
                color: Theme.muted; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true; elide: Text.ElideRight
            }
        }
        SectionHead {
            Layout.topMargin: 6
            title: "Backdrop · " + (ed.linkedGroup ? ed.groupScreens.map(s => ed.screenTitle(s)).join(" + ") : ed.sel ? ed.screenTitle(ed.sel) : "")
            detail: "transparent when flush"
            Toggle {
                checked: ed.sel ? BarConfig.transparentFlush(ed.sel) : false
                enabledLook: ed.sel ? BarConfig.enabled(ed.sel) : false
                onToggled: want => { if (ed.sel) BarConfig.set(ed.sel, "transparentFlush", want) }
            }
        }
        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Theme.muted
            font.pixelSize: Theme.fontCaption
            text: "When on, the bar draws no glass, fill, border or blur while it sits flush with the screen edge (docked bar, or compacted by a maximized window); the chips stay. A floating bar looks as usual. With a docked bar the padding below also applies."
        }

        // padding of the bar in that mode (docked + transparent when flush): Auto = 3 x the window gap, or a manual total
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
                inset: 18
                segHeight: 24
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
        }
        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Theme.muted
            font.pixelSize: Theme.fontCaption
            text: "Total space above and below the chips while the backdrop is gone (docked bar). Auto is three times the gap between windows (4 to 16 px per side); Manual is 0 to 48 px. The bar is chip height plus this, windows start right at its edge."
        }

        // ---- layout of the picked monitor: actions, preview, editor ----
        SectionHead {
            Layout.topMargin: 6
            title: "Layout · " + (ed.linkedGroup ? ed.groupScreens.map(s => ed.screenTitle(s)).join(" + ") : ed.sel ? ed.screenTitle(ed.sel) : "")
            detail: (ed.linkedGroup ? "linked, " : "") + (ed.own ? "own layout" : "default layout")
            Btn { inset: 18; implicitHeight: 24; text: "Reset"; enabledLook: ed.own; onClicked: if (ed.own) BarWidgets.reset(ed.key) }
        }
        // "Copy from <other monitor>": a wrapping row of its own (with 3 monitors the names do not fit next to the head at 920 px)
        Flow {
            visible: copyRep.count > 0
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                id: copyRep
                model: Quickshell.screens.filter(s => ed.group.indexOf(BarConfig.keyOf(s)) < 0)   // copying from a linked monitor would change nothing
                Btn {
                    required property var modelData
                    inset: 18                 // page level, like the monitor cards (radiusPage)
                    implicitHeight: 24
                    text: "Copy from " + ed.screenTitle(modelData)
                    onClicked: BarWidgets.copyFrom(ed.key, BarWidgets.keyOf(modelData))
                }
            }
        }
        Label {
            visible: ed.sel ? !BarConfig.enabled(ed.sel) : false
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Theme.fgDim
            font.pixelSize: Theme.fontCaption
            text: "The bar is off on this monitor. The layout is kept and used again when you turn it back on."
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

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Theme.muted
            font.pixelSize: Theme.fontCaption
            text: "Drag chips between the columns to move or reorder them, onto Hidden to hide them (or use the eye). Monitors without their own layout use the default one; changes apply to the bar right away. Linked monitors (the chain button between two cards) share one layout, one on/off switch and one edge: an edit on any of them applies to all. The control center chip can be moved like the others but not hidden, and the last bar can't be turned off: the control center is the way back into Settings."
        }

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
            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10 }
            spacing: 8
            Icon { text: proxy.icon; font.pixelSize: 13; color: Theme.accent }
            Label { text: proxy.text; font.pixelSize: Theme.fontSmall }
        }
    }
}
