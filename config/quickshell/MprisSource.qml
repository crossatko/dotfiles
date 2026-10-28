import QtQuick

// An MPRIS player as a media source (MediaSources makes one per player). Pass-through: same fields, same controls as
// the player itself; `mpris` stays the raw player for the seek bar and the bar's brand guess.
MediaSource {
    id: ms
    required property var modelData
    key: "mpris:" + (modelData.dbusName || modelData.identity || "")
    kind: "mpris"
    mpris: modelData
    title: modelData.trackTitle || ""
    subtitle: modelData.trackArtist || ""
    caption: modelData.identity || ""
    name: caption
    chipText: title + (subtitle ? "  ·  " + subtitle : "")
    artUrl: modelData.trackArtUrl || ""
    playing: !!modelData.isPlaying
    titled: title !== ""
    canToggle: true
    transport: true
    canPrev: !!modelData.canGoPrevious
    canNext: !!modelData.canGoNext
    onCommand: what => {
        if (what === "toggle") modelData.togglePlaying()
        else if (what === "previous") modelData.previous()
        else if (what === "next") modelData.next()
    }
}
