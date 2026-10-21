import QtQuick
import QtQuick.Layouts
import Quickshell

// Settings -> Bar: per-monitor layout editor (BarWidgets). Pick a monitor, then drag widget chips between
// Left / Center / Right / Hidden to move, reorder or hide them; the eye button hides / shows a chip in place.
// The bell chip is fixed at the right end of every bar and can't be moved or hidden.
Item {
    id: ed
    implicitHeight: col.implicitHeight

    // ---- which monitor ----
    property string selName: (Quickshell.screens.find(s => BarConfig.enabled(s)) || Quickshell.screens[0] || { name: "" }).name
    readonly property var sel: Quickshell.screens.find(s => s.name === selName) || Quickshell.screens[0]
    readonly property string key: sel ? BarWidgets.keyOf(sel) : ""
    readonly property var lay: BarWidgets.layoutFor(key)
    readonly property bool own: BarWidgets.hasOwn(key)
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
        color: chipArea.containsMouse ? Theme.alpha(Theme.fg, 0.12) : Theme.alpha(Theme.fg, 0.06)
        border.width: 1
        border.color: section === "hidden" ? Theme.alpha(Theme.overlay, 0.5) : Theme.alpha(Theme.accent, 0.45)
        opacity: editor.dragId === wid ? 0.35 : 1

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
                enabledLook: true
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
        property bool locked: false             // the right box ends with the fixed bell chip
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
                    Rectangle {               // the bell: always the last chip on the right, can't move
                        visible: box.locked
                        width: list.width
                        height: 34
                        radius: box.editor.chipRadius
                        color: Theme.alpha(Theme.fg, 0.03)
                        border.width: 1
                        border.color: Theme.alpha(Theme.overlay, 0.4)
                        RowLayout {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 10 }
                            spacing: 6
                            Icon { text: "\uf023"; font.pixelSize: 11; color: Theme.muted }
                            Icon { text: "\uf0f3"; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 18; color: Theme.fgDim }
                            Label { text: "Control center"; Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: Theme.fontSmall; color: Theme.fgDim }
                            Label { text: "fixed"; font.pixelSize: Theme.fontCaption; color: Theme.muted }
                        }
                    }
                }
                Label {
                    visible: !box.horizontal && box.ids.length === 0 && !box.locked
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
        Flow {
            id: monFlow
            Layout.fillWidth: true
            spacing: 10
            readonly property int cols: Math.max(1, Math.min(Quickshell.screens.length, Math.floor((width + spacing) / (260 + spacing))))
            readonly property real cardW: (width - (cols - 1) * spacing) / cols
            Repeater {
                model: Quickshell.screens
                Rectangle {
                    id: mon
                    required property var modelData
                    readonly property bool on: BarConfig.enabled(modelData)
                    readonly property bool onlyOne: on && BarConfig.enabledCount <= 1   // the last bar is the way back into Settings
                    readonly property bool picked: modelData.name === ed.selName
                    readonly property string edge: BarConfig.edge(modelData)
                    width: monFlow.cardW
                    height: 70
                    radius: Theme.radiusPage
                    color: picked ? Theme.alpha(Theme.accent, 0.12) : monArea.containsMouse ? Theme.alpha(Theme.fg, 0.08) : Theme.alpha(Theme.fg, 0.04)
                    border.width: 1
                    border.color: picked ? Theme.alpha(Theme.accent, 0.85) : Theme.alpha(Theme.overlay, 0.45)

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

        // ---- layout of the picked monitor: actions, preview, editor ----
        SectionHead {
            Layout.topMargin: 6
            title: "Layout · " + (ed.sel ? ed.screenTitle(ed.sel) : "")
            detail: ed.own ? "own layout" : "default layout"
            Repeater {
                model: Quickshell.screens.filter(s => s.name !== ed.selName)
                Btn {
                    required property var modelData
                    inset: 18                 // page level, like the monitor cards (radiusPage)
                    implicitHeight: 24
                    text: "Copy from " + ed.screenTitle(modelData)
                    onClicked: BarWidgets.copyFrom(ed.key, BarWidgets.keyOf(modelData))
                }
            }
            Btn { inset: 18; implicitHeight: 24; text: "Reset"; enabledLook: ed.own; onClicked: if (ed.own) BarWidgets.reset(ed.key) }
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
            radius: Theme.barFloating ? Theme.radiusPage : 0     // docked bar = square, like the real one
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
                Mini { glyph: "\uf0f3"; color: Theme.alpha(Theme.accent, 0.18) }
            }
        }

        // ---- editor ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            SectionBox { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; section: "left";   title: "Left";   editor: ed }
            SectionBox { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; section: "center"; title: "Center"; editor: ed }
            SectionBox { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; section: "right";  title: "Right";  editor: ed; locked: true }
        }
        SectionBox { Layout.fillWidth: true; section: "hidden"; title: "Hidden"; editor: ed }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Theme.muted
            font.pixelSize: Theme.fontCaption
            text: "Drag chips between the columns to move or reorder them, onto Hidden to hide them (or use the eye). Monitors without their own layout use the default one; changes apply to the bar right away. The last bar can't be turned off: its bell chip is the way back into Settings."
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
