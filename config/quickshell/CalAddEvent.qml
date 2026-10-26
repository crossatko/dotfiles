import QtQuick
import QtQuick.Layouts
import "launcher/js/CalEvent.js" as CalEvent

// Inline "add event" form of the calendar popup: title, start/end (HH:MM) or All day, last day (multi-day events), Save / Cancel.
// Enter saves, Esc cancels. Validation errors are shown inline; `busy` and `serverError` come from the runner
// (CalCreate). Emits submit(title, start, end, allDay) only for valid input.
ColumnLayout {
    id: form
    property date day: new Date()
    property bool busy: false
    property string serverError: ""
    property string localError: ""
    readonly property string error: localError !== "" ? localError : serverError
    readonly property string date: CalEvent.isoDate(day)    // first day (YYYY-MM-DD)
    property var calendars: []              // writable calendars [{id, name, color, primary}]
    property int lastCalendar: -1           // id used last time
    readonly property alias calendarIndex: picker.index
    signal submit(string title, string start, string end, bool allDay, string endDate, int calendarId)
    signal cancelled()

    spacing: 6

    // picking another day in the grid moves the end date along
    onDateChanged: if (until.text < date || !CalEvent.validDate(until.text)) until.text = date

    // fresh defaults every time the form opens; focus waits a tick (the popup surface gets keyboard focus late)
    function open() {
        title.text = ""
        const s = CalEvent.defaultStart(day, new Date())
        start.text = s
        end.text = CalEvent.plusHour(s)
        allDay.checked = false
        until.text = date
        picker.index = CalEvent.pickCalendar(calendars, lastCalendar)
        localError = ""
        Qt.callLater(() => title.focusField())
    }
    function save() {
        if (busy) return
        localError = CalEvent.validate(title.text, start.text, end.text, allDay.checked, date, until.text)
        if (localError === "") submit(title.text, start.text, end.text, allDay.checked, until.text.trim(), picker.current ? picker.current.id : -1)
    }

    FieldBox {
        id: title
        Layout.fillWidth: true
        placeholder: "Title"
        error: form.localError !== "" && title.text.trim() === ""
        KeyNavigation.tab: start.input
        onTextChanged: form.localError = ""
        onAccepted: form.save()
        onCancelled: form.cancelled()
    }
    RowLayout {
        spacing: 6
        FieldBox {
            id: start
            Layout.preferredWidth: 64
            visible: !allDay.checked
            placeholder: "09:00"
            error: form.localError !== "" && CalEvent.minutes(text) < 0
            KeyNavigation.tab: end.input
            onTextChanged: form.localError = ""
            onAccepted: form.save()
            onCancelled: form.cancelled()
        }
        Label { visible: !allDay.checked; text: "–"; color: Theme.muted }
        FieldBox {
            id: end
            Layout.preferredWidth: 64
            visible: !allDay.checked
            placeholder: "10:00"
            error: form.localError !== "" && CalEvent.minutes(text) < 0
            KeyNavigation.tab: until.input
            onTextChanged: form.localError = ""
            onAccepted: form.save()
            onCancelled: form.cancelled()
        }
        Item { Layout.fillWidth: true }
        Label { text: "All day"; color: Theme.fgDim; font.pixelSize: Theme.fontSmall }
        Toggle { id: allDay; onToggled: wantOn => { checked = wantOn; form.localError = "" } }
    }
    RowLayout {
        spacing: 6
        Label { text: "Until"; color: Theme.fgDim; font.pixelSize: Theme.fontSmall }
        FieldBox {
            id: until
            Layout.preferredWidth: 100
            placeholder: "YYYY-MM-DD"
            error: form.localError !== "" && !CalEvent.validDate(text)
            KeyNavigation.tab: title.input
            onTextChanged: form.localError = ""
            onAccepted: form.save()
            onCancelled: form.cancelled()
        }
        Btn { Layout.preferredWidth: 28; text: "‹"; onClicked: until.text = CalEvent.shiftDate(until.text, -1) }
        Btn { Layout.preferredWidth: 28; text: "›"; onClicked: until.text = CalEvent.shiftDate(until.text, 1) }
        CalPicker { id: picker; Layout.fillWidth: true; calendars: form.calendars }
    }
    RowLayout {
        spacing: 6
        Btn { text: "Cancel"; onClicked: form.cancelled() }
        Btn { text: form.busy ? "Saving…" : "Save"; active: true; enabledLook: !form.busy; onClicked: form.save() }
        Label {
            Layout.fillWidth: true
            Layout.preferredWidth: 1                 // don't let a long message widen the popup
            visible: form.error !== ""
            text: form.error
            color: form.serverError !== "" && form.localError === "" && form.busy ? Theme.muted : Theme.red
            font.pixelSize: Theme.fontCaption
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            leftPadding: 4
        }
    }
}
