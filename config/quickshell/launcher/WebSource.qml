import QtQuick
import Quickshell

// Source: web-search fallback rows, appended after the ranked results while a query exists.
QtObject {
    readonly property var items: []
    readonly property var engines: [
        { id: "google",     name: "Google",     url: "https://www.google.com/search?q=" },
        { id: "duckduckgo", name: "DuckDuckGo", url: "https://duckduckgo.com/?q=" }
    ]

    function dynamic(query) {
        const q = query.trim()
        if (q === "") return []
        return engines.map(e => ({
            id: "web:" + e.id, name: "Search " + e.name + " for \"" + q + "\"", subtitle: "",
            kind: "web", source: "Web", glyph: "", url: e.url + encodeURIComponent(q)
        }))
    }

    function run(item) {
        if (item.kind !== "web") return false
        Quickshell.execDetached(["xdg-open", item.url])
        return true
    }
}
