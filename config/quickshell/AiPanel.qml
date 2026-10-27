pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// AI popup (sparkles chip): every Claude Code profile (~/.claude*) with its plan and subscription limits
// (session / weekly windows, reset countdowns), local estimates where there are no limits, and other AI tools
// found on the machine. Data: AiUsage.qml -> bin/ai-usage.
ColumnLayout {
    id: ap
    readonly property int listMaxH: 620     // the profile list scrolls beyond this height
    spacing: Theme.padSm

    readonly property var profiles: AiUsage.profiles
    readonly property var others: AiUsage.others

    function statusColor(s) {
        return s === "expired" || s === "paused" || s === "forbidden" ? Theme.orange
             : s === "error" ? Theme.red : Theme.fgDim
    }
    function statsLine(s) {
        if (!s) return ""
        return s.messages + (s.messages === 1 ? " msg" : " msgs") + " · " + AiUsage.compact(s.input + s.output) + " tokens"
             + (s.cacheRead > 0 ? " · " + AiUsage.compact(s.cacheRead) + " cached" : "")
    }

    PanelHeader {
        title: "AI usage"
        showStatus: true
        // the error sits in the status line only while there are cards to keep; with none it is the empty state below
        status: AiUsage.loading && !AiUsage.loaded ? "Loading…" : AiUsage.error !== "" && ap.profiles.length > 0 ? AiUsage.error : ""
        statusColor: AiUsage.error !== "" ? Theme.red : Theme.fgDim
        Btn {
            icon: true
            text: Icons.retry
            active: AiUsage.loading
            onClicked: AiUsage.refresh(true)
        }
    }

    EmptyState {
        readonly property bool failed: AiUsage.error !== ""
        visible: (AiUsage.loaded || failed) && ap.profiles.length === 0
        icon: failed ? Icons.warning : Icons.user
        text: failed ? "No usage data" : "No Claude profiles found"
        hint: failed ? AiUsage.error : "Looked for ~/.claude* directories (one per CLAUDE_CONFIG_DIR). Run claude and log in, then refresh."
    }

    Flickable {
        id: flick
        visible: ap.profiles.length > 0 || ap.others.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? Math.min(ap.listMaxH, content.implicitHeight) : 0
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: content
            width: flick.width
            spacing: Theme.padSm

            SectionHead {
                visible: ap.profiles.length > 0
                title: "Claude Code"
                detail: ap.profiles.length + (ap.profiles.length === 1 ? " profile" : " profiles")
            }

            Repeater {
                model: ap.profiles
                Notice {
                    id: card
                    required property var modelData
                    readonly property var p: modelData
                    spacing: Theme.padSm
                    // width of the "Today" / "7 days" label column of the local estimate
                    readonly property real dayW: Math.ceil(Math.max(dayA.advanceWidth, dayB.advanceWidth)) + Theme.gapRow
                    TextMetrics { id: dayA; font.family: Theme.font; font.pixelSize: Theme.fontSmall; text: "Today" }
                    TextMetrics { id: dayB; font.family: Theme.font; font.pixelSize: Theme.fontSmall; text: "7 days" }

                    ColumnLayout {
                        id: cardCol
                        Layout.fillWidth: true
                        spacing: Theme.padSm

                        // account line: label, plan badge, profile dir
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.gapRow
                            Label { text: card.p.label || card.p.dir; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                            Pill { visible: (card.p.plan || "") !== ""; text: card.p.plan || "" }
                        }
                        Label {
                            visible: text !== ""
                            Layout.topMargin: -Theme.controlGap
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: [card.p.label !== card.p.dir ? "~/" + card.p.dir : "", card.p.org || ""].filter(s => s).join("  ·  ")
                            color: Theme.muted; font.pixelSize: Theme.fontCaption
                        }

                        // problem / note (expired, offline, rate limited, API key, ...)
                        RowLayout {
                            visible: (card.p.message || "") !== ""
                            Layout.fillWidth: true
                            spacing: Theme.gapRow
                            Icon {
                                text: Icons.warning
                                visible: ["expired", "paused", "forbidden", "error", "nologin"].indexOf(card.p.status) >= 0
                                color: ap.statusColor(card.p.status)
                                font.pixelSize: Theme.iconSm
                            }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: card.p.message || ""
                                color: ap.statusColor(card.p.status)
                                font.pixelSize: Theme.fontSmall
                            }
                        }

                        Repeater {
                            model: card.p.windows || []
                            AiLimit {
                                required property var modelData
                                win: modelData
                                stale: card.p.stale === true
                            }
                        }
                        AiLimit {
                            readonly property var ex: card.p.extra
                            visible: ex !== null && ex !== undefined && typeof ex.percent === "number"
                            stale: card.p.stale === true
                            win: ex ? { title: "Extra usage", percent: ex.percent || 0, resetsAt: null,
                                        detail: ex.used !== null && ex.limit !== null ? ex.used.toFixed(2) + " / " + ex.limit.toFixed(2) + " " + (ex.currency || "") : "" } : ({})
                            resetText: "monthly"
                        }

                        // local estimate from the session logs (no subscription windows to show)
                        ColumnLayout {
                            visible: !!card.p.local && (card.p.windows || []).length === 0
                            Layout.fillWidth: true
                            spacing: Theme.gapTight
                            Label { text: "Local estimate · session logs" + (card.p.local && card.p.local.partial ? " (still counting)" : ""); color: Theme.fgDim; font.pixelSize: Theme.fontCaption; font.bold: true }
                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Today"; font.pixelSize: Theme.fontSmall; Layout.preferredWidth: card.dayW }
                                Label { text: card.p.local ? ap.statsLine(card.p.local.today) : ""; color: Theme.fgDim; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; elide: Text.ElideRight }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "7 days"; font.pixelSize: Theme.fontSmall; Layout.preferredWidth: card.dayW }
                                Label { text: card.p.local ? ap.statsLine(card.p.local.week) : ""; color: Theme.fgDim; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; elide: Text.ElideRight }
                            }
                        }

                        Label {
                            visible: !!card.p.fetchedAt && (card.p.windows || []).length > 0
                            Layout.alignment: Qt.AlignRight
                            text: "updated " + AiUsage.ago(card.p.fetchedAt)
                            color: Theme.muted; font.pixelSize: Theme.fontTiny
                        }
                    }
                }
            }

            SectionHead {
                visible: ap.others.length > 0
                Layout.topMargin: Theme.gapTight
                title: "Other tools"
            }
            Repeater {
                model: ap.others
                ColumnLayout {
                    id: other
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.gapRow
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.gapRow
                        Label { text: other.modelData.name; font.bold: true }
                        Label { text: other.modelData.detail || ""; color: Theme.fgDim; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { visible: !!other.modelData.lastUsed; text: other.modelData.lastUsed ? AiUsage.ago(other.modelData.lastUsed) : ""; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                    }
                    Repeater {
                        model: other.modelData.windows || []
                        AiLimit { required property var modelData; win: modelData }
                    }
                }
            }
        }
    }
}
