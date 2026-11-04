import QtQuick
import QtQuick.Layouts
import "launcher/js/PttKeys.js" as K

// One push-to-talk key of Settings > Voice (PttPrefs entry `entry`): the key field (type or press a key / mouse
// button), Apply, Clear and the key's status. A changed key is checked before it is applied: not a key / the same as
// another push-to-talk key (red, Apply refused), used by another bind or another app's global shortcut (orange,
// "Apply anyway"). Applied keys show Active (or Held while pressed), or why they do not work.
SettingRow {
    id: row
    required property var entry
    property real fieldW: 170
    property real ctrlH: 26
    property real ctrlInset: 9
    property real statusMaxW: 300      // the status text; its InfoTip follows it

    title: entry.label
    titleWrap: true                    // "Haitian Creole → English" wraps in the title column
    readonly property string saved: PttPrefs.keysOf(entry.name)
    readonly property var check: PttPrefs.check(entry.name, field.text)
    readonly property bool pending: field.text.trim() !== "" && check.keys !== saved
    readonly property bool blocked: check.error !== "" || check.duplicate !== ""
    readonly property var savedConflicts: saved !== "" ? PttPrefs.check(entry.name, saved).conflicts : []
    readonly property bool held: PttShortcuts.isHeld(entry.name)

    // [text, colour, glyph, tooltip]
    readonly property var status: {
        const list = cs => cs.map(c => c.text).join(", ")
        if (pending) {
            if (check.error !== "") return [check.error, Theme.red, Icons.error, ""]
            if (check.duplicate !== "") return ["Same as " + check.duplicate, Theme.red, Icons.error, ""]
            if (check.conflicts.length) return ["Also: " + list(check.conflicts), Theme.orange, Icons.warning,
                                                "Used by: " + list(check.conflicts) + ". Applying keeps both: they would fire together."]
            return [K.isMouse(check.keys) ? K.label(check.keys) : "Not applied", Theme.fgDim, "", ""]
        }
        if (saved === "") return ["Not set", Theme.muted, "", ""]
        if (held) return ["Held", Theme.accent, Icons.mic, ""]
        if (PttPrefs.applyError !== "") return ["Not applied", Theme.red, Icons.error, PttPrefs.applyError]
        if (PttPrefs.loaded && !PttPrefs.bound(entry.name)) return ["Not bound", Theme.red, Icons.error, "Hyprland has no bind for this key (config not loaded?)."]
        if (PttPrefs.loaded && !PttPrefs.registered(entry.name)) return ["Not registered", Theme.orange, Icons.warning, "The shell's global shortcut " + PttPrefs.appid + ":" + entry.name + " is not registered."]
        if (savedConflicts.length) return ["Active, also: " + list(savedConflicts), Theme.orange, Icons.warning, "Used by: " + list(savedConflicts)]
        return [K.isMouse(saved) ? "Active · " + K.label(saved) : "Active", Theme.fgDim, Icons.check, ""]
    }

    function apply() { if (pending && !blocked && PttPrefs.setKeys(entry.name, field.text)) field.text = PttPrefs.keysOf(entry.name) }
    function sync() { field.text = saved }
    Component.onCompleted: sync()
    onSavedChanged: sync()

    KeyCaptureField {
        id: field
        objectName: "ptt-key-" + row.entry.name
        Layout.preferredWidth: row.fieldW
        error: row.pending && row.blocked
        outerRadius: Theme.radiusPage; inset: row.ctrlInset
        implicitHeight: row.ctrlH
        onAccepted: row.apply()
        onCancelled: row.sync()
    }
    Btn {
        objectName: "btn-ptt-apply-" + row.entry.name
        text: row.pending && row.check.conflicts.length ? "Apply anyway" : "Apply"
        outerRadius: Theme.radiusPage; inset: row.ctrlInset
        implicitHeight: row.ctrlH
        enabledLook: row.pending && !row.blocked
        onClicked: row.apply()
    }
    Btn {
        objectName: "btn-ptt-clear-" + row.entry.name
        glyph: Icons.xmark
        tip: "Clear"
        outerRadius: Theme.radiusPage; inset: row.ctrlInset
        implicitHeight: row.ctrlH
        minWidth: row.ctrlH
        enabledLook: row.saved !== "" || field.text !== ""
        onClicked: { field.text = ""; PttPrefs.setKeys(row.entry.name, "") }
    }
    Icon {
        visible: row.status[2] !== ""
        text: row.status[2]
        font.pixelSize: Theme.iconSm
        color: row.status[1]
    }
    Label {
        objectName: "ptt-status-" + row.entry.name
        text: row.status[0]
        color: row.status[1]
        font.pixelSize: Theme.fontSmall
        elide: Text.ElideRight
        Layout.maximumWidth: row.statusMaxW
    }
    InfoTip { text: row.status[3]; icon: Icons.warning; color: row.status[1] }
    Item { Layout.fillWidth: true }
}
