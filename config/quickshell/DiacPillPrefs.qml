pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The diacritics pill's view of the Diacritics preferences: `${XDG_STATE_HOME:-~/.local/state}/quickshell/diacritics.json`
// (QS_DIACRITICS_FILE overrides), written by Settings and read by the service and the key flow. Read only here, watched; a missing
// or malformed file / field = the default.
//   showText   show the real words of the text being fixed (default true); false = the generic neutral animation (privacy)
Singleton {
    id: prefs
    readonly property string filePath: {
        const env = Quickshell.env("QS_DIACRITICS_FILE")
        return env ? String(env) : Appearance.dir + "/diacritics.json"
    }
    property bool showText: true

    function parse(text) {
        let o = null
        try { o = JSON.parse(text) } catch (e) { /* malformed: defaults */ }
        showText = !(o && typeof o === "object" && o.show_text === false)
    }
    FileView {
        path: prefs.filePath
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: prefs.parse(text())
        onLoadFailed: prefs.parse("")
    }
}
