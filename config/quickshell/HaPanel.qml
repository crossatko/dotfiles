import QtQuick
import QtQuick.Layouts

// Home Assistant popup (house chip in the bar): lights, climate, vacuum (HaVacuum), fans, covers, switches.
// State and transport: HomeAssistant.qml. The eye button switches to hide / unhide mode.
ColumnLayout {
    id: hp
    spacing: 10

    property bool editing: false
    property var expanded: ({})              // entity_id -> true: colour controls open

    readonly property var groups: [
        { key: "light", title: "Lights", domains: ["light"], grid: false },
        { key: "climate", title: "Climate", domains: ["climate"], grid: false },
        { key: "vacuum", title: "Vacuum", domains: ["vacuum"], grid: false },
        { key: "fan", title: "Fans", domains: ["fan"], grid: false },
        { key: "cover", title: "Covers", domains: ["cover"], grid: false },
        { key: "switch", title: "Switches", domains: ["switch", "input_boolean"], grid: false }
    ]
    function availableOf(g) {
        let ids = []
        for (const d of g.domains) ids = ids.concat(HomeAssistant.sections[d] || [])
        return ids.filter(id => HomeAssistant.isAvailable(id))
    }
    // entities of a section that pass the per-entity hide filter
    function entsOf(g) { return availableOf(g).filter(id => hp.editing || !HomeAssistant.isHidden(id)) }
    // entities actually shown (none while the whole section is off)
    function idsOf(g) { return HomeAssistant.isSectionHidden(g.key) ? [] : entsOf(g) }
    // a hidden section keeps its (dimmed) header in edit mode so it can be switched back on
    function sectionVisible(g) {
        return HomeAssistant.isSectionHidden(g.key) ? hp.editing && availableOf(g).length > 0 : entsOf(g).length > 0
    }
    readonly property int unavailableCount: {
        let n = 0
        for (const d of HomeAssistant.domains) if (!HomeAssistant.isSectionHidden(HomeAssistant.sectionOf(d)))
            n += (HomeAssistant.sections[d] || []).filter(id => !HomeAssistant.isAvailable(id) && !HomeAssistant.isHidden(id)).length
        return n
    }
    readonly property int hiddenCount: HomeAssistant.hidden.filter(id => HomeAssistant.byId[id] !== undefined).length
    readonly property int hiddenSectionCount: HomeAssistant.hiddenSections.filter(k => groups.some(g => g.key === k && availableOf(g).length > 0)).length
    readonly property int shownCount: {
        let n = 0
        for (const g of groups) n += idsOf(g).length
        return n
    }
    // sections drawn at all (hidden ones count in edit mode); the list stays up while any is there
    readonly property int sectionCount: groups.filter(g => sectionVisible(g)).length

    PanelHeader {
        id: header
        title: "Home"
        showStatus: true
        status: HomeAssistant.status === "ok" && HomeAssistant.lightsOn > 0 ? HomeAssistant.lightsOn + (HomeAssistant.lightsOn === 1 ? " light on" : " lights on") : ""
        Btn {
            visible: HomeAssistant.configured
            icon: true
            text: ""
            onClicked: HomeAssistant.refresh(true)
        }
        Btn {
            visible: HomeAssistant.configured && HomeAssistant.status === "ok"
            icon: true
            text: hp.editing ? "" : ""
            active: hp.editing
            onClicked: hp.editing = !hp.editing
        }
    }

    // setup / error / edit-mode notice
    Notice {
        id: notice
        readonly property bool setup: HomeAssistant.secretsRead && !HomeAssistant.configured
        readonly property bool bad: HomeAssistant.configured && HomeAssistant.failed
        visible: setup || bad || HomeAssistant.actionError !== "" || hp.editing || (HomeAssistant.status === "loading" && hp.sectionCount === 0)
        danger: bad || HomeAssistant.actionError !== ""
        padY: 10
        spacing: 10
        Label {
            id: noticeText
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            lineHeight: 1.15
            textFormat: Text.StyledText
            color: Theme.fg
            font.pixelSize: Theme.fontSmall
            text: notice.setup
                ? "<b>Connect Home Assistant</b><br>"
                  + "1. In Home Assistant open your profile → Security → Long-lived access tokens → Create token.<br>"
                  + "2. Add <tt>HA_URL=http://&lt;host&gt;:8123</tt> and <tt>HA_TOKEN=&lt;token&gt;</tt> to <tt>~/.config/hypr/.secrets</tt>.<br>"
                  + "The panel picks it up the next time it opens."
                : notice.bad
                ? "<b>" + HomeAssistant.errorText + "</b><br>Host: <tt>" + HomeAssistant.host + "</tt>"
                  + (HomeAssistant.errorHint !== "" ? "<br>" + HomeAssistant.errorHint : "")
                  + (HomeAssistant.status === "unreachable" ? "<br>Retrying every 15 s." : "")
                : HomeAssistant.actionError !== "" ? HomeAssistant.actionError
                : hp.editing ? "Choose what the panel shows: the eye hides or unhides an entity, the switch in a section header turns the whole section on or off."
                  + (hp.hiddenCount > 0 ? " " + hp.hiddenCount + (hp.hiddenCount === 1 ? " entity" : " entities") + " hidden." : "")
                  + (hp.hiddenSectionCount > 0 ? " " + hp.hiddenSectionCount + (hp.hiddenSectionCount === 1 ? " section" : " sections") + " off." : "")
                : "Loading…"
        }
        RowLayout {
            visible: notice.bad
            Layout.fillWidth: true
            spacing: 8
            Btn {
                outerRadius: notice.radius       // inside the notice's 12 px padding
                text: HomeAssistant.retrying || HomeAssistant.refreshing ? "Retrying…" : "Retry"
                active: true
                onClicked: HomeAssistant.refresh(true)
            }
            Label { visible: HomeAssistant.lastUpdate > 0; text: "Last update " + Qt.formatTime(new Date(HomeAssistant.lastUpdate), "HH:mm"); color: Theme.fgDim; font.pixelSize: Theme.fontCaption }
            Item { Layout.fillWidth: true }
        }
    }

    Flickable {
        id: flick
        visible: HomeAssistant.configured && HomeAssistant.status === "ok" && hp.sectionCount > 0
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? Math.min(600, content.implicitHeight) : 0
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: content
            width: flick.width
            spacing: 8

            Repeater {
                model: hp.groups
                ColumnLayout {
                    id: grp
                    required property var modelData
                    readonly property var ids: hp.entsOf(modelData)      // delegates stay alive while the section is off; its grid is just hidden
                    readonly property bool off: HomeAssistant.isSectionHidden(modelData.key)
                    visible: hp.sectionVisible(modelData)
                    opacity: off ? 0.5 : 1
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 6

                    SectionHead {
                        title: grp.modelData.title
                        detail: grp.off ? "hidden" : grp.modelData.grid || grp.isVacuum ? "" : grp.ids.filter(id => {
                            const e = HomeAssistant.byId[id]
                            return e && (e.state === "on" || e.state === "cleaning" || e.state === "open" || (id.indexOf("climate.") === 0 && e.state !== "off" && e.state !== "unavailable"))
                        }).length + " of " + grp.ids.length + " on"
                        Toggle {
                            visible: hp.editing
                            implicitWidth: 34; implicitHeight: 18
                            checked: !grp.off
                            onToggled: want => HomeAssistant.setSectionHidden(grp.modelData.key, !want)
                        }
                    }

                    readonly property bool isVacuum: modelData.domains[0] === "vacuum"
                    GridLayout {
                        visible: !grp.off
                        Layout.fillWidth: true
                        columns: grp.modelData.grid ? 2 : 1
                        rowSpacing: 6
                        columnSpacing: 6
                        Repeater {
                            model: grp.isVacuum ? grp.ids : []
                            HaVacuum {
                                required property var modelData
                                entityId: modelData
                                Layout.fillWidth: true
                                editing: hp.editing
                            }
                        }
                        Repeater {
                            model: grp.isVacuum ? [] : grp.ids
                            HaEntity {
                                required property var modelData
                                entityId: modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1          // equal grid columns
                                compact: grp.modelData.grid
                                editing: hp.editing
                                expanded: hp.expanded[modelData] === true
                                onToggleExpand: {
                                    const x = Object.assign({}, hp.expanded)
                                    if (x[modelData]) delete x[modelData]; else x[modelData] = true
                                    hp.expanded = x
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Label {
        visible: HomeAssistant.configured && HomeAssistant.status === "ok" && hp.unavailableCount > 0
        text: hp.unavailableCount + " unavailable"
        color: Theme.muted
        font.pixelSize: Theme.fontCaption
        Layout.alignment: Qt.AlignRight
    }

    Label {
        visible: HomeAssistant.configured && HomeAssistant.status === "ok" && hp.sectionCount === 0
        text: hp.hiddenCount > 0 || hp.hiddenSectionCount > 0 ? "Everything is hidden. Use the eye button to bring entities and sections back." : "No lights, switches, climate, vacuum, fan or cover entities found."
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        color: Theme.muted
    }
}
