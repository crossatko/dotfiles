import QtQuick

// Send to TV (TvCast) for one media source: an icon button like the transport's. Shown only when it would work
// (TvCast.shownFor: HA answering, a TV set and available (off / standby too: it wakes it), a recognised source with an
// identified id); fades in / out in place (the caller keeps its slot, nothing moves). The glyph is the progress: tv at
// rest, power while the TV wakes, circle-play while the app opens (both pulse; still with motion off), check once
// sent, warning when it failed (the tooltip says why), then tv again. A click while busy cancels. Hover = what it does
// and where. MediaPanel (never the lock card).
Btn {
    id: tb
    property var source: null
    readonly property bool mine: source !== null && TvCast.sourceKey === source.key && TvCast.phase !== ""
    readonly property string phase: mine ? TvCast.phase : ""
    readonly property bool working: phase === "waking" || phase === "opening"
    readonly property bool shown: source !== null && (mine || TvCast.shownFor(source))
    readonly property string tvName: TvCast.tvName

    objectName: "btn-media-tv"
    icon: true
    text: phase === "waking" ? Icons.power : phase === "opening" ? Icons.circlePlay : phase === "sent" ? Icons.check
        : phase === "failed" ? Icons.warning : Icons.tv
    active: working
    ink: phase === "failed" ? Theme.red : working || phase === "sent" ? Theme.accent : Theme.fg
    opacity: shown ? 1 : 0
    visible: opacity > 0
    enabled: shown
    Behavior on opacity { NumberAnimation { duration: Motion.ms(Motion.moveMs); easing.type: Motion.easeEnter } }
    onClicked: if (tb.source) TvCast.press(tb.source)

    // a browser player's video id comes from its tab: ask once the card shows it (TvCast asks again after a miss)
    readonly property string lookupKey: source && source.kind === "mpris" && source.mpris ? TvCast.tabKey(source.mpris) : ""
    onLookupKeyChanged: if (lookupKey !== "") TvCast.lookup(source)
    Component.onCompleted: if (lookupKey !== "") TvCast.lookup(source)
    readonly property bool pending: lookupKey !== "" && TvCast.tabs[lookupKey] === undefined
    onPendingChanged: if (pending) TvCast.lookup(source)          // the helper's retry dropped the cache entry

    SequentialAnimation on inkOpacity {
        running: tb.working && !Motion.reduced
        loops: Animation.Infinite
        onRunningChanged: if (!running) tb.inkOpacity = 1
        NumberAnimation { to: 0.35; duration: Theme.busyPulseMs; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: Theme.busyPulseMs; easing.type: Easing.InOutSine }
    }

    HoverHandler { id: hh }
    TipBubble {
        anchors.fill: parent
        shown: hh.hovered && tb.shown
        text: tb.phase === "failed" ? TvCast.error
            : tb.phase === "waking" ? "Waking " + tb.tvName + " · click cancels"
            : tb.phase === "opening" ? "Opening on " + tb.tvName + " · click cancels"
            : tb.phase === "sent" ? (TvPrefs.dryRun ? "Dry run: logged" : "On " + tb.tvName)
            : "Send to " + tb.tvName + (TvPrefs.dryRun ? " (dry run)" : "")
    }
}
