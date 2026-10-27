pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Vacuum card in the Home Assistant popup: header (name, status, battery), Start / Pause / Dock, a room
// grid (multi-select, map order), a cycles control and the Clean button ("Clean 2 rooms · 2×" / "Clean all").
// Suction and mop settings are deliberately never touched.
// State and service mapping live in HomeAssistant.qml (cleanRooms / cleanAll); room selection
// and cycles are local to the popup. Like HaEntity, nothing flips by itself: the next refresh shows the truth.
Rectangle {
    id: vac

    property string entityId: ""
    property bool editing: false

    readonly property var e: HomeAssistant.byId[entityId] || null
    readonly property var a: e && e.attributes ? e.attributes : ({})
    readonly property string st: e ? e.state : "unavailable"
    readonly property bool unavailable: st === "unavailable" || st === "unknown"
    readonly property bool hiddenNow: HomeAssistant.isHidden(entityId)
    readonly property bool busy: HomeAssistant.busy[entityId] === true
    readonly property bool cleaning: st === "cleaning"
    readonly property string title: a.friendly_name || entityId
    readonly property string area: HomeAssistant.areas[entityId] || ""
    readonly property int battery: HomeAssistant.lastUpdate >= 0 ? HomeAssistant.batteryOf(entityId) : -1
    readonly property string status: HomeAssistant.lastUpdate >= 0 ? HomeAssistant.statusOf(entityId) : ""
    readonly property bool charging: /charg/i.test(status)

    readonly property var rooms: HomeAssistant.vacRooms && HomeAssistant.lastUpdate >= 0 ? HomeAssistant.roomsOf(entityId) : []
    readonly property string repeatEntity: HomeAssistant.devices && HomeAssistant.lastUpdate >= 0 ? HomeAssistant.repeatEntityOf(entityId) : ""
    readonly property bool hasCycles: rooms.length > 0 || repeatEntity !== ""

    property var selRooms: []
    property int cycles: 1
    function pickRoom(id) {
        const i = selRooms.indexOf(id)
        selRooms = i >= 0 ? selRooms.filter(x => x !== id) : selRooms.concat([id])
    }
    function clean() {
        if (selRooms.length > 0) {
            const order = rooms.map(r => r.id).filter(id => selRooms.indexOf(id) >= 0)   // map order, not click order
            HomeAssistant.cleanRooms(entityId, order, cycles)
        } else HomeAssistant.cleanAll(entityId, hasCycles ? cycles : 0)
    }
    readonly property string cleanText: (selRooms.length > 0
            ? "Clean " + selRooms.length + (selRooms.length === 1 ? " room" : " rooms")
            : "Clean all") + (hasCycles && cycles > 1 ? " · " + cycles + "×" : "")

    function pretty(s) { return s ? String(s.charAt(0).toUpperCase() + s.slice(1)).replace(/_/g, " ") : "" }

    readonly property int tileExtra: 40      // icon + padding of a room tile: a name needs its width plus this

    implicitHeight: body.implicitHeight + 24
    radius: Theme.radiusItem
    color: cleaning ? Theme.alpha(Theme.accent, 0.10) : Theme.alpha(Theme.fg, 0.05)
    border.width: cleaning ? 1 : 0
    border.color: Theme.alpha(Theme.accent, 0.45)
    opacity: hiddenNow || unavailable ? Theme.disabledOpacity : 1

    // ---- building blocks ----
    // small label above a control
    component Caption: Label { color: Theme.fgDim; font.pixelSize: Theme.fontCaption; font.letterSpacing: 0.6 }

    // icon + text button, Btn's look (fills, radius, press) with a leading glyph; `primary` is the filled accent one
    component ActBtn: Rectangle {
        id: ab
        property string icon: ""
        property string text: ""
        property bool primary: false
        property bool active: false
        property bool enabledLook: true
        signal clicked()
        implicitHeight: Theme.controlH
        implicitWidth: row.implicitWidth + 2 * Theme.pad
        radius: Theme.inner(Theme.radiusItem, Theme.pad)    // inside the card's padding
        opacity: enabledLook ? 1 : Theme.disabledOpacity
        color: primary || active ? (abGlow.hovered ? Theme.accentHover : Theme.accentFill)
             : abGlow.hovered ? Theme.itemActive : Theme.itemFill
        border.width: primary || active ? 1 : 0
        border.color: Theme.accentEdge
        Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
        PressFeedback { area: abArea }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: Theme.gapRow
            Icon {
                visible: ab.icon !== ""
                text: ab.icon
                font.pixelSize: Theme.fontSize      // Btn's icon glyph size
                color: ab.primary || ab.active ? Theme.accent : Theme.fg
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                visible: ab.text !== ""
                text: ab.text
                font.pixelSize: Theme.fontSmall
                font.bold: ab.primary
                color: ab.primary || ab.active ? Theme.accent : Theme.fg
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        HoverGlow { id: abGlow; area: abArea; radius: ab.radius }
        MouseArea {
            id: abArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: ab.enabledLook ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (ab.enabledLook) ab.clicked()
        }
    }

    // joined row of equal-width options; `current` is highlighted
    component Segmented: Rectangle {
        id: seg
        property var options: []
        property var labels: []             // display text per option
        property var current: undefined
        signal picked(var value)
        implicitHeight: Theme.controlH
        color: "transparent"
        radius: Theme.inner(Theme.radiusItem, Theme.pad)    // inside the card's padding
        border.width: 1
        border.color: Theme.alpha(Theme.overlay, 0.6)
        Row {
            anchors.fill: parent
            anchors.margins: 1
            Repeater {
                model: seg.options
                Rectangle {
                    id: cell
                    required property var modelData
                    required property int index
                    readonly property bool on: seg.current !== undefined && String(seg.current) === String(modelData)
                    width: (seg.width - 2) / Math.max(1, seg.options.length)
                    height: parent.height
                    // end cells follow the frame's rounded corners (1 px inside its border)
                    readonly property real endR: Theme.inner(seg.radius, 1)
                    topLeftRadius: index === 0 ? endR : 0
                    bottomLeftRadius: index === 0 ? endR : 0
                    topRightRadius: index === seg.options.length - 1 ? endR : 0
                    bottomRightRadius: index === seg.options.length - 1 ? endR : 0
                    color: on ? Theme.alpha(Theme.accent, 0.3) : cellGlow.hovered ? Theme.alpha(Theme.fg, 0.12) : Theme.alpha(Theme.fg, 0.04)
                    Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
                    Rectangle {                      // hairline between cells
                        visible: cell.index > 0
                        width: 1; height: parent.height
                        color: Theme.alpha(Theme.overlay, 0.6)
                    }
                    Rectangle {                      // accent outline on the selected cell
                        visible: cell.on
                        anchors.fill: parent
                        topLeftRadius: cell.topLeftRadius; bottomLeftRadius: cell.bottomLeftRadius
                        topRightRadius: cell.topRightRadius; bottomRightRadius: cell.bottomRightRadius
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.alpha(Theme.accent, 0.8)
                    }
                    Label {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.gapTight; anchors.rightMargin: Theme.gapTight
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: seg.labels[cell.index] !== undefined ? seg.labels[cell.index] : String(cell.modelData)
                        font.pixelSize: Theme.fontCaption
                        color: cell.on ? Theme.accent : Theme.fg
                    }
                    HoverGlow {
                        id: cellGlow
                        area: cellArea
                        topLeftRadius: cell.topLeftRadius; bottomLeftRadius: cell.bottomLeftRadius
                        topRightRadius: cell.topRightRadius; bottomRightRadius: cell.bottomRightRadius
                    }
                    MouseArea {
                        id: cellArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.picked(cell.modelData)
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.pad }
        spacing: Theme.pad

        // ---- header: icon, name / status, battery ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.pad          // icon column -> text, as ListRow
            Icon {
                text: Icons.vacuum
                font.pixelSize: Theme.iconLg
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: Theme.iconCol
                color: vac.cleaning ? Theme.accent : Theme.fgDim
            }
            RowText {
                title: vac.title
                titleBold: true
                sub: vac.unavailable ? "Unavailable" : (vac.area !== "" ? vac.area + " · " : "") + vac.pretty(vac.status)
            }
            Row {
                visible: !vac.editing && vac.battery >= 0
                spacing: Theme.controlGap
                Icon {
                    text: vac.charging ? Icons.bolt : ""
                    visible: vac.charging
                    font.pixelSize: Theme.iconSm
                    color: Theme.green           // charging
                    anchors.verticalCenter: parent.verticalCenter
                }
                Icon {
                    text: Icons.batteryGlyph(vac.battery, false)
                    font.pixelSize: Theme.iconMd
                    color: vac.battery < 20 ? Theme.red : Theme.fgDim
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label { text: vac.battery + "%"; font.pixelSize: Theme.fontSmall; color: Theme.fg; anchors.verticalCenter: parent.verticalCenter }
            }
            Btn {
                outerRadius: vac.radius        // inside the card's 12 px padding
                visible: vac.editing
                icon: true
                text: vac.hiddenNow ? Icons.eyeOff : Icons.eye
                active: !vac.hiddenNow
                onClicked: HomeAssistant.setHidden(vac.entityId, !vac.hiddenNow)
            }
        }

        // ---- primary actions ----
        RowLayout {
            visible: !vac.editing && !vac.unavailable
            Layout.fillWidth: true
            spacing: Theme.controlGap
            ActBtn {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: Icons.play
                text: vac.st === "paused" ? "Resume" : "Start"
                active: vac.cleaning
                enabledLook: !vac.busy
                onClicked: HomeAssistant.call("vacuum", "start", vac.entityId)
            }
            ActBtn {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: Icons.pause
                text: "Pause"
                active: vac.st === "paused"
                enabledLook: !vac.busy
                onClicked: HomeAssistant.call("vacuum", "pause", vac.entityId)
            }
            ActBtn {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: Icons.dock
                text: "Dock"
                active: vac.st === "returning"
                enabledLook: !vac.busy
                onClicked: HomeAssistant.call("vacuum", "return_to_base", vac.entityId)
            }
        }

        // ---- rooms ----
        ColumnLayout {
            visible: !vac.editing && !vac.unavailable && vac.rooms.length > 0
            Layout.fillWidth: true
            spacing: Theme.controlGap
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.controlGap
                Caption { text: "Rooms" + (vac.selRooms.length > 0 ? " · " + vac.selRooms.length + " selected" : ""); Layout.fillWidth: true }
                Repeater {
                    model: [["All", true], ["None", false]]
                    Label {
                        required property var modelData
                        text: modelData[0]
                        font.pixelSize: Theme.fontCaption
                        color: linkArea.containsMouse ? Theme.accent : Theme.fgDim
                        font.underline: linkArea.containsMouse
                        MouseArea {
                            id: linkArea
                            anchors.fill: parent; anchors.margins: -Theme.gapTight
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: vac.selRooms = parent.modelData[1] ? vac.rooms.map(r => r.id) : []
                        }
                    }
                }
            }
            FontMetrics { id: fm; font.family: Theme.font; font.pixelSize: Theme.fontSmall }
            GridLayout {
                id: roomGrid
                Layout.fillWidth: true
                // three columns when every name fits a third of the row (icon + padding = tileExtra), else two
                columns: vac.rooms.every(r => fm.advanceWidth(r.name) + vac.tileExtra <= (roomGrid.width - 2 * roomGrid.columnSpacing) / 3) ? 3 : 2
                rowSpacing: Theme.controlGap
                columnSpacing: Theme.controlGap
                Repeater {
                    model: vac.rooms
                    Rectangle {
                        id: tile
                        required property var modelData
                        readonly property bool sel: vac.selRooms.indexOf(modelData.id) >= 0
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1                    // equal columns
                        implicitHeight: Theme.controlH              // as the action buttons above
                        radius: Theme.inner(Theme.radiusItem, Theme.pad)    // inside the card's padding
                        color: sel ? (roomGlow.hovered ? Theme.accentHover : Theme.accentFill) : roomGlow.hovered ? Theme.itemActive : Theme.itemFill
                        border.width: sel ? 1 : 0
                        border.color: Theme.accentEdge
                        Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
                        RowLayout {
                            anchors { fill: parent; leftMargin: Theme.padSm; rightMargin: Theme.gapRow }
                            spacing: Theme.gapRow
                            Icon {
                                text: tile.sel ? Icons.squareCheck : Icons.square
                                font.pixelSize: Theme.iconSm
                                color: tile.sel ? Theme.accent : Theme.muted
                            }
                            Label {
                                text: tile.modelData.name
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: Theme.fontSmall
                                color: tile.sel ? Theme.accent : Theme.fg
                            }
                        }
                        HoverGlow { id: roomGlow; area: tileArea; radius: tile.radius }
                        MouseArea {
                            id: tileArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: vac.pickRoom(tile.modelData.id)
                        }
                    }
                }
            }
        }

        // ---- cycles ----
        ColumnLayout {
            visible: !vac.editing && !vac.unavailable && vac.hasCycles
            Layout.fillWidth: true
            spacing: Theme.controlGap
            Caption { text: "Cycles" }
            Segmented {
                Layout.fillWidth: true
                options: [1, 2, 3]
                labels: ["1×", "2×", "3×"]
                current: vac.cycles
                onPicked: v => vac.cycles = v
            }
        }

        // ---- primary: clean the selection (or everything) ----
        ActBtn {
            visible: !vac.editing && !vac.unavailable
            Layout.fillWidth: true
            primary: true
            icon: Icons.play
            text: vac.cleanText
            enabledLook: !vac.busy
            onClicked: vac.clean()
        }
    }
}
