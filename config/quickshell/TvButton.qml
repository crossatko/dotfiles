import QtQuick

// Send to TV (TvCast) for one media source (a HandoffButton). Shown only when it would work (TvCast.shownFor: HA
// answering, a TV set and available (off / standby too: it wakes it), a recognised source with an identified id). Glyph:
// tv at rest, power while the TV wakes, circle-play while the app opens, check once sent, warning when it failed. A click
// while busy cancels. Hover = what it does and where (a Twitch past broadcast: the TV app resumes from the account, not
// from here). MediaPanel (never the lock card).
HandoffButton {
    id: tb
    property var source: null
    readonly property bool mine: source !== null && TvCast.sourceKey === source.key && TvCast.phase !== ""
    readonly property string tvName: TvCast.tvName

    objectName: "btn-media-tv"
    phase: mine ? TvCast.phase : ""
    shown: source !== null && (mine || TvCast.shownFor(source))
    restGlyph: Icons.tv
    onActivated: if (tb.source) TvCast.press(tb.source)
    tipText: phase === "failed" ? TvCast.error
        : phase === "waking" ? "Waking " + tvName + " · click cancels"
        : phase === "opening" ? "Opening on " + tvName + " · click cancels"
        : phase === "sent" ? (TvPrefs.dryRun ? "Dry run: logged" : "On " + tvName)
        : "Send to " + tvName + (shown ? TvCast.startNote(source) : "") + (TvPrefs.dryRun ? " (dry run)" : "")

    // a browser player's video id comes from its tab: ask once the card shows it (TvCast asks again after a miss)
    readonly property string lookupKey: source && source.kind === "mpris" && source.mpris ? TvCast.tabKey(source.mpris) : ""
    onLookupKeyChanged: if (lookupKey !== "") TvCast.lookup(source)
    Component.onCompleted: if (lookupKey !== "") TvCast.lookup(source)
    readonly property bool pending: lookupKey !== "" && TvCast.tabs[lookupKey] === undefined
    onPendingChanged: if (pending) TvCast.lookup(source)          // the helper's retry dropped the cache entry
}
