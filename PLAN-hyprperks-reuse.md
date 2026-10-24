# Plan: reuse ideas from Hyprland's official dotfiles (hyprperks v0.56.0)

Written 2026-10-24 on macOS from a read-only comparison. Run on the Linux host (battlestation first, the stock
workstation build second) so each step is tested live. Delete this file once every item is done or dropped, and
move the lasting findings into `AGENTS.md`.

Upstream: <https://github.com/hyprwm/hyprperks-dotfiles/tree/main/v0.56.0/dotfiles> (Quickshell under `quickshell/`).
Treat it as reference only: read it, copy ideas, do not run its scripts (`update.sh` pipes curl into bash).

## Ground rules (from AGENTS.md, repeated because they bite)

- Test Quickshell changes in an isolated instance first (AGENTS.md "Isolated Quickshell" recipe), then hot reload the live one.
- Kill Quickshell / test instances by exact PID. No synthetic keystrokes. Screenshots only of the relevant layer
  region (`grim -g` with geometry from `hyprctl layers -j`); glass needs a generated backdrop, never real windows.
- Do not edit the QML of a popup that is open in the live shell.
- Everything is driven by `qs ipc call` + Hyprland binds; no `GlobalShortcut`.
- New popups go through `PopupHost`, not a new `PanelWindow`. Use the shared building blocks (AGENTS.md "Shared building blocks").
- Must load on both builds: fork features behind `pcall(hl.get_config)` probes (see "Stock Hyprland (workstation) compatibility").

## 0. Housekeeping (5 min)

- Check for orphaned poller loops left from before the `Bar.qml` FileView fix:
  `pgrep -af "while :"` → kill the `sh -c 'while :; … /proc/meminfo …'` ones (ppid 1) by PID. Update the AGENTS.md
  "CPU/MEM poller leak" entry with the result.
- `pacman -Q hyprsunset grim` — install what is missing; add `grim` (and `hyprsunset` if item 3 goes ahead) to `install.sh`.

## 1. Bar compacts on fullscreen (S)

Upstream: `quickshell/ScreenState.qml` (`Hyprland.monitorFor(screen).activeWorkspace.hasFullscreen`) drives an animated
`compactState` 0..1 in `quickshell/bar/Bar.qml` (margins, radius, exclusive zone).
Ours: nothing (`fullscreen` only appears in a comment in `ModalMenu.qml`).

Steps:
1. In `config/quickshell/Bar.qml`, bind `readonly property bool fs` to the bar screen's
   `Hyprland.monitorFor(screen)?.activeWorkspace?.hasFullscreen ?? false`.
2. Decide the behaviour (ask the user if unclear): hide the bar fully (slide/fade out) vs compact (docked look: floating gap
   and radius to 0). Default proposal: slide out, because a fullscreen window already ignores the reserved area.
3. Animate with the existing motion tokens in `Theme.qml` (same timing as popups, Settings > Animations scale applies).
4. Keep `NotchMask.qml` / the glass region in sync with the animated shape, and drop the region at opacity ~0 like
   `Glass.qml` does, otherwise a blurred box stays behind (same class of bug as the 2026-10-21 "close cut").
5. Check `BarReserve.qml` / exclusive zone: tiled windows on that monitor must not reflow when the bar hides only for fullscreen.

Verify: fullscreen a window (`hyprctl dispatch` the fullscreen dispatcher on a throwaway test window, e.g. a kitty with a
solid backdrop), screenshot the bar region before/after; leave fullscreen and confirm the bar returns and blur matches;
check the other monitor's bar is unaffected; check a fullscreen game on workspace 9 (Steam rule) does not flash the bar.

## 2. Keybind cheat sheet (M)

Upstream: `quickshell/state/ShortcutsState.qml` (Process `hyprctl binds -j`, refetch on raw event `configreloaded`,
modmask bitmask → names), `quickshell/shortcuts/ShortcutsPanel.qml` (list, description or `dispatcher: arg` fallback).
Ours: nothing (`binds -j` not used anywhere).

Steps:
1. First check the data: `hyprctl binds -j | jq '.[0:5]'`. With the Lua config, find out what Lua-function binds
   (`focus-direction`, `switch-workspace`, the Escape → `qs ipc call popup esc` bind) look like: is there a
   `description`, or only an opaque dispatcher? If descriptions are missing, add them in `config/hypr/hyprland/binds.lua`
   (check the `hl.bind` options for a description field) rather than hard-coding names in QML.
2. New singleton `config/quickshell/Binds.qml`: one-shot Process (not a loop) running `hyprctl binds -j`, re-run on
   `configreloaded` (same hook as `Theme.qml:70`). Decode modmask (SHIFT=1, CAPS=2, CTRL=4, ALT=8, MOD2=16, MOD3=32,
   SUPER=64, MOD5=128). Group by modifier set / category; hide `non_consuming` and mouse binds or put them last.
3. UI: a launcher section (filter field for free, matches the launcher pattern in AGENTS.md "Launcher sections")
   or a PopupHost popup. Proposal: launcher section `binds`, plus IPC `qs ipc call launcher open binds` and a bind
   (e.g. SUPER+/ ; check `binds.lua` for conflicts).
4. Render keys with the existing `KeyBadge.qml` if it fits.

Verify: open via IPC in the isolated instance, screenshot; edit a bind, reload Hyprland, confirm the list updates;
confirm no `hyprctl` process lingers (`pgrep -af "hyprctl binds"` empty after load).

## 3. Night light via hyprsunset (S-M, optional)

Upstream: `quickshell/state/NightLightState.qml` (`hyprctl hyprsunset temperature N` / `identity`, 100 ms debounce Timer).
Ours: nothing.

Steps:
1. Start `hyprsunset` from `config/hypr/hyprland/autostart.lua` (`hl.on("hyprland.start")`), not from a Quickshell
   Process (hot reload would double-start it). Skip upstream's heredoc-written `hyprsunset.conf`.
2. Toggle + temperature slider in the control center brightness area (existing `Slider.qml`, toggle on the section
   header per the "Toggles only on section headers" rule). Debounce with a Timer; persist state like DND (`~/.cache/qs-*`).
3. Check HDR on the battlestation: with `cm_auto_hdr` / fp16 the gamma ramp may be ignored or look wrong. If so, hide
   the control on that host or document the limitation.
4. Skip time-based profiles unless the user asks.

Verify: `hyprctl hyprsunset temperature 4000` by hand first, then via the UI; check it survives a Quickshell hot reload
and a Hyprland config reload; check the gamescope session switch does not leave it stuck.
Verifying the colour shift visually needs the user's eyes (screenshots capture pre-gamma pixels).

## 4. Never-zero-bars guard (S, optional)

Upstream `quickshell/shell.qml` falls back to `screens[0]` if the filter excludes every monitor.
Ours: `shell.qml` Variants show bars only for screens enabled in `BarConfig`; all disabled → no bar, and Settings is then
only reachable via IPC/launcher. Decide with the user whether that is intended; if not, fall back to the primary monitor.

## 5. Hyprland-side items (optional, from the same comparison)

- `hyprpaper.conf` still uses `preload=` lines, generated by `config/theme/theme.py`. Check the installed hyprpaper version;
  if it supports the block syntax (`wallpaper { monitor = …; path = …; fit_mode = cover }`), switch the generator and use
  `~` instead of an absolute home path. Verify both hosts and the video-wallpaper still frame (mpvpaper path).
- Gestures, only if a host has a touchpad: `hl.gesture{fingers=3, direction="horizontal", action="workspace"}`.
- hyprlock: add a clock label (and optionally an avatar) using the theme-generated colours. Verify with a lock on a
  test monitor or ask the user to look; never screenshot the real lock content.

## 6. Code hygiene (from a style review against upstream's QML, 2026-10-24)

Our shell is already more robust than upstream (argv-safe Process calls, 43 `JSON.parse` all in `try`, native services,
exit-code handling). Upstream is ahead on modern QML idioms. Counts below are greps over `config/quickshell`.

1. **Quoting fixes (S, do first).**
   - `Bar.qml:180` `run(cmd)` builds `sh -c` strings; the rec-stop button (~line 351) wraps `recScript` in single quotes
     (breaks on `'`). Change `run` to take an argv array (`runner.command = argv`) and pass
     `[bar.recScript, "stop"]`; the workspace-focus call (~339) becomes `["hyprctl", "dispatch", "hl.dsp.focus({workspace=" + id + "})"]`.
     Keep the jq pipeline (~374) as `sh -c` but with no interpolated data (it has none today).
   - `SettingsWallpaper.qml:452` builds a `find` command with folder names in unescaped single quotes. Pass the folders as
     positional args (`["sh", "-c", 'find "$@" …', "sh", ...dirs]`) like `launcher/ClipboardSource.qml:81` does.
   - Verify: click a workspace chip, start/stop a recording, rescan wallpapers incl. a test folder with a `'` in its name.
2. **`?.` / `??` instead of `||` for defaults (S per file).** Ours: `?.` 0, `??` 2 (upstream 25 / 28). `x || d` turns a real
   `0` / `""` / `false` into the default; matters for settings like radius 0 or gaps 0. Examples: `HomeAssistant.qml:151`,
   `Launcher.qml:492`. Go through `grep -rn "|| " config/quickshell` and change only the ones where a falsy value is valid;
   leave string fallbacks where `""` should fall back. Verify: Settings > Appearance radius/gaps 0 survives a hot reload.
3. **`pragma ComponentBehavior: Bound` (M).** Ours 0, upstream 13, while we have 87 `required property`. Add it file by file
   to files with delegates (Repeater / ListView / Variants), fix the resulting warnings (delegates must reach outer ids, not
   implicit context properties). Verify: `quickshell -p` log shows no new warnings, open each touched popup/launcher section.
4. **Smaller, when touching the area anyway:**
   - Remove/guard `console.log` in `NotifCard.qml:74` and `HomeAssistant.qml` (~210, 230, 264): they log notification
     content and the HA host.
   - Timers: 73 vs upstream 16. Check that pollers bind `running` to visibility (`running: panel.visible` or the chip's `shown`).
   - `Qt.binding`: where JS assigns to a property that is normally bound, restore the binding or switch to a state flag.
   - `LazyLoader` for rarely opened UI (Settings, big launcher sections): only if startup/memory measurably improves.
   - Jellyfin search `*Tok` counters (`launcher/JellyfinSource.qml:55-62`): check stale results can't win when typing fast.
   - Not doing: moving ~90 flat files into module folders / splitting state out of `*Source` files, unless rewriting that family.

Checked and fine: `launcher/CommandsSource.qml:30` and `SectionsSource.qml:584` run `sh -c item.command`, but those commands
are hard-coded in the source, not user input.

## Not taken (decided 2026-10-24)

Upstream's system stats (`top`/`free`/`ifstat`/`sensors` polling), nmcli wifi wrapper, weather (`wttr.in` + `ipinfo.io`
leak IP/city), update/intro flow, monitor-corner rounding (timer hack), matugen, `killall -9 hypridle` toggle,
GlobalShortcut toggles, managed `conf.d`/`custom.d` split, `HLDE.*` globals.
