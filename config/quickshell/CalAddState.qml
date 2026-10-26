import QtQuick
import Quickshell
import Quickshell.Io

// Remembers the calendar last used in the calendar popup's "add event" form (numeric omacal calendar id only):
// ${XDG_STATE_HOME:-~/.local/state}/quickshell/cal-add.json (QS_CAL_ADD_FILE overrides).
Item {
    id: st
    readonly property string filePath: {
        const env = Quickshell.env("QS_CAL_ADD_FILE")
        if (env) return String(env)
        const xdg = Quickshell.env("XDG_STATE_HOME")
        return (xdg ? String(xdg) : Quickshell.env("HOME") + "/.local/state") + "/quickshell/cal-add.json"
    }
    property int lastId: -1
    signal loadedState()

    function remember(id) {
        if (id === lastId) return
        lastId = id
        Quickshell.execDetached(["mkdir", "-p", filePath.substring(0, filePath.lastIndexOf("/"))])
        saveTimer.restart()
    }
    // mkdir runs detached: give it a moment before the write
    Timer { id: saveTimer; interval: 300; onTriggered: file.setText(JSON.stringify({ lastCalendar: st.lastId })) }

    FileView {
        id: file
        path: st.filePath
        printErrors: false
        onLoaded: { try { const v = JSON.parse(text()).lastCalendar; if (Number.isInteger(v)) st.lastId = v } catch (e) {} st.loadedState() }
    }
}
