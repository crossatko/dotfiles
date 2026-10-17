# AGENTS.md — dotfiles handbook for AI agents

Read this first. It describes the machine, the repo, the conventions, and what has already been built, so you can continue without re-deriving it.

## Working rules (mandatory)

### 1. Every task goes through a subagent, sized by difficulty

Do not do the work inline in the main conversation. Delegate each task to a subagent and pick the model by difficulty:

| Difficulty | Examples | Model |
|---|---|---|
| Trivial | rename, typo, one-line config tweak, reading/summarising a file, `grep` lookups, simple docs | **haiku** |
| Normal | a contained feature or bug fix in one or two files, adding a panel/chip, styling, scripted edits | **sonnet** |
| Hard | cross-cutting changes (theme engine, Hyprland Lua + Quickshell interplay, reserved-area logic), debugging crashes/races, design decisions, anything touching several subsystems | **opus** |

- The main conversation only plans, delegates, verifies and reports. Give each subagent a self-contained brief (goal, files, constraints, what is already ruled out).
- When unsure between two tiers, take the higher one for anything that can break the user's live desktop.
- Independent tasks run in parallel; dependent ones run in sequence.
- Always verify a subagent's result yourself (reload, logs, screenshot) before telling the user it works.

### 2. Safety rules learned the hard way

- **Never inject synthetic keystrokes** (`wtype`, etc.). It lands in the user's own terminal. (Memory: `feedback_no_key_injection`.)
- **Kill Quickshell only by exact PID.** The user's shell is the bare `/usr/bin/quickshell` process. `pgrep -x quickshell` also matches other instances (the Twitch app, probes); `kill`ing by name or relaunching blindly creates duplicates.
- **Don't edit a popup's QML file while that popup is open.** Hot reload crashed Qt's Repeater (segfault) twice. Test in an isolated instance (`quickshell -n -p <dir>`) or with the popup closed.
- Hot reload only works for files already loaded. A new QML type needs a `qmldir` entry; a new *top-level* file may need a restart.
- Don't touch the screen-sharing portal routing (`config/xdg-desktop-portal`). ScreenCast/RemoteDesktop/Screenshot must stay on the Hyprland portal.
- **Secrets:** `config/hypr/.secrets` (Twitch `TWITCH_SECRET`, `TWITCH_CLIENT_ID`, Home Assistant `HA_URL`, `HA_TOKEN`) is git-ignored; placeholders live in the tracked `config/hypr/.secrets.example`. Never print, log or commit values. WiVRn pairing data is also not tracked.
- **Licensed fonts stay out of the repo.** Font Awesome 7 Pro Sharp is installed in `~/.local/share/fonts/FontAwesomePro/` only; the repo is public on GitHub.
- Screenshot tips: `grim -g "x,y WxH"`; Hyprland dims unfocused windows (focus first when sampling colours); popups open on the *focused* monitor.

### 3. Commit messages

- **Never attribute Claude or any other AI agent** in commit messages or PR descriptions: no `Co-Authored-By:` trailers naming an agent or model, no "Generated with Claude Code" (or similar) lines, no agent names anywhere in the message.
- Commit messages must read as if written by the user alone.
- This user rule overrides any tool or system default that suggests adding attribution.

## The machine

- Arch-based (CachyOS), **Hyprland 0.56 with the native Lua config** (`hl.*`, not a plugin), Quickshell 0.3.2 (QML) for bar/launcher/notifications, hyprpaper, hyprlock.
- Two monitors on the "battlestation" host: `DP-3` (main, y=0) and `DP-1` (second, below it), 2560x1440. Per-host differences live in `config/hypr/hyprland/host.lua`.
- Only `~/dotfiles/config` is live (symlinked into `~/.config`). The Nix files (`flake.nix`, `home.nix`, `hosts/`, `modules/`, `system/`, `lib/`) are an **old setup**, kept for reference. `install.sh` is the Arch bootstrap.
- UI font: Paper Mono. Icon font: **Font Awesome 7 Pro Sharp (Regular)** plus Font Awesome Brands (system package) for brand logos.
- Hyprland dispatch: `hyprctl dispatch "hl.dsp.focus({workspace=N})"`; window focus `hl.dsp.focus({window="address:0x..."})`. Lua globals can be called with an IIFE: `hyprctl dispatch '(function() if pip_bar_changed then pip_bar_changed() end return hl.dsp.exec_cmd("true") end)()'`. Lua monitor objects expose name/serial/description but **not** model.

## Repository map

```
config/
  hypr/            hyprland.lua + hyprland/*.lua (env, settings, theme, binds, rules, workspaces,
                   monitors, input, apps, autostart, host, permissions), scripts/ (power menu, TV mode,
                   pip-reserve, twitch-menu, wallpaper start, ...), hyprlock.conf, hyprpaper.conf
  quickshell/      the desktop shell (bar, popups, notifications, launcher, OSD, wallpaper picker)
  theme/           wallpaper-driven theme engine (theme.py, theme.toml, templates/, out/, bin/)
  kitty ghostty alacritty nvim zellij herdr nautilus tofi swaync waybar opencode fastfetch wivrn
  xdg-desktop-portal systemd/user  portal routing + units
  brave-flags.conf
install.sh         Arch bootstrap (packages, symlinks)
plans.md tv-behavior.md   older notes
```

`waybar`, `swaync` and `tofi` are legacy: Quickshell replaced them (tofi stays only as `qmenu`'s fallback).

## Theme system (`config/theme`)

- **One place to edit:** `theme.toml` (+ `templates/`). Never hard-code colours in an individual app config.
- `theme.py apply <img>` extracts a palette from the wallpaper (own extractor — wallust/matugen were tried and average away small saturated accents), renders templates, and live-reloads: kitty, ghostty, alacritty, nvim (RPC sockets), zellij, herdr, hyprland/hyprlock/hyprpaper, quickshell, GTK css, KDE/qt6ct palette, hue-rotated Adwaita icons (`Wall-Adwaita`), Brave seed-colour theme.
- `python3 -I config/theme/selftest.py` must pass after touching the extractor; it has to work for any wallpaper.
- Known limits: GTK4/libadwaita (Nautilus) cannot restyle open windows; Brave only picks up the theme while closed (shim `~/.local/bin/brave`); Dolphin is low priority.
- Qt apps: `QT_QPA_PLATFORMTHEME=kde` (set in `hyprland/env.lua`), style Fusion. Brave/Chromium dialogs use the generated GTK theme `Wall` via `GTK_THEME`, and portal FileChooser = `xdg-desktop-portal-gnome` (Nautilus-style).
- Wallpapers: `~/Pictures/wallpapers`. The Quickshell picker is `SUPER+T`.
- Details: `config/theme/README.md`.

## Quickshell (`config/quickshell`)

Palette comes from `~/.config/theme/out/palette.json` through the `Theme` singleton (`Theme.qml`): colours, `font`, `fontSize`, `iconFont` ("Font Awesome 7 Sharp"), `iconSize` (15), `rounding` (0), `barOpacity`, `barHeight`, `alpha()`.

| File | Role |
|---|---|
| `shell.qml` | root: per-screen Variants for Bar, BarReserve, PopupHost, Toasts, Osd; Picker, Menu; IPC handlers (`picker`, `menu`, `notif`, `popup`, `osd`) |
| `Bar.qml`, `Chip.qml`, `BarLabel.qml` | the bar and its modules. Chips highlight (`active`) while their popup is open via `bar.isOpen(name)` |
| `BarConfig.qml` | per-monitor `{enabled, edge}` saved to `~/.local/state/quickshell/bars.json` (key `model\|serial`), refuses to disable the last bar, notifies Hyprland (`pip_bar_changed`) |
| `BarReserve.qml` | invisible strip that reserves space; the bar itself uses `exclusiveZone: -1` so it ignores the monitor `reserved_area` |
| `Popups.qml`, `PopupHost.qml` | one popup at a time per screen; card placed with computed x/y (not anchors), content/container fade together |
| `CenterPanel.qml` + `Notifs.qml`, `NotifCard.qml`, `NotifIcon.qml`, `Icons.qml`, `Toasts.qml` | control center and notification server (click = default action + `bin/focus-app`, right-click = slide-out dismiss) |
| `AudioPanel/AudioSection/DevicePicker/Slider`, `NetPanel`, `BtPanel`, `CalPanel`, `MediaPanel` | popups |
| `TrayMenu.qml` | themed tray context menu (platform `QsMenuAnchor` needs QApplication mode, so we draw our own; position is read at click time) |
| `Menu.qml`, `bin/qmenu` | launcher (SUPER+D → `qs ipc call menu drun`) and fzf-backed dmenu |
| `Osd.qml` | volume/brightness OSD |
| `HomeAssistant.qml` (singleton), `HaPanel.qml`, `HaEntity.qml`, `HaStrip.qml` | Home Assistant popup (house chip, popup name `ha`, bar widget id `homeassistant`): REST API via in-process XHR (token never in argv/logs), polls `/api/states` every 4 s while open, once a minute for the chip. Lights (toggle, brightness, hue/saturation strips, colour temperature by `supported_color_modes`), climate (power, target ±, HVAC modes), vacuum (start/pause/dock, suction, rooms + passes, see below), fans, covers, switches/input_booleans, scenes/scripts. Unavailable/unknown entities are left out (footer count) and come back on their own; entities hidden in HA and switches belonging to a shown light/climate/vacuum device are dropped (template `is_hidden_entity` / `device_id`). Eye button = hide/unhide mode, saved in `~/.local/state/quickshell/homeassistant.json`. |
| `AiUsage.qml` (singleton), `AiPanel.qml`, `AiLimit.qml`, `bin/ai-usage` | AI usage popup (sparkles chip, popup name `ai`, bar widget id `ai`; chip shows the fullest limit window, orange ≥80 %, red ≥90 %). `bin/ai-usage` (Python, run with `-I`) discovers every Claude Code profile as `~/.claude*` dirs (one per `CLAUDE_CONFIG_DIR`; profile file = `<dir>/.claude.json`, for `~/.claude` it is `~/.claude.json`), label = email/display name, plan from `subscriptionType` + the profile's `userRateLimitTier` multiplier. Limits come from **`GET https://api.anthropic.com/api/oauth/usage`** (`Authorization: Bearer <claudeAiOauth.accessToken>`, `anthropic-beta: oauth-2025-04-20`): **unofficial and undocumented** (what Claude Code's `/usage` calls), may change or disappear; parsed defensively (`five_hour`, `seven_day`, `seven_day_opus/sonnet/…`, model-scoped entries of the `limits` array, `extra_usage`). Claude Code's own cached copy (`cachedUsageUtilization` in `.claude.json`) is adopted when newer, so often no request is made. Token only in the request header inside the helper (never argv/QML/cache/logs); it is **never refreshed** (would rotate the refresh token and can log the CLI out): lapsed access token = "start claude in this profile", 401/lapsed refresh token = "session expired", no retry until `.credentials.json` changes. Answers cached 60 s (`--force` 20 s) in `~/.cache/quickshell/ai-usage/`, 429 → Retry-After or 5 min backoff, offline → 2 min, last good values shown dimmed. Without windows (API key, no login) it shows local estimates from `projects/**/*.jsonl` (files touched in the last 8 days, read incrementally by byte offset). Also lists Codex CLI (rate limits from its newest session log), opencode, Gemini CLI when present. Runs on popup open, every 3 min while open (or while a limit ≥80 %), every 10 min for the chip, not at all while the chip is hidden. Tests: `QS_AI_HOME` (where to look), `QS_AI_CACHE`, `QS_AI_MOCK` (dir of `<profile dir>.json` = `{"status":200,"body":{…}}`), `QS_AI_HELPER`; `ai-usage --shape` prints response keys/numbers only. |
| `bin/` | `focus-app`, `calendar-events` (read-only Thunderbird `cache.sqlite` helper), `qmenu`, `ai-usage` |

Home Assistant setup: create a long-lived access token in HA (profile → Security → Long-lived access tokens) and put `HA_URL=http://<host>:8123` and `HA_TOKEN=<token>` (optional `HA_URL_FALLBACK=`) into `config/hypr/.secrets`; the panel re-reads it each time it opens. No host is hard-coded: without both keys the popup shows the setup steps, an unresolvable/unreachable host shows "unreachable". Vacuum rooms: from the vacuum's attributes (`rooms`/`segments`, Dreame) or `roborock.get_maps` (Roborock); selected rooms are cleaned with `dreame_vacuum.vacuum_clean_segment {segments, repeats}` or `vacuum.send_command app_segment_clean [{segments, repeat}]`; a full clean's passes go through a same-device `number`/`select` "repeat / cleaning times" entity when one exists. Testing: `QS_HA_SECRETS` / `QS_HA_STATE_DIR` point an isolated instance at a mock server's files — never test service calls against the real HA.

Gotchas: `qmldir` must list every type; a QML property named like an id (`bar: bar`) shadows it — name properties differently; `Chip`'s hover MouseArea sits at `z: -1` so child MouseAreas (tray icons) get clicks; singletons aren't warmed in isolated test instances.

## Hyprland config (`config/hypr`)

- `theme.lua`: border 2px, rounding 0; `settings.lua`: gaps 0.
- `rules.lua`: Twitch player (`org.quickshell` titled "Twitch - …"), PiP and mpv rules — pinned, 1588x893, placed bottom-right of the second monitor.
- `scripts/pip-reserve.lua` (battlestation only): reserves a right-hand strip on the second monitor while a pinned PiP/mpv/Twitch window lives there, heals windows that Hyprland drags to the other monitor (unpin → move → reposition → pin), follows the bar edge (`bottom_offset` = 40 with a bottom bar, 0 with a top bar), exposes `pip_bar_changed()`.
- `autostart.lua`: quickshell, `scripts/start-hyprpaper.sh` (waits for monitors, 3 s settle, single start), clears a stale empty `XDG_DESKTOP_PORTAL_DIR`.
- `env.lua` prepends `~/.local/bin` to PATH (shims: `brave`, `qmenu`, `discord`).
- `binds.lua`: `SUPER+D` launcher, `SUPER+T` wallpaper picker, `SUPER+SHIFT+T` Twitch menu, brightness keys → `qs ipc call osd brightness`.

## Summary of what has been built (chronological highlights)

1. **Wallpaper-driven theming** of every app with live reload, hue-matched Adwaita icons, Brave seed theme, hyprlock wallpaper follows the wallpaper; `herdr` and `nautilus` configs moved into the repo.
2. **Quickshell replaced waybar, tofi and swaync**: bar, launcher/dmenus, notification server + toasts, notification center, calendar, network, bluetooth, audio, media popups, volume OSD, wallpaper picker.
3. **Look:** bar gap/rounding/border 0, Hyprland rounding 0 and 2px borders, blur-aware transparency, Adwaita icons globally, no Oxygen leftovers, portal-based Nautilus-style file dialogs in Brave.
4. **Twitch workflow:** separate project `~/code/crossatko/twitch-qs-mpv` (mpv wrapped in a Quickshell app with chat overlay; its own `AGENTS.md`), streamer menu on `SUPER+SHIFT+T`, matching Hyprland window rule, now-playing in the bar. One-time `bin/twitch-qs-mpv login` still needed.
5. **PiP/mpv layout:** reserved strip on the second monitor, healing of pinned windows, automatic alignment to the bar edge (top/bottom).
6. **Notifications:** click focuses the app including Hyprland groups, right-click dismisses with a slide-out (toasts and control center), pop-in animation, toasts/OSD ignore the reserved area.
7. **Control center:** per-monitor bar settings (enable + top/bottom), toggles (Wi-Fi, Bluetooth, DND, sound), input/output device pickers, order flips with the bar edge, min height, snappy open/close animations.
8. **Network/Bluetooth panels:** disconnect individual wired/wireless connections, shared toggle component, wired/wireless section heads, inline Wi-Fi password form in the selected card, even spacing, icon/title gap of 14px.
9. **Calendar** with Thunderbird events above the grid (reversed for a top bar).
10. **Bar polish:** workspaces per monitor (all shown when only one bar), CPU/MEM sparklines with fixed widths, vertical alignment, state-dependent volume icon, brand logo for the playing media (Spotify/YouTube/Twitch/… via `mediaBrand`), highlighted chip while its popup is open.
11. **Font Awesome 7 Pro Sharp (Regular)** for all bar and popup icons; Brands font for media logos. Installed locally only.
12. **Tray:** own themed context menu with submenus, highlighted icon while open.
13. **Boot reliability:** hyprpaper race fixed, Discord autostart on its workspace restored.
14. **Home Assistant popup:** bar chip (lights-on count) + control popup for lights, climate, vacuum (rooms, passes, suction), fans, covers, switches, scenes; credentials in `config/hypr/.secrets`.

## Open items / ideas

- Twitch project README and end-to-end verification.
- Optional: Bibata cursors instead of Oxygen, brightness via `brightnessctl` (not installed), animating notification-center list reflow, PiP rule parity for the workstation host.
- Mic chip in the bar (the mic icon currently exists only in the control center).
