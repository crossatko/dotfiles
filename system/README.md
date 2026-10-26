# system/

Root-owned files that live outside `$HOME`. Copy each to the listed path (as root), then reload the relevant service.

| File in `system/etc/` | Installs to | Purpose / machine |
|---|---|---|
| `udev/rules.d/50-vial.rules` | `/etc/udev/rules.d/` | hidraw access for the seat user on Vial-firmware keyboards (Corne with Vial; WebHID, vial-gui). |
| `udev/rules.d/61-corne-nojoystick.rules` | `/etc/udev/rules.d/` | Stops the Corne (VIA firmware) from being treated as a joystick by games/SDL. |
| `udev/rules.d/62-corne-via.rules` | `/etc/udev/rules.d/` | uaccess on the Corne hidraw node so VIA (WebHID) can talk to it. |
| `mullvad-tailscale/coexist.nft` | `/etc/mullvad-tailscale/` | nftables table letting Tailscale traffic coexist with the Mullvad firewall/tunnel. Loaded by the service below. |
| `systemd/system/mullvad-tailscale.service` | `/etc/systemd/system/` | Loads `coexist.nft` (machines running both Mullvad and Tailscale). |
| `systemd/logind.conf.d/inhibit-delay.conf` | `/etc/systemd/logind.conf.d/` | Raises `InhibitDelayMaxSec` so the TV-standby sleep inhibitor (`gamescope-sleep-signal-listener.sh`) has time to finish (TV/gamescope machine). |
| `systemd/system/getty@tty1.service.d/autologin.conf` | `/etc/systemd/system/getty@tty1.service.d/` | tty1 autologin; `session-supervisor.sh` runs from the login shell. Set the username to your own. |

After udev changes: `sudo udevadm control --reload-rules && sudo udevadm trigger`. After systemd changes: `sudo systemctl daemon-reload`.
