pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Month calendar (Monday first) with events from omacal
// (bin/calendar-events). Event dots on the grid, click a day to see its agenda below.
GridLayout {
    id: cal
    columns: 1
    rowSpacing: Theme.gapRow
    columnSpacing: 0
    // The grid sits next to the bar and the agenda beyond it: panel at the bottom -> agenda on top,
    // grid at the bottom; bar at the top -> grid on top, agenda below. Same rule as the control center.
    readonly property int agendaH: 156          // fixed height of the agenda list (nothing moves when you pick a day)
    readonly property int agendaEmptyH: 60      // the agenda while the whole month has no events: just the empty-state row, no dead box
    readonly property int cellH: 38             // one day cell of the month grid
    readonly property bool barBottom: Popups.edgeOf(Popups.screen) !== "top"

    // Not SystemClock: it re-arms a QTimer with a negative interval during the repeated local hour at the end of DST (fires every 1 ms, ~2000 warnings/s, ~9% CPU)
    property date clockNow: new Date()
    Timer { interval: 5000; running: true; repeat: true; onTriggered: cal.clockNow = new Date() }
    property date shown: new Date()           // month on display
    property date selected: new Date()        // day whose agenda is listed
    readonly property date today: clockNow

    property var dayMap: ({})                 // "YYYY-MM-DD" -> [event]
    readonly property bool monthEmpty: Object.keys(dayMap).length === 0
    property bool loaded: false
    property string error: ""                 // calendar-events' error (omacal missing / not answering): shown in the agenda's empty state
    property var writable: []                 // calendars events can be added to (omacal only)
    property string source: ""                // "omacal" (calendar-events); events can only be added with omacal

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
                    cal.error = d.error ? String(d.error) : ""
                    cal.source = d.source || ""
                    cal.writable = d.writable || []
                    cal.index(d.events || [])
                    cal.loaded = true
                } catch (e) { cal.error = "No reply"; cal.loaded = true }
            }
        }
    }
    onShownChanged: reload()
    Component.onCompleted: reload()
    Timer { interval: 300000; running: true; repeat: true; onTriggered: cal.reload() }   // pick up omacal's syncs

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
        spacing: Theme.gapRow

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
                text: Icons.externalLink
                onClicked: { creator.openDay(cal.key(cal.selected)); Popups.close() }
            }
        }

        CalAddState { id: addState }
        CalCreate {
            id: creator
            onCreated: { addForm.shown = false; cal.reload() }
        }

        // The add form takes the agenda's place. The agenda keeps its fixed height (clicking between days never
        // resizes the panel); while the form is open the area grows to the form's height, away from the grid (the
        // card's far edge moves, the grid stays put under the pointer), and the two cross-fade.
        Item {
            id: agendaArea
            readonly property real agendaH: cal.monthEmpty ? cal.agendaEmptyH : cal.agendaH
            readonly property real openH: addForm.implicitHeight + Theme.controlGap      // a little air before the month header
            Layout.fillWidth: true
            Layout.preferredHeight: expanded ? Math.max(agendaH, openH) : agendaH
            // only the open / close glides: the form's own changes (calendar list unfolding) are animated inside it
            Behavior on Layout.preferredHeight { enabled: agendaArea.morphing; NumberAnimation { duration: Theme.popupMoveMs; easing.type: Theme.popupEaseMove } }
            property bool morphing: false
            property bool expanded: false             // follows addForm.shown, set after `morphing` so the change glides
            Timer { id: morphEnd; interval: Theme.popupMoveMs + 30; onTriggered: agendaArea.morphing = false }
            clip: morphing

        CalAddEvent {
            id: addForm
            property bool shown: false
            function toggle() { shown = !shown }
            onShownChanged: { agendaArea.morphing = true; morphEnd.restart(); agendaArea.expanded = shown; if (shown) open() }
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.topMargin: shown ? 0 : -Theme.gapRow
            Behavior on anchors.topMargin { NumberAnimation { duration: Theme.popupMoveMs; easing.type: Theme.popupEaseMove } }
            opacity: shown ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.popupFadeInMs; easing.type: Easing.OutCubic } }
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
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: agendaArea.agendaH
            opacity: addForm.shown ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.popupFadeInMs; easing.type: Easing.OutCubic } }
            clip: true
            spacing: Theme.controlGap
            // all-day first, then by time
            model: cal.eventsOn(cal.selected).slice().sort((a, b) => (b.allDay - a.allDay) || a.start.localeCompare(b.start))
            delegate: Rectangle {
                id: evCard
                required property var modelData
                width: agenda.width
                height: row.implicitHeight + Theme.pad
                radius: Theme.radiusItem
                color: Theme.itemFill
                Rectangle { x: 0; y: parent.radius; width: 3; height: parent.height - parent.radius * 2; color: evCard.modelData.color }   // clear of the rounded corners
                ColumnLayout {
                    id: row
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Theme.pad; rightMargin: Theme.padSm }
                    spacing: 1
                    RowLayout {
                        spacing: Theme.gapRow
                        Label { text: evCard.modelData.title; Layout.fillWidth: true; elide: Text.ElideRight; font.bold: true }
                        Label { text: cal.when(evCard.modelData); color: Theme.fgDim; font.pixelSize: Theme.fontCaption }
                    }
                    Label {
                        visible: evCard.modelData.location !== ""
                        textFormat: Text.StyledText
                        text: "<font face=\"" + Theme.iconFont + "\">" + Icons.locationDot + "</font>  " + evCard.modelData.location
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: Theme.fgDim
                        font.pixelSize: Theme.fontCaption
                    }
                    Label { text: evCard.modelData.calendar; color: Theme.muted; font.pixelSize: Theme.fontTiny }
                }
            }
            EmptyState {
                anchors { left: parent.left; right: parent.right; top: parent.top }   // the first row of the agenda
                visible: agenda.count === 0
                icon: cal.loaded ? Icons.calendarPlain : Icons.spinner
                text: !cal.loaded ? "Loading…" : cal.error !== "" ? "No calendar" : "No events"
                hint: cal.loaded ? cal.error : ""
            }
        }
        }


    }

    ColumnLayout {
        id: gridSec
        Layout.fillWidth: true
        Layout.row: cal.barBottom ? 1 : 0
        spacing: Theme.gapRow

        // ---- header -------------------------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Btn { icon: true; text: Icons.chevronLeft; onClicked: cal.monthShift(-1) }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(cal.shown, "MMMM yyyy")
                font.pixelSize: Theme.fontLead
                font.bold: true
            }
            Btn { text: "Today"; onClicked: { cal.shown = new Date(); cal.selected = new Date() } }
            Btn { icon: true; text: Icons.chevronRight; onClicked: cal.monthShift(1) }
        }

        // ---- month grid ------------------------------------------------------------------------------
        GridLayout {
            Layout.fillWidth: true
            columns: 7
            rowSpacing: Theme.gapTight / 2
            columnSpacing: Theme.gapTight / 2

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
                    implicitHeight: cal.cellH
                    radius: Theme.radiusItem
                    color: isToday ? Theme.alpha(Theme.accent, 0.32) : cellGlow.hovered ? Theme.itemHover : "transparent"
                    border.width: isSel ? 1 : 0
                    border.color: Theme.accent
                    Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }

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
}
