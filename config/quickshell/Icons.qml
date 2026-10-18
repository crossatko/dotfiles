pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Index of Adwaita's symbolic icons (name -> svg path). Qt's own lookup quietly falls back from
// "foo-symbolic" to a coloured "foo" from any theme, so it can't tell us whether a real
// symbolic icon exists; reading the files can.
Singleton {
    id: root
    property var symbolic: ({})

    // Font Awesome speaker for a volume level: xmark when muted, then off / low / high
    function volumeGlyph(muted, v) { return muted ? "\uf6a9" : v < 0.01 ? "\uf026" : v < 0.5 ? "\uf027" : "\uf028" }

    Process {
        running: true
        command: ["sh", "-c", "find /usr/share/icons/Adwaita/symbolic -name '*-symbolic.svg' -printf '%f\\t%p\\n' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {}
                for (const l of text.split("\n")) {
                    const [f, p] = l.split("\t")
                    if (f && p) m[f.replace(/-symbolic\.svg$/, "")] = p
                }
                root.symbolic = m
            }
        }
    }
}
