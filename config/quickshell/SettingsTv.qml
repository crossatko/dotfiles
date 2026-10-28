pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Settings -> TV: the target of Send to TV (TvCast; the button sits in the media popup's card). One entry per physical TV
// (TvCast.candidates = Js.tvGroups: its HA devices merged, named by the device name), icon + name + a state dot (green
// on, dim off, red unavailable); which integration sends is TvCast's choice per send, never shown. Listed from HA on
// open; "Show TV playback" (auto-detect: the TV card for what the TV plays by itself), "Pause here" and "Dry run" (TvPrefs, tv.json); "Test" opens the YouTube app's home on the TV (the same flow as a
// send: wakes it first). Without Home Assistant credentials only a notice.
Item {
    id: pg
    implicitHeight: col.implicitHeight

    readonly property int titleW: 120
    readonly property int pickW: 300          // the TV dropdown
    function dot(state) { return state === "on" ? Theme.green : state === "off" ? Theme.alpha(Theme.muted, 0.6) : Theme.red }
    // a model note only to tell two TVs of the same name apart
    readonly property var options: [{ label: "None" }].concat(TvCast.candidates.map(c => {
        const twin = TvCast.candidates.some(o => o !== c && o.name === c.name)
        return twin && c.model !== "" ? { label: c.name, icon: Icons.tv, color: pg.dot(TvCast.stateOf(c)), note: c.model }
                                      : { label: c.name, icon: Icons.tv, color: pg.dot(TvCast.stateOf(c)) }
    }))
    readonly property int currentIndex: {
        if (TvPrefs.entity === "") return 0
        const i = TvCast.candidates.findIndex(c => c.members.some(m => m.id === TvPrefs.entity))
        return i >= 0 ? i + 1 : -1
    }
    Component.onCompleted: TvCast.loadCandidates()

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 12

        EmptyState {
            visible: !HomeAssistant.configured
            icon: Icons.home
            text: "No Home Assistant"
            hint: "HA_URL / HA_TOKEN in ~/.config/hypr/.secrets"
        }

        SettingRow {
            visible: HomeAssistant.configured
            title: "TV"; titleWidth: pg.titleW
            titleTopAt: Theme.controlH / 2
            DropSelect {
                objectName: "tv-entity"
                Layout.preferredWidth: pg.pickW
                options: pg.options
                currentIndex: pg.currentIndex
                headIcon: pg.currentIndex !== 0 ? Icons.tv : ""
                headText: pg.currentIndex >= 0 ? "" : TvCast.candidatesBusy ? "Loading…" : (TvPrefs.tvName || TvCast.tvName)
                onPicked: i => TvPrefs.setTv(i === 0 ? null : TvCast.candidates[i - 1])
            }
            InfoTip {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: (Theme.controlH - height) / 2
                text: "YouTube, Twitch, Wholphin (YouTube only on Cast-only TVs). Off TVs are woken first."
            }
            Item { Layout.fillWidth: true }
        }

        PrefToggle { visible: HomeAssistant.configured; titleWidth: pg.titleW; store: TvPrefs; key: "autoDetect"; label: "Show TV playback" }
        PrefToggle { visible: HomeAssistant.configured; titleWidth: pg.titleW; store: TvPrefs; key: "pauseAfter"; label: "Pause here after sending" }
        SettingRow {
            visible: HomeAssistant.configured
            titleWidth: pg.titleW
            Toggle {
                objectName: "toggle-dryRun"
                checked: TvPrefs.dryRun
                onToggled: want => TvPrefs.set("dryRun", want)
            }
            Label { text: "Dry run"; color: Theme.fgDim; font.pixelSize: Theme.fontSmall }
            InfoTip { text: "Logs the calls instead of sending them: qs ipc call tvcast last" }
            Item { Layout.fillWidth: true }
        }

        SettingRow {
            visible: HomeAssistant.configured && TvPrefs.entity !== ""
            title: "Test"; titleWidth: pg.titleW
            Btn {
                objectName: "btn-tv-test"
                text: TvCast.busy && TvCast.sourceKey === "" ? "Cancel" : "Open YouTube"
                outerRadius: Theme.radiusPage; inset: 9
                onClicked: { if (TvCast.busy) TvCast.cancel(); else { TvCast.sourceKey = ""; TvCast.test() } }
            }
            Label {
                visible: TvCast.sourceKey === "" && TvCast.phase !== ""
                text: TvCast.phase === "failed" ? TvCast.error : TvCast.phase === "sent" ? (TvPrefs.dryRun ? "Logged" : "Sent")
                    : TvCast.phase === "waking" ? "Waking…" : "Opening…"
                color: TvCast.phase === "failed" ? Theme.red : Theme.fgDim
                font.pixelSize: Theme.fontCaption
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        PageReset {
            objectName_: "btn-tv-reset"
            dirty: Object.keys(TvPrefs.data).length > 0
            info: "Saved in tv.json."
            onReset: TvPrefs.reset()
        }
    }
}
