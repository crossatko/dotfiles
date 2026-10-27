import QtQuick
import Quickshell
import Quickshell.Io
import "js/Ranker.js" as Ranker

// Source: emoji picker, prefix mode: a query starting with ":" (":smile") lists emoji, max 50, ranked with Ranker.
// Data: data/emoji.tsv (char TAB name TAB keywords), generated once from GTK4's bundled CLDR English annotations.
// Enter copies the character with wl-copy.
QtObject {
    id: src

    readonly property var items: []               // nothing in the normal list
    readonly property string modeTitle: "Emoji"   // launcher header in prefix mode
    readonly property string modeGlyph: "\uf118"   // face-smile
    property var table: []                        // ranker items {id, name, keywords, char}

    function exclusive(q) { return q.startsWith(":") }

    function dynamic(q) {
        if (!exclusive(q)) return []
        const t = q.slice(1).trim()
        let list
        if (t === "") list = table.slice(0, 50)
        else list = Ranker.rank(table, t, {}, 0, { limit: 50 }).map(r => r.item)
        return list.map(e => ({                   // the character itself is the row's leading glyph (drawn by the font fallback)
            id: e.id, name: e.name, subtitle: e.keywords.join(" "),
            kind: "emoji", source: "Emoji", glyph: e.char, transient: true, char: e.char
        }))
    }

    property var file: FileView {
        path: String(Qt.resolvedUrl("data/emoji.tsv")).replace(/^file:\/\//, "")
        printErrors: false
        onLoaded: {
            const out = []
            for (const line of text().split("\n")) {
                const p = line.split("\t")
                if (p.length < 2 || p[0] === "") continue
                out.push({ id: "emoji:" + p[0], name: p[1], keywords: p[2] ? p[2].split(" ") : [],
                           kind: "emoji", source: "Emoji", char: p[0] })
            }
            src.table = out
        }
    }

    function run(item) {
        if (item.kind !== "emoji") return false
        Quickshell.execDetached(["wl-copy", "--", item.char])
        return true
    }
}
