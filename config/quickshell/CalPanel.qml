pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Month calendar (Monday first) with events from Thunderbird's local calendar cache
// (bin/calendar-events). Event dots on the grid, click a day to see its agenda below.
GridLayout {
    id: cal
    columns: 1
    rowSpacing: 8
    columnSpacing: 0
    // The grid sits next to the bar and the agenda beyond it: panel at the bottom -> agenda on top,
    // grid at the bottom; bar at the top -> grid on top, agenda below. Same rule as the control center.
    readonly property bool barBottom: Popups.edgeOf(Popups.screen) !== "top"

    // Not SystemClock: it re-arms a QTimer with a negative interval during the repeated local hour at the end of DST (fires every 1 ms, ~2000 warnings/s, ~9% CPU)
    property date clockNow: new Date()
    Timer { interval: 5000; running: true; repeat: true; onTriggered: cal.clockNow = new Date() }
    property date shown: new Date()           // month on display
    property date selected: new Date()        // day whose agenda is listed
    readonly property date today: clockNow

    property var dayMap: ({})                 // "YYYY-MM-DD" -> [event]
    property var uncached: []
    property bool loaded: false
    property var writable: []                 // calendars events can be added to (omacal only)
    property string source: ""                // "omacal" | "thunderbird" (calendar-events); events can only be added with omacal

    function two(n) { return n < 10 ? "0" + n : "" + n }
    function key(d) { return d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate()) }
    function monthShift(d) { shown = new Date(shown.getFullYear(), shown.getMonth() + d, 1) }
    function firstCell() {
        const first = new Date(shown.getFullYear(), shown.getMonth(), 1)
        return new Date(first.getFullYear(), first.getMonth(), 1 - (first.getDay() + 6) % 7)
    }

    // ---- data -------------------------------------------------------------------------------
    function reload() {
        const a = firstCell()
        const b = new Date(a.getFullYear(), a.getMonth(), a.getDate() + 42)
        loader.command = [Quickshell.shellDir + "/bin/calendar-events", key(a), key(b)]
        loader.running = true
    }
    function index(events) {
        const m = {}
        for (const e of events) {
            const s = new Date(e.start.replace(" ", "T"))
            let last = new Date(e.end.replace(" ", "T"))
            if (e.allDay || (last.getHours() === 0 && last.getMinutes() === 0)) last = new Date(last.getTime() - 60000)   // end is exclusive
            if (last < s) last = s
            for (let d = new Date(s.getFullYear(), s.getMonth(), s.getDate()); d <= last; d.setDate(d.getDate() + 1)) {
                const k = key(d)
                ;(m[k] = m[k] || []).push(e)
            }
        }
        dayMap = m
    }
    Process {
        id: loader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    cal.uncached = d.uncached || []
                    cal.source = d.source || ""
                    cal.writable = d.writable || []
                    cal.index(d.events || [])
                    cal.loaded = true
                } catch (e) { cal.loaded = true }
            }
        }
    }
    onShownChanged: reload()
    Component.onCompleted: reload()
    Timer { interval: 300000; running: true; repeat: true; onTriggered: cal.reload() }   // pick up Thunderbird's syncs

    function eventsOn(d) { return dayMap[key(d)] || [] }
    function dots(d) {
        const seen = [], out = []
        for (const e of eventsOn(d)) if (seen.indexOf(e.calendar) < 0) { seen.push(e.calendar); out.push(e.color) }
        return out.slice(0, 3)
    }
    function when(e) {
        if (e.allDay) return "All day"
        return e.start.slice(11) + "–" + e.end.slice(11)
    }

    ColumnLayout {
        id: agendaSec
        Layout.fillWidth: true
        Layout.row: cal.barBottom ? 0 : 1
        spacing: 8

        // ---- agenda for the selected day (ABOVE the grid, fixed height: nothing moves when you pick a day) ----
        SectionHead {
            title: cal.key(cal.selected) === cal.key(cal.today) ? "Today" : Qt.formatDate(cal.selected, "ddd d MMM")
            detail: cal.eventsOn(cal.selected).length > 0 ? cal.eventsOn(cal.selected).length + (cal.eventsOn(cal.selected).length === 1 ? " event" : " events") : ""
            // omacal only: add inline / open the app on this day
            Btn { visible: cal.source === "omacal" && cal.writable.length > 0; Layout.preferredHeight: 22; text: "+ Add event"; active: addForm.shown; onClicked: addForm.toggle() }
            Btn {
                visible: cal.source === "omacal"
                Layout.preferredHeight: 22
                Layout.preferredWidth: 28
                icon: true
                text: "\uf08e"
                onClicked: { creator.openDay(cal.key(cal.selected)); Popups.close() }
            }
        }

        CalAddState { id: addState }
        CalCreate {
            id: creator
            onCreated: { addForm.shown = false; cal.reload() }
        }

        // The add form takes the agenda's place (same fixed height), so nothing else in the popup moves.
        Item {
            id: agendaArea
            Layout.fillWidth: true
            Layout.preferredHeight: 156            // fixed, so clicking between days never resizes the panel

        CalAddEvent {
            id: addForm
            property bool shown: false
            function toggle() { shown = !shown }
            onShownChanged: if (shown) open()
            anchors { left: parent.left; right: parent.right; top: parent.top }
            visible: shown
            day: cal.selected
            calendars: cal.writable
            lastCalendar: addState.lastId
            busy: creator.busy
            serverError: creator.error
            onSubmit: (title, start, end, allDay, endDate, calendarId) => { addState.remember(calendarId); creator.create(title, cal.key(cal.selected), start, end, allDay, endDate, calendarId) }
            onCancelled: shown = false
        }

        ListView {
            id: agenda
            anchors.fill: parent
            visible: !addForm.shown
            clip: true
            spacing: 6
            // all-day first, then by time
            model: cal.eventsOn(cal.selected).slice().sort((a, b) => (b.allDay - a.allDay) || a.start.localeCompare(b.start))
            delegate: Rectangle {
                id: evCard
                required property var modelData
                width: agenda.width
                height: row.implicitHeight + 12
                radius: Theme.radiusItem
                color: Theme.alpha(Theme.fg, 0.06)
                Rectangle { x: 0; y: parent.radius; width: 3; height: parent.height - parent.radius * 2; color: evCard.modelData.color }   // clear of the rounded corners
                ColumnLayout {
                    id: row
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 10 }
                    spacing: 1
                    RowLayout {
                        spacing: 8
                        Label { text: evCard.modelData.title; Layout.fillWidth: true; elide: Text.ElideRight; font.bold: true }
                        Label { text: cal.when(evCard.modelData); color: Theme.fgDim; font.pixelSize: Theme.fontCaption }
                    }
                    Label {
                        visible: evCard.modelData.location !== ""
                        textFormat: Text.StyledText
                        text: "<font face=\"" + Theme.iconFont + "\">\uf3c5</font>  " + evCard.modelData.location
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: Theme.fgDim
                        font.pixelSize: Theme.fontCaption
                    }
                    Label { text: evCard.modelData.calendar; color: Theme.muted; font.pixelSize: Theme.fontTiny }
                }
            }
            Label {
                anchors.centerIn: parent
                visible: agenda.count === 0
                text: cal.loaded ? "No events" : "Loading…"
                color: Theme.muted
            }
        }
        }


    }

    ColumnLayout {
        id: gridSec
        Layout.fillWidth: true
        Layout.row: cal.barBottom ? 1 : 0
        spacing: 8

        // ---- header -------------------------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Btn { text: "‹"; onClicked: cal.monthShift(-1) }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(cal.shown, "MMMM yyyy")
                font.pixelSize: 16
                font.bold: true
            }
            Btn { text: "Today"; onClicked: { cal.shown = new Date(); cal.selected = new Date() } }
            Btn { text: "›"; onClicked: cal.monthShift(1) }
        }

        // ---- month grid ------------------------------------------------------------------------------
        GridLayout {
            Layout.fillWidth: true
            columns: 7
            rowSpacing: 2
            columnSpacing: 2

            Repeater {
                model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                Label {
                    required property string modelData
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: Theme.muted
                    font.pixelSize: Theme.fontCaption
                }
            }
            Repeater {
                model: 42
                Rectangle {
                    id: cell
                    required property int index
                    readonly property date day: new Date(cal.firstCell().getFullYear(), cal.firstCell().getMonth(), cal.firstCell().getDate() + index)
                    readonly property bool inMonth: day.getMonth() === cal.shown.getMonth()
                    readonly property bool isToday: cal.key(day) === cal.key(cal.today)
                    readonly property bool isSel: cal.key(day) === cal.key(cal.selected)
                    readonly property var dotColors: cal.dots(day)

                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: Theme.radiusItem
                    color: isToday ? Theme.alpha(Theme.accent, 0.32) : cellGlow.hovered ? Theme.alpha(Theme.fg, 0.10) : "transparent"
                    border.width: isSel ? 1 : 0
                    border.color: Theme.accent
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Label {
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 5 }
                        text: cell.day.getDate()
                        color: cell.isToday ? Theme.accent : cell.inMonth ? Theme.fg : Theme.muted
                        opacity: cell.inMonth ? 1 : 0.5
                        font.bold: cell.isToday
                    }
                    Row {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 5 }
                        spacing: 3
                        Repeater {
                            model: cell.dotColors
                            Rectangle { required property string modelData; width: 5; height: 5; radius: 3; color: modelData; opacity: cell.inMonth ? 1 : 0.5 }
                        }
                    }
                    HoverGlow { id: cellGlow; area: hover; radius: cell.radius }
                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { cal.selected = cell.day; if (!cell.inMonth) cal.shown = new Date(cell.day.getFullYear(), cell.day.getMonth(), 1) }
                    }
                }
            }
        }

    }

    Label {
        visible: cal.uncached.length > 0
        Layout.fillWidth: true
        Layout.preferredWidth: 1                      // don't let the text widen the popup
        Layout.row: 2
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
        // these CalDAV calendars have no local copy, so their events can't be shown here
        text: "Not shown: " + cal.uncached.join(", ") + " (enable Offline support in Thunderbird)"
        color: Theme.muted
        font.pixelSize: Theme.fontTiny
    }
}
