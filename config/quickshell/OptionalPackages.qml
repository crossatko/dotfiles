pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "launcher/js/Bundles.js" as Bundles

// Optional package bundles (packages/optional/<name>.txt): which are missing, their install command, hint rows.
// Metadata + fallback names: launcher/js/Bundles.js. The package names are read at runtime from the repo's
// packages/optional/<name>.txt, found by resolving this file's symlink (the config dir is a link into the repo); an
// unreadable file (no repo, copied config) keeps the fallback names. `refresh()` re-checks `command -v` for every
// bundle's binaries; consumers call it when they open (no polling). UI: MissingPackage.qml, launcher "pkg-hint" rows.
Singleton {
    id: root

    property var missing: ({})            // bundle -> true while one of its binaries is not on PATH
    property var lists: ({})              // bundle -> package names read from packages/optional/<name>.txt
    readonly property string self: String(Qt.resolvedUrl("OptionalPackages.qml")).replace(/^file:\/\//, "")

    function isMissing(bundle) { return missing[bundle] === true }
    function packages(bundle) { return lists[bundle] && lists[bundle].length ? lists[bundle] : Bundles.BUNDLES[bundle].fallback }
    function command(bundle) { return Bundles.installCommand(packages(bundle)) }
    function info(bundle) { return Bundles.BUNDLES[bundle] }
    function hintRow(bundle, over) { return Bundles.hintRow(bundle, command(bundle), over) }
    function refresh() { if (!checkProc.running) checkProc.running = true }

    Component.onCompleted: { listProc.running = true; refresh() }

    Process {
        id: listProc
        // prints "## <bundle>" then the file for every bundle
        command: ["sh", "-c", "d=$(dirname \"$(readlink -f \"$0\")\")/../../packages/optional; for n in " + Object.keys(Bundles.BUNDLES).join(" ")
                 + "; do echo \"## $n\"; cat \"$d/$n.txt\" 2>/dev/null; done", root.self]
        stdout: StdioCollector { id: listOut }
        onExited: {
            const l = {}
            let cur = ""
            for (const line of listOut.text.split("\n")) {
                if (line.startsWith("## ")) { cur = line.slice(3).trim(); l[cur] = ""; continue }
                if (cur) l[cur] += line + "\n"
            }
            for (const k in l) l[k] = Bundles.parsePackages(l[k])
            root.lists = l
        }
    }
    Process {
        id: checkProc
        command: Bundles.checkArgv()
        stdout: StdioCollector { id: checkOut }
        onExited: root.missing = Bundles.parseMissing(checkOut.text)
    }
}
