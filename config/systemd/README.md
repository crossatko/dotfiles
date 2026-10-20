# systemd units — rootful gamescope-session alongside Hyprland

Reference copies of the units that make CachyOS's SteamOS-style
`gamescope-session` (Steam Big Picture as its own DRM/KMS compositor, on the
TV over HDMI) coexist with Hyprland on the same machine, switchable in both
directions without a display manager.

These are **copies, not symlinks** — `~/.config/systemd/user/` is a real
directory here, unlike `~/.config/hypr` which symlinks into `config/hypr`.
Edit the live files and re-copy, or convert to a symlink (see bottom).

## Layout

| File | Installs to |
|---|---|
| `user/gamescope-session.service.d/override.conf` | `~/.config/systemd/user/` |
| `user/steam-launcher.service.d/override.conf` | `~/.config/systemd/user/` |
| `user/gamescope-session-wake.service` | `~/.config/systemd/user/` |
| `user/gamescope-sleep-signal-listener.service` | `~/.config/systemd/user/` |
| `user/gamescope-webhook-notify.service` | `~/.config/systemd/user/` |
| `user/hypr-focus-daemon.service` | `~/.config/systemd/user/` |
| `../../system/etc/systemd/system/getty@tty1.service.d/autologin.conf` | `/etc/systemd/system/` (root) |
| `../../system/etc/systemd/logind.conf.d/inhibit-delay.conf` | `/etc/systemd/logind.conf.d/` (root) |

Packages: `gamescope`, `lib32-gamescope` (**must match `gamescope`'s exact
version** or pacman refuses the dependency), `gamescope-session-cachyos`.
The 32-bit layer is not optional — 32-bit games need their own WSI layer.

Related, outside this directory:
- `config/hypr/scripts/gamescope-wrapper/gamescope` — PATH-shadow wrapper,
  the only way to add flags to the session (see below).
- `config/hypr/scripts/session-supervisor.sh` — switching.
- `config/hypr/scripts/tv-*.sh`, `steam-tv-dim.lua` — TV wake/sleep/audio.

## The landmine: WAYLAND_DISPLAY must be UNSET, not set

If any `WAYLAND_DISPLAY` reaches Steam, **every game shows "Hooking has
failed somewhere" on launch and HDR renders washed out** (grey blacks).

Hyprland imports `WAYLAND_DISPLAY` into the shared systemd `--user`
environment so its own units can find its socket. That leaks into
`steam-launcher.service`, and pressure-vessel then mirrors it into the
game's container as `wayland-0` while rewriting `GAMESCOPE_WAYLAND_DISPLAY`
to an absolute bind path (`/run/pressure-vessel/gamescope-socket`).

gamescope's WSI layer gates *all* hooking on a nested-session guard:

```c
// isRunningUnderGamescope(), layer/VkLayer_FROG_gamescope_wsi.cpp
if (waylandSocketName && *waylandSocketName &&
    strcmp(gamescopeSocketName, waylandSocketName) != 0)
  return false;
```

The two can never compare equal inside the container, so *any* value fails
and only **unset** passes. `CreateInstance` then bails before hooking
anything: no registered surface (→ the dialog), and gamescope never learns
the app's colorspace so it defaults to `COLORSPACE_SRGB` — SDR handling on
HDR content, i.e. lifted blacks. One guard, both symptoms.

Hence `UnsetEnvironment=WAYLAND_DISPLAY` in *both* overrides. Do not
"helpfully" set it to `gamescope-0`; that fails identically. Nothing needs
it — Steam and games are XWayland clients (`DISPLAY=:0` / `:1`), and the
layer reaches gamescope via `GAMESCOPE_WAYLAND_DISPLAY`, which the packaged
session supplies dynamically off gamescope's ready-pipe through
`EnvironmentFile=%t/gamescope-environment`.

Corollary: never hardcode `GAMESCOPE_WAYLAND_DISPLAY` in a drop-in. Drop-in
`Environment=` is applied *after* `EnvironmentFile=`, so it would silently
override the correct discovered value.

## Other gotchas

- **Connector**: the packaged script defaults to `-O "*,eDP-1"` (Steam Deck's
  internal panel). Set `OUTPUT_CONNECTOR` to the real one (`HDMI-A-1` here).
- **No flag injection**: `/usr/lib/steamos/gamescope-session`'s `exec
  gamescope \ ...` is fully hardcoded. The only way to add flags without
  patching a packaged file (lost on update) is the PATH-shadow wrapper,
  pointed at by the `PATH=` line in the gamescope-session override.
- **Seat exclusivity**: starting gamescope-session while Hyprland is still
  logged in makes the seat cycle `resumed → paused` and gamescope dies with
  `drm: flip error: Invalid argument`. Fully end one session first.
- **Never `systemctl restart gamescope-session.target`** directly — it skips
  `start-gamescope-session`'s stop/reset-failed sequencing and wedges the
  target in `deactivating` with `steam-launcher` looping on "Failed to load
  environment files". Switch via the power menu or Steam's own UI.
- `steam-launcher.service` can be restarted on its own safely; that reloads
  Steam's environment without touching the compositor.
- **`graphical-session.target` is not gamescope-specific** — it starts for
  Hyprland too. Any unit that must only run for gamescope-session needs
  `ConditionPathExists=%t/gamescope-environment` (the marker the packaged
  launcher writes), or it fires on every Hyprland login as well.
- **Suspend/resume is invisible to `graphical-session.target`.** It never
  stops, so a `Type=oneshot` + `RemainAfterExit=yes` unit's `ExecStop=` does
  *not* fire on suspend and its `ExecStart=` does not re-fire on resume.
  Anything that must track "is gamescope actually on the TV" (rather than
  "does a session exist") needs the logind `PrepareForSleep` listener as
  well — `gamescope-sleep-signal-listener.sh` covers both halves. This is
  why the HA notification has *four* call sites, two per mechanism.
- **One concern per oneshot.** A `Type=oneshot` aborts its remaining
  `ExecStart=` lines as soon as one fails, and a unit whose `ExecStart=`
  failed never runs `ExecStop=` at all — so piggybacking a second, unrelated
  command onto an existing unit silently couples it to the first one's exit
  status *in both directions*. `gamescope-webhook-notify.service` is split
  out of `gamescope-session-wake.service` for exactly this reason.

## Wake source decides the session

`gamescope-sleep-signal-listener.service` does more than TV power: on resume it
asks `wake-source-switch.sh` which device woke the machine and switches session
accordingly — controller → gamescope-session, keyboard/mouse → Hyprland. It
runs on `default.target`, not `graphical-session.target`, which is what lets it
survive the switch it performs.

Attribution is a before/after diff of per-device `power/wakeup_*` counters,
snapshotted on `PrepareForSleep (true,)`. Two measured facts that a from-first-
principles implementation gets wrong:

- **`wakeup_count` never moves on this hardware** — only
  `wakeup_active_count` does (plus `wakeup_last_time_ms` becoming non-zero).
  Keying off `wakeup_count` alone classifies every wake as unknown and the
  feature silently does nothing.
- **The counters are cumulative and never reset**, so only the *delta* across
  the suspend identifies the waking device. An absolute-value check sees last
  week's wake and misfires.

Only three devices have `power/wakeup == enabled` and can wake it at all:
Corne (`4653:0001`) and Logitech receiver (`046d:c54d`) → desk, Steam
Controller Puck (`28de:1304`) → controller. The MSI "Gaming Controller"
(`1462:3fa4`) is the *monitor's* HID, has no `power/wakeup` file, and is not a
gamepad. Unknown/ambiguous wakes (RTC, network, spurious) always stay put.

```sh
wake-source-switch.sh report            # counters + snapshot + flags
tail ~/.local/state/wake-source/log     # every decision, with its reasoning
touch ~/.local/state/wake-source/dry-run   # log decisions, act on none
touch ~/.local/state/wake-source/disabled  # kill switch: always stay
```

### Watching PrepareForSleep is not enough — you need a delay inhibitor

`PrepareForSleep (true,)` is an announcement, not a request for permission.
Measured here, `PM: suspend entry (deep)` lands **3ms** after it is broadcast.
A `gdbus monitor` subscriber that merely reacts to the signal gets no window
at all: the first version of the TV-sleep-on-suspend logic was frozen mid-`adb`
and only returned 24s later, *after* the resume, having left the TV awake on a
"no input" screen for the entire suspend.

The fix is a `mode=delay` inhibitor, which logind genuinely waits on (up to
`InhibitDelayMaxSec`, hence the drop-in above raising it to 15s for
`tv-sleep.sh`'s ~6s worst case). The listener holds one continuously via
`systemd-inhibit … sleep infinity &`, and *releasing* it — killing that child —
is what allows the suspend to proceed. So the release must be unconditional and
last, or a suspend stalls until the cap expires.

Two traps here:

- **Don't clean up stale locks with `pkill -f`.** The inhibit child lives in the
  unit's cgroup and systemd's default `KillMode=control-group` already reaps it
  on stop/restart, even after SIGKILL where the EXIT trap never runs. An
  earlier `pkill -f "systemd-inhibit.*$INHIBIT_WHO"` killed the interactive
  shell that was grepping for that same string, because `-f` matches any
  process whose command line merely *contains* the pattern.
- **`/usr/lib/systemd/system-sleep/` hooks do not fire on this system** —
  confirmed across multiple real cycles, including the pre-existing `nvidia`
  one. That is why this is a D-Bus subscriber rather than a sleep hook.

## Verifying a working session

```sh
# 1. layer got past the gate (prints the game's exe, not just helpers)
journalctl --since "-5 min" | grep -E "Executable name|Surface state"

# 2. surfaces hooked with HDR offered
journalctl --since "-5 min" | grep -A5 "Surface state" | grep "hdr formats"
#    want: hdr formats exposed to client: true

# 3. must be ZERO
journalctl --since "-5 min" | grep -c "does not support HDR\|non-Gamescope"

# 4. compositor sees the app asking for HDR (only set once truly hooked)
DISPLAY=:0 xprop -root | grep GAMESCOPE_COLOR_APP_WANTS_HDR_FEEDBACK   # = 1

# if broken, this is the first thing to check:
tr '\0' '\n' < /proc/$(pgrep -f '\.exe$' | head -1)/environ | grep WAYLAND
#    WAYLAND_DISPLAY must be ABSENT
```

Note `SetHdrMetadataEXT: Swapchain N does not support HDR` is misleadingly
worded — it fires when the swapchain isn't hooked, not when HDR is
unsupported. It means the same thing as the dialog.

## Optional: track live instead of copying

```sh
rm -rf ~/.config/systemd/user
ln -s ~/dotfiles/config/systemd/user ~/.config/systemd/user
systemctl --user daemon-reload
```

Do this only from a plain Hyprland session (not while gamescope-session is
running), and confirm `systemctl --user cat steam-launcher.service` still
shows the drop-in afterwards.
