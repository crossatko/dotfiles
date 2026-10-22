pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The one place that turns Tailscale / Mullvad on (and Mullvad off) for the network popup: runs bin/vpn-switch,
// which keeps the two mutually exclusive (turning one on first takes the other down and waits for it; Mullvad off
// brings Tailscale back up), or switches each on its own while mullvad-tailscale.service (system/etc/
// mullvad-tailscale: nft rules for running both) is active = `coexist`. A singleton, so a switch in flight
// survives the popup closing. Turning Tailscale off is plain `tailscale down` in TailscaleSection.
// A VPN switched on outside this UI is only reflected, never fought: the sections just show the state.
// `QS_VPN_SWITCH` replaces the script (tests).
Singleton {
    id: root

    readonly property string script: Quickshell.env("QS_VPN_SWITCH") ? String(Quickshell.env("QS_VPN_SWITCH")) : Quickshell.shellDir + "/bin/vpn-switch"
    property string target: ""            // "tailscale" | "mullvad" | "mullvad-off" while a switch runs
    readonly property bool busy: target !== ""
    property bool coexist: false          // both may run together (see checkMode)
    // finished(target, exit code, stderr + stdout): 0 ok, 2 first step failed, 3 refused (lockdown), -1 timed out
    signal finished(string target, int code, string text)

    // header text while a switch runs: in exclusive mode both VPNs are being changed, so both headers say it
    function switching(vpn) {
        if (!busy) return false
        if (!coexist) return true
        return target === vpn || (vpn === "mullvad" && target === "mullvad-off")
    }

    function run(t) {
        if (proc.running) return false
        target = t
        proc.command = [script, t]
        proc.running = true
        guard.restart()
        return true
    }
    function checkMode() { if (!modeProc.running) modeProc.running = true }

    Process {
        id: proc
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: (code, status) => Qt.callLater(() => root.done(code, err.text + "\n" + out.text))
    }
    function done(code, text) {
        if (target === "") return         // the guard already reported it
        guard.stop()
        const t = target
        target = ""
        finished(t, code, text)
    }
    // the script's own waits add up to ~50 s at worst (10 s + 25 s `tailscale up` + slack)
    Timer { id: guard; interval: 60000; onTriggered: if (proc.running) { root.done(-1, "Timed out switching the VPN"); proc.running = false } }

    Process {
        id: modeProc
        command: ["systemctl", "is-active", "--quiet", "mullvad-tailscale.service"]
        onExited: (code, status) => root.coexist = code === 0
    }
}
