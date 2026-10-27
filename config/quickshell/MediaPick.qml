import QtQuick
import Quickshell.Services.Mpris

// The MPRIS player a media card shows (MediaPanel, LockMedia): the playing one, else one with a title, else the first;
// null = none. (The bar chip has its own pick: it also knows the Twitch app and the service brand.)
QtObject {
    readonly property var player: {
        const ps = Mpris.players.values   // qmllint disable missing-property
        return ps.find(p => p.isPlaying) || ps.find(p => p.trackTitle) || ps[0] || null
    }
}
