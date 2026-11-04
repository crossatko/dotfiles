pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings > Voice: the last dictation error, from DictationStatus (the record the pill writes; file and schema there).
// None = "No errors". Live: the singleton watches the file, and it is also re-read every few seconds while the page is
// open. Clear empties it.
ColumnLayout {
    id: le
    property real titleWidth: 120
    property int messageLines: 3                 // a long message wraps to this many lines, the rest is in the tooltip

    readonly property var err: DictationStatus.lastError   // { time (ISO string), message, code, count } or null
    property real now: Date.now()

    function ago(t) {
        const m = Math.max(0, Math.round((now - t) / 60000))
        return m < 1 ? "just now" : m < 60 ? m + " min ago" : m < 1440 ? Math.round(m / 60) + " h ago" : Math.round(m / 1440) + " d ago"
    }
    function when(e) {
        const t = Date.parse(e.time)
        if (isNaN(t)) return "–"
        return ago(t) + " · " + Qt.formatDateTime(new Date(t), "yyyy-MM-dd HH:mm:ss")
    }

    Layout.fillWidth: true
    spacing: Theme.pad

    Timer {
        interval: 3000; repeat: true; running: true
        onTriggered: { le.now = Date.now(); DictationStatus.reload() }
    }

    SectionHead {
        title: "Last error"
        Btn {
            objectName: "btn-voice-error-clear"
            visible: le.err !== null
            text: "Clear"
            outerRadius: Theme.radiusPage; inset: 9
            implicitHeight: 26
            onClicked: DictationStatus.clear()
        }
    }
    SettingRow {
        visible: le.err === null
        title: "Status"; titleWidth: le.titleWidth
        Label { objectName: "voice-error-none"; text: "No errors"; color: Theme.muted; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true }
    }
    SettingRow {
        visible: le.err !== null
        title: "Message"; titleWidth: le.titleWidth; titleTopAt: 9
        Label {
            id: msg
            objectName: "voice-error-message"
            text: le.err ? le.err.message : ""
            color: Theme.red
            font.pixelSize: Theme.fontSmall
            wrapMode: Text.Wrap
            maximumLineCount: le.messageLines
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        InfoTip { text: msg.truncated && le.err ? le.err.message : ""; maxWidth: 420 }
    }
    SettingRow {
        visible: le.err !== null
        title: "When"; titleWidth: le.titleWidth
        Label {
            objectName: "voice-error-when"
            text: le.err ? le.when(le.err) + (le.err.count > 1 ? " · " + le.err.count + " times" : "") : ""
            color: Theme.fgDim; font.pixelSize: Theme.fontSmall; elide: Text.ElideRight; Layout.fillWidth: true
        }
    }
    SettingRow {
        visible: le.err !== null && le.err.code !== ""
        title: "Code"; titleWidth: le.titleWidth
        Label { text: le.err ? le.err.code : ""; color: Theme.fgDim; font.pixelSize: Theme.fontSmall; elide: Text.ElideRight; Layout.fillWidth: true }
    }
}
