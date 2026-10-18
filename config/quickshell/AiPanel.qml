import QtQuick
import QtQuick.Layouts

// AI popup (sparkles chip): every Claude Code profile (~/.claude*) with its plan and subscription limits
// (session / weekly windows, reset countdowns), local estimates where there are no limits, and other AI tools
// found on the machine. Data: AiUsage.qml -> bin/ai-usage.
ColumnLayout {
    id: ap
    spacing: 10

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

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Label { text: "AI usage"; font.pixelSize: 17; font.bold: true }
        Label {
            Layout.fillWidth: true
            text: AiUsage.loading && !AiUsage.loaded ? "Loading…" : AiUsage.error !== "" ? AiUsage.error : ""
            color: AiUsage.error !== "" ? Theme.red : Theme.fgDim
            font.pixelSize: 12
            elide: Text.ElideRight
        }
        Btn {
            icon: true
            text: ""
            active: AiUsage.loading
            onClicked: AiUsage.refresh(true)
        }
    }

    // empty state
    Rectangle {
        visible: AiUsage.loaded && ap.profiles.length === 0
        Layout.fillWidth: true
        implicitHeight: emptyCol.implicitHeight + 24
        radius: Theme.radiusItem
        color: Theme.alpha(Theme.fg, 0.06)
        border.width: 1
        border.color: Theme.alpha(Theme.overlay, 0.6)
        ColumnLayout {
            id: emptyCol
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
            spacing: 4
            Label { text: "No Claude profiles found"; font.bold: true }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "Looked for ~/.claude* directories (one per CLAUDE_CONFIG_DIR). Run claude and log in, then refresh."
                color: Theme.fgDim; font.pixelSize: 12
            }
        }
    }

    Flickable {
        id: flick
        visible: ap.profiles.length > 0 || ap.others.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? Math.min(620, content.implicitHeight) : 0
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: content
            width: flick.width
            spacing: 10

            SectionHead {
                visible: ap.profiles.length > 0
                title: "Claude Code"
                detail: ap.profiles.length + (ap.profiles.length === 1 ? " profile" : " profiles")
            }

            Repeater {
                model: ap.profiles
                Rectangle {
                    id: card
                    required property var modelData
                    readonly property var p: modelData
                    Layout.fillWidth: true
                    implicitHeight: cardCol.implicitHeight + 24
                    radius: Theme.radiusItem
                    color: Theme.alpha(Theme.fg, 0.05)
                    border.width: 1
                    border.color: Theme.alpha(Theme.overlay, 0.55)

                    ColumnLayout {
                        id: cardCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 10

                        // account line: label, plan badge, profile dir
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Label { text: card.p.label || card.p.dir; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                            Rectangle {
                                visible: (card.p.plan || "") !== ""
                                implicitWidth: planText.implicitWidth + 12
                                implicitHeight: 20
                                radius: Math.min(3, Theme.radius)
                                color: Theme.alpha(Theme.accent, 0.16)
                                border.width: 1
                                border.color: Theme.alpha(Theme.accent, 0.6)
                                Label { id: planText; anchors.centerIn: parent; text: card.p.plan || ""; color: Theme.accent; font.pixelSize: 11; font.bold: true }
                            }
                        }
                        Label {
                            visible: text !== ""
                            Layout.topMargin: -6
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: [card.p.label !== card.p.dir ? "~/" + card.p.dir : "", card.p.org || ""].filter(s => s).join("  ·  ")
                            color: Theme.muted; font.pixelSize: 11
                        }

                        // problem / note (expired, offline, rate limited, API key, ...)
                        RowLayout {
                            visible: (card.p.message || "") !== ""
                            Layout.fillWidth: true
                            spacing: 8
                            Icon {
                                text: ""
                                visible: ["expired", "paused", "forbidden", "error", "nologin"].indexOf(card.p.status) >= 0
                                color: ap.statusColor(card.p.status)
                                font.pixelSize: 12
                            }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: card.p.message || ""
                                color: ap.statusColor(card.p.status)
                                font.pixelSize: 12
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
                            spacing: 4
                            Label { text: "Local estimate · session logs" + (card.p.local && card.p.local.partial ? " (still counting)" : ""); color: Theme.fgDim; font.pixelSize: 11; font.bold: true }
                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Today"; font.pixelSize: 12; Layout.preferredWidth: 56 }
                                Label { text: card.p.local ? ap.statsLine(card.p.local.today) : ""; color: Theme.fgDim; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "7 days"; font.pixelSize: 12; Layout.preferredWidth: 56 }
                                Label { text: card.p.local ? ap.statsLine(card.p.local.week) : ""; color: Theme.fgDim; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
                            }
                        }

                        Label {
                            visible: !!card.p.fetchedAt && (card.p.windows || []).length > 0
                            Layout.alignment: Qt.AlignRight
                            text: "updated " + AiUsage.ago(card.p.fetchedAt)
                            color: Theme.muted; font.pixelSize: 10
                        }
                    }
                }
            }

            SectionHead {
                visible: ap.others.length > 0
                Layout.topMargin: 4
                title: "Other tools"
            }
            Repeater {
                model: ap.others
                ColumnLayout {
                    id: other
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Label { text: other.modelData.name; font.bold: true }
                        Label { text: other.modelData.detail || ""; color: Theme.fgDim; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { visible: !!other.modelData.lastUsed; text: other.modelData.lastUsed ? AiUsage.ago(other.modelData.lastUsed) : ""; color: Theme.muted; font.pixelSize: 11 }
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
