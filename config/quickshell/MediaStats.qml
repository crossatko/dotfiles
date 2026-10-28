import QtQuick

// A media source's badges, wrapping onto a second line when the card is narrow: LIVE pill, viewers (user glyph, 999 /
// 1.2K / 45.6K / 1.1M), stream time (clock glyph, H:MM:SS since `liveSince`, ticking once a second only while visible),
// with `withCategory` the category (gamepad glyph) and a `note` (muted caption: Offline, Paused, the player's name);
// the last two elide at the row's width. Hidden when it has nothing (an MPRIS player without a note). MediaPanel, LockMedia.
Flow {
    id: ms
    property bool live: false
    property int viewers: -1               // -1 = unknown
    property double liveSince: 0           // epoch ms, 0 = unknown
    property string category: ""
    property bool withCategory: false
    property string note: ""
    readonly property bool any: live || viewers >= 0 || liveSince > 0 || (withCategory && category !== "") || note !== ""
    readonly property real rowH: live ? pill.implicitHeight : noteLabel.implicitHeight   // one centre line (the pill's, if any)
    property double clock: Date.now()
    visible: any
    spacing: Theme.padSm

    // 999, 1.2K, 45.6K, 123K, 1.1M: one decimal under 100 units, cut (not rounded) like Twitch shows it
    function compact(n) {
        const fmt = (v, unit) => (v < 100 ? Math.floor(v * 10) / 10 : Math.floor(v)) + unit
        return n < 1000 ? String(n) : n < 1e6 ? fmt(n / 1000, "K") : fmt(n / 1e6, "M")
    }
    function elapsed(since, now) {
        const s = Math.max(0, Math.floor((now - since) / 1000))
        return Math.floor(s / 3600) + ":" + String(Math.floor(s / 60) % 60).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0")
    }

    Timer {
        interval: 1000; repeat: true; triggeredOnStart: true
        running: ms.visible && ms.liveSince > 0
        onTriggered: ms.clock = Date.now()
    }

    LivePill { id: pill; visible: ms.live }
    MediaBadge { objectName: "media-viewers"; height: ms.rowH; icon: Icons.user; text: ms.viewers >= 0 ? ms.compact(ms.viewers) : "" }
    MediaBadge { objectName: "media-uptime"; height: ms.rowH; icon: Icons.clock; text: ms.liveSince > 0 ? ms.elapsed(ms.liveSince, ms.clock) : "" }
    MediaBadge {
        objectName: "media-category"
        width: Math.min(implicitWidth, ms.width)
        height: ms.rowH
        visible: ms.withCategory && text !== ""
        icon: Icons.gamepad
        text: ms.category
    }
    Label {
        id: noteLabel
        width: Math.min(implicitWidth, ms.width)
        height: ms.rowH
        visible: text !== ""
        text: ms.note
        color: Theme.muted
        font.pixelSize: Theme.fontCaption
        elide: Text.ElideRight
    }
}
