import QtQuick
import Quickshell
import Quickshell.Io

// Source: calculator / unit conversion through `qalc -t` (libqalculate). Only queries that look like math are
// evaluated (a digit plus an operator, a function call, or "<number><unit> to|in|as <unit>"), so plain app searches
// never spawn qalc. The expression is an argv element (never a shell string); runtime is capped at 2 s by timeout(1).
// The result row is `top` (shown above the ranked results). Enter copies the result (wl-copy) and toasts.
QtObject {
    id: src

    signal updated()

    property var items: []
    property string expr: ""            // expression being / last evaluated
    property string result: ""          // qalc output for `expr` ("" = none yet or failed)
    property string wanted: ""          // expression the launcher currently asks for

    function looksLikeMath(q) {
        if (q.length < 2 || q.length > 200) return false
        if (!/\d/.test(q)) return false
        if (!/^[0-9a-zA-Z\s.,+\-*\/^%()$€£¥°²³×÷=!_<>]+$/.test(q)) return false
        if (/^[a-zA-Z]/.test(q) && !/^(sqrt|cbrt|sin|cos|tan|asin|acos|atan|sinh|cosh|tanh|ln|log|log2|log10|exp|abs|floor|ceil|round|fact|root|pow|gcd|lcm|rand|mod)\s*\(/i.test(q)) {
            // starts with a word: only "<word> <number>" style conversions are not supported, require a function call
            return false
        }
        if (/\d\s*[+*\/^%×÷]\s*[\d(.]|\d\s*-\s*[\d(.]|[\d)]\s*\^|\)\s*[+\-*\/^%]/.test(q)) return true
        if (/[a-z]\s*\(/i.test(q) && /\)/.test(q)) return true
        return /^[\d.,]+\s*[a-zA-Z°$€£%\/²³]+\s+(to|in|as|into)\s+[a-zA-Z°$€£%]/i.test(q)
    }

    function normalize(q) {
        // "5km in miles": qalc reads "in" as inches, "to" converts
        return q.replace(/\s+(in|as|into)\s+/gi, " to ").replace(/×/g, "*").replace(/÷/g, "/")
    }

    function dynamic(q) {
        if (!looksLikeMath(q)) { wanted = ""; return [] }
        wanted = q
        if (q === expr && result !== "")
            return [{
                id: "calc:result", name: "= " + result, subtitle: q, kind: "calc", source: "Calculator",
                glyph: "\uf1ec", transient: true, top: true, result: result      // calculator
            }]
        if (q !== expr) debounce.restart()
        return []
    }

    property var debounce: Timer {
        interval: 250
        onTriggered: {
            if (src.wanted === "" || proc.running) return
            src.expr = src.wanted
            src.result = ""
            proc.command = ["timeout", "2", "qalc", "-t", "--", src.normalize(src.expr)]
            proc.running = true
        }
    }

    property var proc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const first = text.split("\n")[0].trim()
                src.result = (first === "" || /^error/i.test(first)) ? "" : first
                src.updated()
                // the query moved on while qalc was running
                if (src.wanted !== "" && src.wanted !== src.expr) debounce.restart()
            }
        }
    }

    function run(item) {
        if (item.kind !== "calc") return false
        Quickshell.execDetached(["sh", "-c",
            "printf '%s' \"$1\" | wl-copy; notify-send -a Launcher 'Copied result' \"$1\"", "sh", item.result])
        return true
    }
}
