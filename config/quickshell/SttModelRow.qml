pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// One speech model in Settings (SttModelsSection): name with plain-text capability marks (translation, Czech quality,
// the role it is recommended for), a line with the size on disk and the VRAM, the catalog's note, and its state:
// not installed (Download), downloading (a progress bar with percent, speed and time left, Cancel), installed
// (Live / Final buttons that assign the role, Delete), failed or interrupted (the reason in red, Resume keeps the bytes
// already loaded). Everything comes from SttModels; `m` is one entry of SttModels.models.
ListRow {
    id: row
    property var m: ({})

    readonly property bool mine: SttModels.downloading === m.name
    readonly property var failure: SttModels.failures[m.name] || null
    readonly property bool partial: m.partialBytes > 0 && !mine
    readonly property bool armed: confirm.running
    readonly property color czechColor: m.czech === "good" ? Theme.green : m.czech === "fair" ? Theme.yellow : Theme.red
    readonly property real shownProgress: mine ? SttModels.progress : m.size > 0 ? m.partialBytes / m.size : 0

    rowH: 52
    interactive: false
    expanded: true
    bodyGap: Theme.gapRow

    RowText {
        title: row.m.label
        sub: SttModels.sizeText(row.m.size) + " on disk  ·  ~" + row.m.vramGb + " GB VRAM"
    }

    // installed: roles
    Btn {
        visible: row.m.installed
        objectName: "btn-role-live-" + row.m.name
        text: "Live"
        active: SttModels.live === row.m.name
        outerRadius: Theme.radiusItem; inset: Theme.gapRow
        implicitHeight: 26
        tip: "Use for the live passes while the key is held"
        onClicked: SttModels.setRole("live", row.m.name)
    }
    Btn {
        visible: row.m.installed
        objectName: "btn-role-final-" + row.m.name
        text: "Final"
        active: SttModels.final_ === row.m.name
        enabledLook: row.m.translate          // still clickable: SttModels explains why it is refused
        outerRadius: Theme.radiusItem; inset: Theme.gapRow
        implicitHeight: 26
        tip: "Use for the final pass and translation"
        onClicked: SttModels.setRole("final", row.m.name)
    }
    Btn {
        visible: row.m.installed && !row.mine
        objectName: "btn-delete-" + row.m.name
        glyph: Icons.xmark
        text: row.armed ? "Delete?" : ""
        ink: row.armed ? Theme.red : Theme.fg
        tip: row.armed ? "" : "Delete " + row.m.label
        outerRadius: Theme.radiusItem; inset: Theme.gapRow
        implicitHeight: 26
        onClicked: { if (row.armed) { confirm.stop(); SttModels.remove(row.m.name) } else confirm.restart() }
    }
    Timer { id: confirm; interval: 3000 }

    // not installed / interrupted: download, resume
    Btn {
        visible: !row.m.installed && !row.mine
        objectName: "btn-download-" + row.m.name
        glyph: row.failure || row.partial ? Icons.retry : Icons.download
        text: row.failure ? "Retry" : row.partial ? "Resume" : "Download"
        enabledLook: !SttModels.busy
        outerRadius: Theme.radiusItem; inset: Theme.gapRow
        implicitHeight: 26
        onClicked: SttModels.download(row.m.name)
    }
    Btn {
        visible: row.partial && !row.m.installed
        objectName: "btn-discard-" + row.m.name
        glyph: Icons.xmark
        tip: "Delete the partial download"
        outerRadius: Theme.radiusItem; inset: Theme.gapRow
        implicitHeight: 26
        onClicked: SttModels.discardPartial(row.m.name)
    }
    Btn {
        visible: row.mine
        objectName: "btn-cancel-" + row.m.name
        text: "Cancel"
        outerRadius: Theme.radiusItem; inset: Theme.gapRow
        implicitHeight: 26
        onClicked: SttModels.cancel()
    }

    // below the head line: the note, then the progress or the failure
    body: [
        // plain-text capability marks (warnings in colour)
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.pad
            Label {
                visible: row.m.recommended !== ""
                text: row.m.recommended === "live" ? "recommended for live" : "recommended for final + translate"
                color: Theme.fg; font.pixelSize: Theme.fontCaption
            }
            Label {
                text: row.m.translate ? "translates" : "cannot translate"
                color: row.m.translate ? Theme.green : Theme.yellow; font.pixelSize: Theme.fontCaption
            }
            Label {
                text: "Czech: " + row.m.czech
                color: row.czechColor; font.pixelSize: Theme.fontCaption
            }
            Item { Layout.fillWidth: true }
        },
        Label {
            Layout.fillWidth: true
            text: row.m.note
            color: Theme.muted; font.pixelSize: Theme.fontCaption
            wrapMode: Text.WordWrap
        },
        RowLayout {
            visible: row.mine || row.partial
            Layout.fillWidth: true
            Layout.topMargin: Theme.gapTight
            spacing: Theme.gapRow
            Meter {
                objectName: "model-progress-" + row.m.name
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                value: row.shownProgress
                fillColor: row.mine ? Theme.accent : Theme.muted
                animMs: 200
            }
            Label {
                objectName: "model-progress-text-" + row.m.name
                color: Theme.fgDim; font.pixelSize: Theme.fontCaption
                text: !row.mine ? "paused at " + Math.round(row.shownProgress * 100) + "%"
                    : SttModels.phase === "verifying" ? "verifying " + Math.round(SttModels.progress * 100) + "%"
                    : SttModels.phase === "retrying" ? "connection lost, retrying…"
                    : Math.round(SttModels.progress * 100) + "%  ·  " + SttModels.speedText(SttModels.bps)
                      + (SttModels.eta >= 0 ? "  ·  " + SttModels.etaText(SttModels.eta) : "")
            }
        },
        Label {
            visible: row.failure !== null && !row.mine
            objectName: "model-error-" + row.m.name
            Layout.fillWidth: true
            text: row.failure ? row.failure.message + (row.failure.resumable && row.partial ? ". The part already downloaded is kept." : "") : ""
            color: Theme.red; font.pixelSize: Theme.fontCaption
            wrapMode: Text.WordWrap
        },
        Label {
            visible: row.m.damaged && !row.m.installed
            Layout.fillWidth: true
            text: "The file on disk is incomplete or the wrong size. Download replaces it."
            color: Theme.yellow; font.pixelSize: Theme.fontCaption
            wrapMode: Text.WordWrap
        }
    ]
}
