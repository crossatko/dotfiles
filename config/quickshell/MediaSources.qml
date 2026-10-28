pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Every media source as one normalized list (MediaSource): MPRIS players (MprisSource, one per player) and the Twitch
// app (TwitchSource, a status file: it has no MPRIS) and the TV card (TvSource: a Send to TV session, first while it lasts,
// or what the TV plays by itself). Read by the bar's media chip (`active`), the media popup (`list`, `current` first) and the
// lock's playback card (`current`).
// Pick rule (the chip's since before this file): a sent TV session wins; else a playing MPRIS player, Twitch playing, the
// TV playing by itself, a paused MPRIS player with a title, Twitch paused, the TV paused; Twitch counts only while its
// file is fresh (45 s). `current` adds the cards' fallback: any MPRIS player.
// Adding a source: a MediaSource subtype that fills the fields it knows and handles `command`, instantiated here and
// added to `all` (and to the pick rule if it needs a place there).
Singleton {
    id: root

    Variants {
        id: mprisVariants
        model: Mpris.players.values   // qmllint disable missing-property
        MprisSource {}
    }
    TwitchSource { id: twitchSrc }
    TvSource { id: tvSrc }

    readonly property var mprisSources: mprisVariants.instances
    readonly property var twitch: twitchSrc.fresh ? twitchSrc : null
    readonly property var tv: tvSrc.on ? tvSrc : null       // the TV card (local players stay in `list`)

    readonly property var active: {
        const t = tv
        if (t && t.sent) return t                            // Send to TV session: wins while it lasts
        const ms = mprisSources
        const tw = twitch
        return ms.find(s => s.playing) || (tw && tw.playing ? tw : null) || (t && t.playing ? t : null)
            || ms.find(s => s.titled) || tw || t || null
    }
    readonly property var current: active || (mprisSources.length > 0 ? mprisSources[0] : null)
    // what the popup can switch between: `current` first, then the other sources that have something to show
    readonly property var list: {
        const c = current
        const rest = mprisSources.filter(s => s.titled && s !== c)
        if (twitch && twitch !== c) rest.push(twitch)
        if (tv && tv !== c) { if (tv.sent) rest.unshift(tv); else rest.push(tv) }
        return c ? [c].concat(rest) : rest
    }
}
