import QtQuick
import QtQuick.Layouts
import "launcher/js/CalEvent.js" as CalEvent

// Inline "add event" form of the calendar popup, drawn as an agenda-style card (left strip = the chosen
// calendar's colour): a big borderless title, then icon-led rows for the time (HH:MM - HH:MM or All day), the
// days (first day = the day picked in the grid, last day by DateStepper) and the calendar (CalPicker dropdown),
// and a footer with the error line, Cancel and Save. Enter saves, Esc cancels. `busy` and `serverError` come
// from the runner (CalCreate). Emits submit(...) only for input CalEvent.validate accepts.
Rectangle {
    id: form
    property date day: new Date()
    property bool busy: false
    property string serverError: ""
    property string localError: ""
    readonly property string error: localError !== "" ? localError : serverError
    readonly property string date: CalEvent.isoDate(day)    // first day (YYYY-MM-DD)
    property string until: date                              // last day (YYYY-MM-DD)
    readonly property int days: CalEvent.spanDays(date, until)
    property var calendars: []              // writable calendars [{id, name, color, primary}]
    property int lastCalendar: -1           // id used last time
    readonly property alias calendarIndex: picker.index
    readonly property real pad: Theme.pad
    readonly property int saveMinW: 72      // the Save button never shrinks below this
    readonly property int stripW: 3         // width of the calendar-colour strip
    readonly property int timeW: 62         // width of an HH:MM field
    signal submit(string title, string start, string end, bool allDay, string endDate, int calendarId)
    signal cancelled()

    implicitHeight: col.implicitHeight + 2 * pad
    radius: Theme.radiusItem
    color: Theme.itemFill

    // picking another day in the grid moves the last day along
    onDateChanged: if (until < date || !CalEvent.validDate(until)) until = date

    // fresh defaults every time the form opens; focus waits a tick (the popup surface gets keyboard focus late)
    function open() {
        title.text = ""
        const s = CalEvent.defaultStart(day, new Date())
        start.text = s
        end.text = CalEvent.plusHour(s)
        allDay.checked = false
        until = date
        picker.index = CalEvent.pickCalendar(calendars, lastCalendar)
        picker.open = false
        localError = ""
        Qt.callLater(() => title.focusField())
    }
    function save() {
        if (busy) return
        localError = CalEvent.validate(title.text, start.text, end.text, allDay.checked, date, until)
        if (localError === "") submit(title.text, start.text, end.text, allDay.checked, until, picker.cal ? picker.cal.id : -1)
    }
    function edited() { localError = "" }

    // the chosen calendar's colour, like the agenda cards (clear of the rounded corners)
    Rectangle {
        x: 0; y: form.radius
        width: form.stripW; height: form.height - form.radius * 2
        color: picker.cal ? picker.cal.color : Theme.accent
        Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: form.pad; leftMargin: form.pad + 2 }
        spacing: Theme.gapRow

        FieldBox {
            id: title
            Layout.fillWidth: true
            Layout.bottomMargin: Theme.gapTight
            flat: true
            pixelSize: Theme.fontSize + 2
            placeholder: "Event title"
            error: form.localError !== "" && title.text.trim() === ""
            KeyNavigation.tab: allDay.checked ? title.input : start.input
            onTextChanged: form.edited()
            onAccepted: form.save()
            onCancelled: form.cancelled()
        }

        FormRow {
            icon: Icons.clock      // clock
            FieldBox {
                id: start
                Layout.preferredWidth: form.timeW
                enabled: !allDay.checked            // dimmed and read-only while All day is on
                horizontalAlignment: TextInput.AlignHCenter
                maximumLength: 5
                placeholder: "09:00"
                error: form.localError !== "" && !allDay.checked && CalEvent.minutes(text) < 0
                KeyNavigation.tab: end.input
                onTextChanged: form.edited()
                onAccepted: form.save()
                onCancelled: form.cancelled()
            }
            Icon { text: Icons.arrowRight; font.pixelSize: Theme.fontTiny; color: Theme.muted; opacity: allDay.checked ? 0.4 : 1 }
            FieldBox {
                id: end
                Layout.preferredWidth: form.timeW
                enabled: !allDay.checked            // dimmed and read-only while All day is on
                horizontalAlignment: TextInput.AlignHCenter
                maximumLength: 5
                placeholder: "10:00"
                error: form.localError !== "" && !allDay.checked && CalEvent.minutes(text) < 0
                KeyNavigation.tab: title.input
                onTextChanged: form.edited()
                onAccepted: form.save()
                onCancelled: form.cancelled()
            }
            Item { Layout.fillWidth: true }
            Label {
                text: "All day"
                color: allDay.checked ? Theme.fg : Theme.fgDim
                font.pixelSize: Theme.fontSmall
                MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: allDay.toggled(!allDay.checked) }
            }
            Toggle { id: allDay; Layout.leftMargin: Theme.gapTight / 2; onToggled: wantOn => { checked = wantOn; form.edited() } }
        }

        FormRow {
            icon: Icons.calendarPlain      // calendar
            Label { text: Qt.formatDate(form.day, "ddd d MMM"); font.pixelSize: Theme.fontSmall }
            Icon { text: Icons.arrowRight; font.pixelSize: Theme.fontTiny; color: Theme.muted }
            DateStepper {
                id: lastDay
                value: form.until
                min: form.date
                sameText: "Same day"
                onMoved: v => { form.until = v; form.edited() }
            }
            Item { Layout.fillWidth: true }
            Label { visible: form.days > 1; text: form.days + " days"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
        }

        FormRow {
            icon: Icons.layerGroup      // layer group: which calendar
            CalPicker { id: picker; Layout.fillWidth: true; calendars: form.calendars; onIndexChanged: form.edited() }
        }

        // error / status line: unfolds above the buttons, full width (up to two lines), never widens the popup
        Item {
            Layout.fillWidth: true
            implicitHeight: form.error !== "" ? errRow.implicitHeight : 0
            opacity: form.error !== "" ? 1 : 0
            visible: implicitHeight > 0
            clip: true
            Behavior on implicitHeight { NumberAnimation { duration: Motion.moveMs; easing.type: Motion.easeMove } }
            Behavior on opacity { NumberAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
            FormRow {
                id: errRow
                width: parent.width
                readonly property bool status: form.busy && form.localError === ""     // "Starting omacal…" is progress, not a failure
                icon: status ? Icons.spinner : Icons.error
                iconColor: status ? Theme.fgDim : Theme.red
                Label {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumHeight: Theme.controlH
                    text: form.error
                    color: errRow.iconColor
                    font.pixelSize: Theme.fontSmall
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.gapTight
            spacing: Theme.controlGap
            Item { Layout.fillWidth: true }
            Btn { text: "Cancel"; onClicked: form.cancelled() }
            Btn {
                Layout.preferredWidth: Math.max(implicitWidth, form.saveMinW)
                text: form.busy ? "Saving…" : "Save"
                active: true
                enabledLook: !form.busy
                onClicked: form.save()
            }
        }
    }
}
