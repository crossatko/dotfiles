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

    function pretty(s) { return s ? (s.charAt(0).toUpperCase() + s.slice(1)).replace(/_/g, " ") : "" }
    function batteryIcon(p) { return p >= 88 ? "" : p >= 63 ? "" : p >= 38 ? "" : p >= 13 ? "" : "" }

    implicitHeight: body.implicitHeight + 24
    radius: Math.max(0, Theme.rounding - 4)
    color: cleaning ? Theme.alpha(Theme.accent, 0.10) : Theme.alpha(Theme.fg, 0.05)
    border.width: cleaning ? 1 : 0
    border.color: Theme.alpha(Theme.accent, 0.45)
    opacity: hiddenNow || unavailable ? 0.45 : 1

    // ---- building blocks ----
    // small label above a control
    component Caption: Label { color: Theme.fgDim; font.pixelSize: 11; font.letterSpacing: 0.6 }

    // icon + text button; `primary` is the filled accent one
    component ActBtn: Rectangle {
        id: ab
        property string icon: ""
        property string text: ""
        property bool primary: false
        property bool active: false
        property bool enabledLook: true
        signal clicked()
        implicitHeight: 34
        implicitWidth: row.implicitWidth + 24
        radius: Math.max(0, Theme.rounding - 4)
        opacity: enabledLook ? 1 : 0.5
        color: primary ? (abArea.containsMouse ? Theme.alpha(Theme.accent, 0.42) : Theme.alpha(Theme.accent, 0.3))
             : active ? Theme.alpha(Theme.accent, 0.3)
             : abArea.containsMouse ? Theme.alpha(Theme.fg, 0.14) : Theme.alpha(Theme.fg, 0.07)
        border.width: primary || active ? 1 : 0
        border.color: Theme.alpha(Theme.accent, 0.8)
        Behavior on color { ColorAnimation { duration: 100 } }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 8
            Label {
                visible: ab.icon !== ""
                text: ab.icon
                font.family: Theme.iconFont; font.styleName: "Regular"; font.pixelSize: 13
                color: ab.primary || ab.active ? Theme.accent : Theme.fg
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                visible: ab.text !== ""
                text: ab.text
                font.pixelSize: 12
                font.bold: ab.primary
                color: ab.primary || ab.active ? Theme.accent : Theme.fg
                anchors.verticalCenter: parent.verticalCenter
            }
        }
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
        implicitHeight: 30
        color: "transparent"
        radius: Math.max(0, Theme.rounding - 4)
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
                    color: on ? Theme.alpha(Theme.accent, 0.3) : cellArea.containsMouse ? Theme.alpha(Theme.fg, 0.12) : Theme.alpha(Theme.fg, 0.04)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Rectangle {                      // hairline between cells
                        visible: cell.index > 0
                        width: 1; height: parent.height
                        color: Theme.alpha(Theme.overlay, 0.6)
                    }
                    Rectangle {                      // accent outline on the selected cell
                        visible: cell.on
                        anchors.fill: parent
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.alpha(Theme.accent, 0.8)
                    }
                    Label {
                        anchors.fill: parent
                        anchors.leftMargin: 4; anchors.rightMargin: 4
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: seg.labels[cell.index] !== undefined ? seg.labels[cell.index] : String(cell.modelData)
                        font.pixelSize: 11
                        color: cell.on ? Theme.accent : Theme.fg
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
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 12

        // ---- header: icon, name / status, battery ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            Label {
                text: ""
                font.family: Theme.iconFont; font.styleName: "Regular"; font.pixelSize: 18
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: 22
                color: vac.cleaning ? Theme.accent : Theme.fgDim
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label { text: vac.title; Layout.fillWidth: true; elide: Text.ElideRight; font.bold: true }
                Label {
                    text: vac.unavailable ? "Unavailable" : (vac.area !== "" ? vac.area + " · " : "") + vac.pretty(vac.status)
                    Layout.fillWidth: true; elide: Text.ElideRight
                    color: Theme.fgDim; font.pixelSize: 11
                }
            }
            Row {
                visible: !vac.editing && vac.battery >= 0
                spacing: 6
                Label {
                    text: vac.charging ? "" : ""
                    visible: vac.charging
                    font.family: Theme.iconFont; font.styleName: "Regular"; font.pixelSize: 11
                    color: Theme.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    text: vac.batteryIcon(vac.battery)
                    font.family: Theme.iconFont; font.styleName: "Regular"; font.pixelSize: 15
                    color: vac.battery < 20 ? Theme.red : Theme.fgDim
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label { text: vac.battery + "%"; font.pixelSize: 12; color: Theme.fg; anchors.verticalCenter: parent.verticalCenter }
            }
            Btn {
                visible: vac.editing
                icon: true
                text: vac.hiddenNow ? "" : ""
                active: !vac.hiddenNow
                onClicked: HomeAssistant.setHidden(vac.entityId, !vac.hiddenNow)
            }
        }

        // ---- primary actions ----
        RowLayout {
            visible: !vac.editing && !vac.unavailable
            Layout.fillWidth: true
            spacing: 6
            ActBtn {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: ""
                text: vac.st === "paused" ? "Resume" : "Start"
                active: vac.cleaning
                enabledLook: !vac.busy
                onClicked: HomeAssistant.call("vacuum", "start", vac.entityId)
            }
            ActBtn {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: ""
                text: "Pause"
                active: vac.st === "paused"
                enabledLook: !vac.busy
                onClicked: HomeAssistant.call("vacuum", "pause", vac.entityId)
            }
            ActBtn {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: ""
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
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Caption { text: "Rooms" + (vac.selRooms.length > 0 ? " · " + vac.selRooms.length + " selected" : ""); Layout.fillWidth: true }
                Repeater {
                    model: [["All", true], ["None", false]]
                    Label {
                        required property var modelData
                        text: modelData[0]
                        font.pixelSize: 11
                        color: linkArea.containsMouse ? Theme.accent : Theme.fgDim
                        font.underline: linkArea.containsMouse
                        MouseArea {
                            id: linkArea
                            anchors.fill: parent; anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: vac.selRooms = parent.modelData[1] ? vac.rooms.map(r => r.id) : []
                        }
                    }
                }
            }
            FontMetrics { id: fm; font.family: Theme.font; font.pixelSize: 12 }
            GridLayout {
                id: roomGrid
                Layout.fillWidth: true
                // three columns when every name fits a third of the row (icon + padding = 40 px), else two
                columns: vac.rooms.every(r => fm.advanceWidth(r.name) + 40 <= (roomGrid.width - 12) / 3) ? 3 : 2
                rowSpacing: 6
                columnSpacing: 6
                Repeater {
                    model: vac.rooms
                    Rectangle {
                        id: tile
                        required property var modelData
                        readonly property bool sel: vac.selRooms.indexOf(modelData.id) >= 0
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1                    // equal columns
                        implicitHeight: 34
                        radius: Math.max(0, Theme.rounding - 4)
                        color: sel ? Theme.alpha(Theme.accent, 0.3) : tileArea.containsMouse ? Theme.alpha(Theme.fg, 0.14) : Theme.alpha(Theme.fg, 0.07)
                        border.width: sel ? 1 : 0
                        border.color: Theme.alpha(Theme.accent, 0.8)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                            spacing: 8
                            Label {
                                text: tile.sel ? "" : ""
                                font.family: Theme.iconFont; font.styleName: "Regular"; font.pixelSize: 12
                                color: tile.sel ? Theme.accent : Theme.muted
                            }
                            Label {
                                text: tile.modelData.name
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: 12
                                color: tile.sel ? Theme.accent : Theme.fg
                            }
                        }
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
            spacing: 6
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
            icon: ""
            text: vac.cleanText
            enabledLook: !vac.busy
            onClicked: vac.clean()
        }
    }
}
