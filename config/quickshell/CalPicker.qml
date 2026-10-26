import QtQuick

// Calendar chooser of the "add event" form: a DropSelect of `calendars` ([{id, name, color}]) with each colour dot.
// `index` is the selected one (set by the form), `current` that calendar or null.
DropSelect {
    id: pick
    property var calendars: []
    property int index: -1
    readonly property var cal: index >= 0 && index < calendars.length ? calendars[index] : null

    options: calendars.map(c => ({ label: c.name, color: c.color }))
    currentIndex: index
    emptyText: "No calendar"
    onPicked: i => pick.index = i
}
