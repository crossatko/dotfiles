import QtQuick
import QtQuick.Layouts

// One Home Assistant entity card in HaPanel (vacuums use HaVacuum). Reads its live state from HomeAssistant.byId, so the
// card survives polling (the panel's model is the list of ids, which only changes when entities do).
// Controls never flip themselves: they send a service call and show the truth after the next refresh;
// sliders / strips keep a local value until then so they don't jump back.
Rectangle {
    id: ent

    property string entityId: ""
    property bool editing: false             // hide / unhide mode: an eye button instead of the controls
    property bool compact: false             // scene / script tile: the whole card runs it
    property bool expanded: false            // light colour controls
    signal toggleExpand()

    readonly property var e: HomeAssistant.byId[entityId] || null
    readonly property string domain: entityId.split(".")[0]
    readonly property var a: e && e.attributes ? e.attributes : ({})
    readonly property string st: e ? e.state : "unavailable"
    readonly property bool unavailable: st === "unavailable" || (st === "unknown" && domain !== "scene" && domain !== "script")
    readonly property bool hiddenNow: HomeAssistant.isHidden(entityId)
    readonly property bool busy: HomeAssistant.busy[entityId] === true
    readonly property string title: a.friendly_name || entityId
    readonly property string area: HomeAssistant.areas[entityId] || ""
    readonly property bool on: domain === "climate" ? (st !== "off" && !unavailable)
                             : domain === "cover" ? (st === "open" || st === "opening")
                             : domain === "vacuum" ? (st === "cleaning")
                             : st === "on"

    // ---- light features (supported_color_modes) ----
    readonly property var modes: a.supported_color_modes || []
    readonly property bool hasBri: domain === "light" && modes.some(m => m !== "onoff")
    readonly property bool hasColor: domain === "light" && modes.some(m => ["hs", "xy", "rgb", "rgbw", "rgbww"].indexOf(m) >= 0)
    readonly property bool hasCt: domain === "light" && modes.indexOf("color_temp") >= 0
    readonly property real bri: typeof a.brightness === "number" ? a.brightness / 255 : 0
    readonly property var hs: Array.isArray(a.hs_color) ? a.hs_color : null
    readonly property int ctMin: a.min_color_temp_kelvin || 2000
    readonly property int ctMax: a.max_color_temp_kelvin || 6500
    readonly property real ct: typeof a.color_temp_kelvin === "number" ? (a.color_temp_kelvin - ctMin) / Math.max(1, ctMax - ctMin) : -1
    readonly property color tint: Array.isArray(a.rgb_color) && a.rgb_color.length === 3
        ? Qt.rgba(a.rgb_color[0] / 255, a.rgb_color[1] / 255, a.rgb_color[2] / 255, 1) : Theme.accent

    // ---- climate ----
    readonly property bool hasTarget: domain === "climate" && typeof a.temperature === "number"
    readonly property real tStep: a.target_temp_step || (a.temperature_unit === "°F" ? 1 : 0.5)
    readonly property string unit: a.temperature_unit || "°"

    // local values while a change is on its way (cleared by the first refresh after the call)
    property real localBri: -1
    property real localHue: -1
    property real localSat: -1
    property real localCt: -1
    property real localPct: -1
    property real localTemp: -1000
    property double sentAt: 0
    Connections {
        target: HomeAssistant
        function onUpdated() {
            if (sendTimer.running || Date.now() - ent.sentAt < 1200) return
            ent.localBri = -1; ent.localHue = -1; ent.localSat = -1; ent.localCt = -1; ent.localPct = -1; ent.localTemp = -1000
        }
    }
    property var pending: null               // [domain, service, data] sent when the debounce runs out
    function later(d, s, data) { pending = [d, s, data]; sentAt = Date.now(); sendTimer.restart() }
    Timer {
        id: sendTimer; interval: 220
        onTriggered: if (ent.pending) { HomeAssistant.call(ent.pending[0], ent.pending[1], ent.entityId, ent.pending[2]); ent.sentAt = Date.now(); ent.pending = null }
    }
    function now(d, s, data) { sentAt = Date.now(); HomeAssistant.call(d, s, entityId, data) }

    function toggle(want) {
        if (domain === "climate") now("climate", want ? "turn_on" : "turn_off")
        else now(domain === "input_boolean" ? "input_boolean" : domain, want ? "turn_on" : "turn_off")
    }

    function icon() {
        switch (domain) {
        case "light": return on ? "" : ""
        case "switch": return ""
        case "input_boolean": return on ? "" : ""
        case "climate": return st === "heat" ? "" : st === "cool" ? "" : ""
        case "vacuum": return ""
        case "fan": return ""
        case "cover": return on ? "" : ""
        case "scene": return ""
        case "script": return ""
        }
        return ""
    }
    function pretty(s) { return s ? (s.charAt(0).toUpperCase() + s.slice(1)).replace(/_/g, " ") : "" }
    function sub() {
        if (unavailable) return "Unavailable"
        let s = ""
        switch (domain) {
        case "light": s = on ? (hasBri && a.brightness != null ? Math.round(bri * 100) + "%" : "On") : "Off"; break
        case "climate":
            s = pretty(a.hvac_action || st)
            if (typeof a.current_temperature === "number") s += " · " + a.current_temperature + unit
            break
        case "vacuum":
            s = pretty(a.status || st)
            if (typeof a.battery_level === "number") s += " · " + a.battery_level + "%"
            break
        case "cover": s = pretty(st) + (typeof a.current_position === "number" ? " · " + a.current_position + "%" : ""); break
        case "fan": s = on ? (typeof a.percentage === "number" ? a.percentage + "%" : "On") : "Off"; break
        default: s = on ? "On" : "Off"
        }
        return area ? area + " · " + s : s
    }

    implicitHeight: body.implicitHeight + (compact ? 16 : 18)
    radius: Theme.radiusItem
    color: compact && tileArea.containsMouse && !editing ? Theme.alpha(Theme.fg, 0.12)
         : on ? Theme.alpha(Theme.accent, 0.14) : Theme.alpha(Theme.fg, 0.05)
    border.width: on ? 1 : 0
    border.color: Theme.alpha(Theme.accent, 0.45)
    opacity: hiddenNow || unavailable ? 0.45 : 1
    Behavior on color { ColorAnimation { duration: 120 } }

    MouseArea {                               // scene / script tile: click runs it
        id: tileArea
        anchors.fill: parent
        enabled: ent.compact && !ent.editing && !ent.unavailable
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: ent.now(ent.domain, "turn_on")
    }

    ColumnLayout {
        id: body
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 10 }
        spacing: 8

        // ---- head: icon, name / state, main control ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            Icon {
                text: ent.icon()
                font.pixelSize: ent.compact ? 15 : 18
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: 22
                color: ent.domain === "light" && ent.on ? ent.tint : ent.on ? Theme.accent : Theme.fgDim
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label { text: ent.title; Layout.fillWidth: true; elide: Text.ElideRight }
                Label { visible: !ent.compact || ent.editing; text: ent.sub(); Layout.fillWidth: true; elide: Text.ElideRight; color: Theme.fgDim; font.pixelSize: 11 }
            }

            // hide / unhide
            Btn {
                outerRadius: Theme.radiusItem; inset: 8      // ~8-10 px inside the entity card
                visible: ent.editing
                icon: true
                text: ent.hiddenNow ? "" : ""
                active: !ent.hiddenNow
                onClicked: HomeAssistant.setHidden(ent.entityId, !ent.hiddenNow)
            }

            // colour controls (lights with colour / temperature)
            Btn {
                outerRadius: Theme.radiusItem; inset: 8
                visible: !ent.editing && ent.on && (ent.hasColor || ent.hasCt)
                icon: true
                text: ""
                active: ent.expanded
                onClicked: ent.toggleExpand()
            }
            // covers: open / stop / close
            Repeater {
                model: !ent.editing && ent.domain === "cover" ? [["", "open_cover"], ["", "stop_cover"], ["", "close_cover"]] : []
                Btn { required property var modelData; outerRadius: Theme.radiusItem; inset: 8; icon: true; text: modelData[0]; enabledLook: !ent.unavailable; onClicked: if (!ent.unavailable) ent.now("cover", modelData[1]) }
            }
            Toggle {
                visible: !ent.editing && ["light", "switch", "input_boolean", "fan", "climate"].indexOf(ent.domain) >= 0
                checked: ent.on
                busy: ent.busy
                enabledLook: !ent.unavailable
                onToggled: want => ent.toggle(want)
            }
        }

        // ---- light brightness / fan speed ----
        RowLayout {
            visible: !ent.editing && ent.on && (ent.hasBri || (ent.domain === "fan" && typeof ent.a.percentage === "number"))
            Layout.fillWidth: true
            Layout.leftMargin: 36
            spacing: 10
            Slider {
                Layout.fillWidth: true
                value: ent.domain === "fan" ? (ent.localPct >= 0 ? ent.localPct : (ent.a.percentage || 0) / 100)
                                            : (ent.localBri >= 0 ? ent.localBri : ent.bri)
                onMoved: v => {
                    if (ent.domain === "fan") { ent.localPct = v; ent.later("fan", "set_percentage", { percentage: Math.round(v * 100) }) }
                    else { ent.localBri = Math.max(0.01, v); ent.later("light", "turn_on", { brightness: Math.max(1, Math.round(v * 255)) }) }
                }
            }
        }

        // ---- light colour: hue + saturation strips, colour temperature ----
        ColumnLayout {
            id: colorBox
            visible: !ent.editing && ent.on && ent.expanded && (ent.hasColor || ent.hasCt)
            Layout.fillWidth: true
            Layout.leftMargin: 36
            Layout.rightMargin: 4
            spacing: 10

            readonly property real hue: ent.localHue >= 0 ? ent.localHue : ent.hs ? ent.hs[0] / 360 : -1
            readonly property real sat: ent.localSat >= 0 ? ent.localSat : ent.hs ? ent.hs[1] / 100 : -1

            HaStrip {
                id: hueStrip
                visible: ent.hasColor
                Layout.fillWidth: true
                colors: [0, 1, 2, 3, 4, 5, 6].map(i => Qt.hsva(i / 6, 1, 1, 1))
                value: ent.a.color_mode === "color_temp" && ent.localHue < 0 ? -1 : colorBox.hue
                onMoved: v => {
                    ent.localHue = v
                    const s = ent.localSat >= 0 ? ent.localSat : ent.hs && ent.a.color_mode !== "color_temp" ? Math.max(0.3, ent.hs[1] / 100) : 1
                    ent.localSat = s
                    ent.later("light", "turn_on", { hs_color: [Math.round(v * 360), Math.round(s * 100)] })
                }
            }
            HaStrip {
                visible: ent.hasColor
                Layout.fillWidth: true
                colors: ["#ffffff", Qt.hsva(Math.max(0, colorBox.hue), 1, 1, 1)]
                value: ent.a.color_mode === "color_temp" && ent.localSat < 0 ? -1 : colorBox.sat
                onMoved: v => {
                    ent.localSat = v
                    const h = ent.localHue >= 0 ? ent.localHue : ent.hs ? ent.hs[0] / 360 : 0
                    ent.localHue = h
                    ent.later("light", "turn_on", { hs_color: [Math.round(h * 360), Math.round(v * 100)] })
                }
            }
            RowLayout {
                visible: ent.hasCt
                Layout.fillWidth: true
                spacing: 10
                HaStrip {
                    Layout.fillWidth: true
                    colors: ["#ff9329", "#ffd2a1", "#fff4e5", "#dce8ff"]
                    value: ent.localCt >= 0 ? ent.localCt : ent.a.color_mode === "color_temp" ? ent.ct : -1
                    onMoved: v => {
                        ent.localCt = v
                        ent.later("light", "turn_on", { color_temp_kelvin: Math.round(ent.ctMin + v * (ent.ctMax - ent.ctMin)) })
                    }
                }
                Label {
                    text: ent.localCt < 0 && (ent.ct < 0 || ent.a.color_mode !== "color_temp") ? "—"
                        : Math.round(ent.ctMin + (ent.localCt >= 0 ? ent.localCt : ent.ct) * (ent.ctMax - ent.ctMin)) + "K"
                    color: Theme.fgDim; font.pixelSize: 11
                    Layout.preferredWidth: 42
                    horizontalAlignment: Text.AlignRight
                }
            }
        }

        // ---- climate: target temperature, modes ----
        RowLayout {
            id: tempRow
            visible: !ent.editing && ent.domain === "climate" && !ent.unavailable && ent.hasTarget
            Layout.fillWidth: true
            Layout.leftMargin: 36
            spacing: 6
            readonly property real target: ent.localTemp > -999 ? ent.localTemp : (ent.a.temperature || 0)
            function step(dir) {
                const t = Math.max(ent.a.min_temp || 7, Math.min(ent.a.max_temp || 35, target + dir * ent.tStep))
                ent.localTemp = t
                ent.later("climate", "set_temperature", { temperature: t })
            }
            Btn { outerRadius: Theme.radiusItem; inset: 8; icon: true; text: ""; onClicked: tempRow.step(-1) }
            Label { text: tempRow.target.toFixed(ent.tStep < 1 ? 1 : 0) + ent.unit; font.pixelSize: 15; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 64 }
            Btn { outerRadius: Theme.radiusItem; inset: 8; icon: true; text: ""; onClicked: tempRow.step(1) }
            Item { Layout.fillWidth: true }
            Label { visible: typeof ent.a.current_humidity === "number"; text: ent.a.current_humidity + "% RH"; color: Theme.fgDim; font.pixelSize: 11 }
        }
        Flow {
            visible: !ent.editing && ent.domain === "climate" && !ent.unavailable && (ent.a.hvac_modes || []).length > 0
            Layout.fillWidth: true
            Layout.leftMargin: 36
            spacing: 6
            Repeater {
                model: ent.domain === "climate" ? (ent.a.hvac_modes || []) : []
                Btn {
                    required property var modelData
                    outerRadius: Theme.radiusItem; inset: 8
                    text: ({ heat_cool: "Auto", fan_only: "Fan", off: "Off" })[modelData] || ent.pretty(modelData)
                    active: ent.st === modelData
                    onClicked: ent.now("climate", "set_hvac_mode", { hvac_mode: modelData })
                }
            }
        }
    }
}
