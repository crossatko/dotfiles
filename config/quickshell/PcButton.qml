import QtQuick

// Play on PC (TvPc) for the TV card (a HandoffButton, the reverse of TvButton): shown while the media popup shows the TV
// source (TvSource). Usable when TvPc can resolve what the TV plays into a PC player (a sent session; YouTube / Jellyfin
// the TV plays by itself, after a lookup); otherwise dimmed, the tooltip says why (e.g. Twitch's TV app reports no
// channel or video). Glyph: laptop at rest, search while it looks the item up, circle-play while the player opens, check,
// warning (tooltip = the error). A click while busy cancels. MediaPanel (never the lock card).
HandoffButton {
    id: pb
    property var source: null

    objectName: "btn-media-pc"
    shown: source !== null && source.kind === "tv" && TvSession.card !== null
    usable: TvPc.usable
    phase: TvPc.phase
    restGlyph: Icons.laptop
    onActivated: TvPc.press()
    tipText: phase === "failed" ? TvPc.error
        : phase === "finding" ? "Looking it up · click cancels"
        : phase === "opening" ? "Opening on this PC · click cancels"
        : phase === "sent" ? (TvPrefs.dryRun ? "Dry run: logged" : "Playing on this PC")
        : TvPc.hint + (TvPrefs.dryRun && usable ? " (dry run)" : "")
}
