# AGENTS.md — dotfiles handbook for AI agents

Public repo with the user's Linux (Arch + Hyprland) and macOS configs. Read the global `CLAUDE.md` first. State document: rules, locations, traps; no config
values (the files are the source of truth), no history. Components document themselves in their README/header; own apps (Hyprland fork, twitch-qs-mpv, tuifin,
zellij claude-tabs, AeroSpace fork, librepods) live in their own repos, only the wiring is here.

## Mandatory rules

- **Public repo: never write real setup details** (code, comments, docs, commit messages, screenshots): no tailnet names, private URLs, IP/MAC addresses,
  serials (monitor descriptions with serials, Bluetooth addresses), accounts, emails, tokens, personal channel/library/server names. Use placeholders
  (`jellyfin.example`, `192.0.2.10`, `user@example.com`). Real values stay outside the repo or in git-ignored files. Enforced by `.githooks/pre-commit` (enabled
  by `install.sh` via `core.hooksPath`; private deny-list in `~/.config/dotfiles-private/denylist`; a line containing `privacy-ok` is skipped; `--no-verify`
  only on the user's explicit decision).
- **Notes:** record config state per machine only (what is installed/linked, which file controls what, caveats), never copied values; app internals go in the
  app's repo/README.
- **Never commit per-machine files:** `config/theme/theme.local.toml`, `config/theme/out/`, `config/hypr/.secrets` (keys listed in tracked `.secrets.example`),
  `config/ghostty/host.local`, `config/wivrn/` pairing data, `config/zellij/plugins/`, `~/.zshrc.local`. Never print/log secret values.
- **Licensed fonts stay out of the repo:** Font Awesome Pro (Sharp Regular) lives in `~/.local/share/fonts/FontAwesomePro/`; Brands comes from the system
  package.
- **Commits:** no AI attribution; commit/merge/push only when the user asks.
- **Screenshots:** only the relevant window/part (`grim -g "x,y WxH"`, geometry from `hyprctl clients -j` / `layers -j`), never the whole screen or user
  content. Glass/translucency only in a nested Hyprland with a generated solid/checkerboard backdrop behind it. Hyprland dims unfocused windows; popups open on
  the focused monitor; check workspace/overlaps first.
- **Never inject synthetic input** into the live session; real clicks/keys count as "not verified" unless the user does them.

### Quickshell/Hyprland safety (each of these broke the live session once)

- Kill Quickshell only by exact PID (`pgrep -x quickshell` also matches other instances: Twitch app, probes). Also kill orphaned poller shells (ppid 1) of a
  test HOME.
- Hot reload only works for files already loaded. A new QML type needs a `qmldir` entry AND a full restart ("X is not a type"; lazily loaded Settings pages show
  it only when opened). Restart: kill the PID, then `hyprctl eval 'hl.exec_cmd("env QSG_USE_SIMPLE_ANIMATION_DRIVER=1 quickshell")'` (`hyprctl dispatch exec`
  silently does nothing with the Lua config; the env var is needed or animations run too fast). Changed `.frag`/`.qsb` shaders are not hot-reloaded either; a
  failed reload keeps the old generation; a multi-file write (checkout, stash pop) can reload between files.
- Do not edit a popup's QML while it is open (hot reload segfaulted Qt's Repeater twice). Test in an isolated instance or with the popup closed.
- Do not touch screen-sharing portal routing (`config/xdg-desktop-portal`): ScreenCast/RemoteDesktop/Screenshot stay on the Hyprland portal.
- Never run `theme.py` from a scratch copy with the real `HOME` or real `PATH` (it rewrites links in `~/.config`, `~/.local/share/themes` and `pkill`s apps by
  name).
- A Lua error at Hyprland config load disables the rest of the config and `Hyprland --verify-config` dumps core: keep every file loadable alone, `pcall`
  optional parts, check with `hyprctl configerrors` after a reload. Nested Hyprland rule: never use `ls -t` to find an instance signature.

## Machines

- Plain Arch Linux (CachyOS repos are only an opt-in), **Hyprland with the native Lua config** (`hl.*`), Quickshell (QML) for
  bar/popups/launcher/notifications/Settings, hyprpaper, hyprlock.
- **Battlestation** (primary desktop): two 2560x1440 monitors (360 Hz OLED + 60 Hz), RX 9070 XT, a living-room 4K TV output for Steam Big Picture/gamescope
  sessions. Runs the user's **Hyprland fork** at `/usr/local/bin/Hyprland` (glass compositing: `solid_glass`, `layer_alpha_ref`, workspace-created-empty fix).
  Corne keyboard with VIA.
- **Workstation** (work): stock `/usr/bin/Hyprland` (no glass), 3440x1440 ultrawide + portrait monitor, RX 5700 (no AV1 hardware decode). Corne keyboard with
  Vial.
- **Mac** (secondary, shared, Apple silicon): see macOS. Never run `install.sh` there.
- Per-host differences: `config/hypr/hyprland/host.lua` (`is_battlestation`/`is_workstation`/`is_vm` hostname flags, `is_vm` = any hostname ending in `vm` such as `xyz-vm`; `$HOSTNAME` env overrides in tests) and
  `monitors.lua`. Fork-only options must load on stock: probe with `pcall(hl.get_config)` (`managed.lua`, `Theme.qml`). `on_created_empty` workspace rules only
  fire on the fork.
- Hyprland Lua: `hyprctl dispatch "hl.dsp.focus({workspace=N})"`; `hyprctl keyword` is refused; Lua objects are userdata (nil-check, never `type(x)=="table"`);
  `hl.dsp.window.pin` TOGGLES.
- Fonts: Paper Mono (UI), Font Awesome Pro Sharp + Brands (icons). A new machine needs `inode/directory` -> Nautilus in untracked `~/.config/mimeapps.list`.

## Repository map

```
install.sh        Arch bootstrap (stages below); install-mac.sh  macOS symlinks only (--dry-run)
packages/         pacman.txt aur.txt flatpak.txt; optional/NAME.txt = opt-in bundles (--with)
system/           root-owned files (udev, systemd units, getty autologin, mullvad-tailscale), needs sudo: system/README.md
.githooks/        pre-commit (privacy), post-merge/rewrite/checkout -> theme-render
config/shell/     zshrc bashrc bash_profile inputrc (linked into ~), README.md
config/theme/     wallpaper-driven theme engine: theme.py theme.toml templates/ default/ bin/ selftest.py, README.md
config/hypr/      hyprland.lua + hyprland/*.lua (host monitors rules binds autostart managed animations ...), scripts/ (lua/sh helpers, TV/gamescope, screenshot/rec)
config/quickshell/ the shell: shell.qml Theme.qml Bar*.qml Popups/PopupHost Settings*.qml Launcher.qml launcher/ (js/ bin/ data/) bin/ shaders/
config/launcher/  script commands (commands/) + Jellyfin helper (jellyfin/); config/url-router/ link router; config/xdg-desktop-portal
config/systemd/user units + README (gamescope session); config/librepods/ AirPods daemon build (README); config/vm-guest guest clipboard bridge
config/ kitty ghostty alacritty nvim zellij herdr nautilus opencode fastfetch wivrn firefox brave-flags.conf
config/aerospace karabiner swiftbar  macOS only
```

## Install, run, test

- `./install.sh --help`: stages `repos,packages,links` by default (`system` opt-in: `--system`/`--only`; sudo asked once). `--dry-run`, `--yes`, `--cachyos`,
  `--with virtualization,video-wallpaper,gaming|all`, `--chsh`, `GPU_DRIVER=` override. `repos` adds the third-party Chaotic-AUR; skip with `--only
  links,packages`.
- Tests: `python3 -I config/theme/selftest.py` (must pass for any wallpaper); `python3 -I -m unittest discover -s config/url-router/tests` (same for
  `config/launcher/jellyfin/tests`, `config/quickshell/bin/tests`); `python3 -I config/quickshell/launcher/bin/tests/vm-ctl.test.py`; `node --test
  config/quickshell/launcher/js/tests/*.test.js`; `bash config/quickshell/launcher/bin/tests/code-open.test.sh`; `luac5.5 -p` on Lua.
- qmllint (PATH one is Qt5): `cd config/quickshell && /usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml --json - $(find . -name '*.qml')`. `--json` is required (text
  output drops warnings of files with `for (... of ...)`); diff against a `git archive HEAD` export for new-vs-baseline; per-line `// qmllint disable
  <category>`, never disable `import` globally.
- **Isolated shell:** copy `config/quickshell` to a short dir, test `HOME` (symlink `.config/theme`, `.local/share/fonts`; copy state JSONs) with own
  `XDG_*_HOME`, short `XDG_RUNTIME_DIR` with `hypr`/`wayland-1` links to the live one, `dbus-run-session ... quickshell -n -p <dir>`, drive with `quickshell ipc
  --pid <pid> call ...`. `QS_*` env hooks redirect state files, binaries, fixtures (`grep -rn 'QS_' config/quickshell`). Test launchers must not take focus
  (`keyboardFocus: None`, empty mask).
- **Nested Hyprland** (glass, scale, layers, rules, wallpapers, GTK/Qt apps): `Hyprland -c <config copy>` with its own short `XDG_RUNTIME_DIR`; `hyprctl output
  create headless TEST` + `hl.monitor{...}`; export the nested `HYPRLAND_INSTANCE_SIGNATURE`/`WAYLAND_DISPLAY`; `grim -o TEST`; headless renders only while the
  nested window is visible; enable `TEST` in the test HOME's `bars.json`; real `hyprctl` on PATH (a shim makes `Theme.glass` false). Never `pkill -f` a pattern
  matching your own command line.
- **Theme engine:** temp clone + temp `HOME` with `~/.config/theme` linked, `THEME_OUT_DIR`, PATH shims for `pkill hyprctl gsettings kwriteconfig6 herdr
  hyprpaper`.

## Workflow shortcuts (save time and tokens)

- **The live desktop is this working tree.** `~/.config/{quickshell,hypr,theme,...}` are symlinks into this clone: checking out or merging a branch hot-reloads
  the LIVE shell and Hyprland, and the git hooks run `theme.py render` on this machine. Switch branches deliberately; test risky work in isolation (below).
- **Errors first:** `qs log | tail -80` (live shell: "X is not a type", ReferenceError, load failures), `hyprctl configerrors` after a Hyprland reload.
- **Agents have no sudo.** Never run `install.sh --system`/`--only repos`, `pacman -S/-U/-R`, `pacman-key`. Test the installer with `--dry-run`, a temp `HOME`,
  `PACMAN_CONF=<copy>` and PATH stubs (`sudo`, `pacman`, `lspci`); real runs happen on a clean Arch VM that the user drives. Say what stayed unverified.
- **Packages:** repo names in `packages/pacman.txt`, AUR in `aur.txt`, Flatpaks in `flatpak.txt`; big/optional ones get `packages/optional/NAME.txt` (see Quickshell
  "Optional bundles"). Verify names with `pacman -Si` / the AUR RPC. Deliberately manual: docker group, GPU kernel drivers, Hyprland fork, licensed fonts.
- **Reading:** grep/offset-limit the source instead of whole files; component headers and the READMEs named above are authoritative, this file is not.

## Theme (`config/theme`, details in its README)

- Edit only `theme.toml` + `templates/`; never hard-code colours in app configs. Tracked: `theme.toml`, `default/`. Ignored: `theme.local.toml`, `out/` (a
  wallpaper switch changes no tracked file).
- `bin/theme-seed` fills a missing `out/` only on machines without `theme.local.toml` (fresh clone, Mac); elsewhere the hooks run `theme.py render`
  (`THEME_RENDER_SKIP=1` skips). herdr has no include: edits to its settings need `theme.py render`.
- Layout defaults in `theme.toml [settings]` drive Quickshell only; Hyprland's own values are hand-written in `hypr/hyprland/theme.lua`/`settings.lua`: keep in
  sync.
- GTK/Kvantum/Brave CSS is rendered per host into `out/host/` (alpha depends on fork vs stock): run `theme.py render` once after pulling on a new host.
- Toolkit glass: the compositor already tints/blurs behind translucent windows, so app CSS paints only the card fill (tint in CSS would double). `theme.py
  hypr_solid_glass()` and `Theme.qml` use the same test: keep in sync. GTK4 blur needs `backdrop-filter`.
- Wallpapers: for non-primary monitors the `hyprctl hyprpaper wallpaper` selector must match the config block's (`desc:<key>` vs connector), else it silently
  does nothing. Video wallpapers (mpvpaper, optimize/bake): see README "Video wallpapers".
- After theme changes run `selftest.py` and diff a dark render before/after.

## Quickshell (`config/quickshell`)

- **Where things live:** `shell.qml` (root, per-screen windows), `Theme.qml` (tokens), `Bar.qml` + `BarWidgets.qml` (bar, chip registry), `PopupHost.qml` /
  `Popups.qml` (popups), `Settings.qml` + `Settings*.qml` (Settings pages), `Launcher.qml` + `launcher/*Source.qml` (launcher sections), `Notifs.qml` /
  `NotifStack.qml` / `Toasts.qml` (notifications), `Osd.qml`, `Appearance.qml` (writes `appearance.json`), `Vm*.qml` + `launcher/bin/vm-ctl` (VM chip/panel),
  `bin/` (python/sh helpers behind sections).
- Use `Theme` tokens, never literal pixels/colours. One layer rule in `rules.lua` blurs `qs-.*`: layer-rule namespaces match the WHOLE name (a bare `^qs-`
  matches nothing and once turned all blur off).
- Reuse the shared building blocks (`PanelHeader`, `ListRow`, `Notice`, `Btn`, `Segmented`, `ModalMenu`, `PopupRegistration`, ...); extract repeated UI into its
  own file. New popup: file + `PopupHost` switch/width entries + chip `bar.pop` + qmldir. New Settings page: `allPages` in `Settings.qml` + qmldir (hooks
  documented in its header). New bar widget: registry entry in `BarWidgets.qml`. Bar chips: never set `implicitWidth`, never `BarLabel` with the icon font (use
  `BarIcon`).
- `Theme.edgeGap` is NOT the user's `edgeGap` key (that is `Theme.gapOut`).
- Appearance (`appearance.json`) is written only by `Appearance.qml`; Hyprland side is `hypr/hyprland/managed.lua` (loaded last via `pcall(require)`, no
  hand-written settings there). Adding keys: deploy theme files, then Hyprland files, then Quickshell files (every intermediate state must load). Animation base
  `A.BASE_MS` (`animations.lua`) must equal `Motion.baseMs`. Springs need `hl.animation{ spring = ... }` (`bezier =` only logs).
- Popups: never `keyboardFocus: Exclusive` on `PopupHost` (breaks click-away and one-click chip switching). Settings is a `FloatingWindow` (`qs-settings`, rule
  `qs-modal`, which must not set `rounding = 0`); layer surfaces cannot be dragged.
- Sliders: `wheel: false` inside scrolling Settings pages (a wheel once triggered a full theme apply). Shader edits need the `.qsb` rebuilt (see
  `shaders/sliderlens.frag` header) and a restart.
- Optional bundles: `OptionalPackages.qml`/`launcher/js/Bundles.js` read names from `packages/optional/*.txt` (`bundles.test.js` fails on drift). New bundle:
  txt + `Bundles.BUNDLES` + `MissingPackage` where used.
- QML gotchas: `pragma ComponentBehavior: Bound` + `required property` in delegates; `??` not `||` where `0`/`false` is valid; `Process` takes argv arrays,
  never user data in `sh -c`; no endless shell loops in a `Process` (poll with `Timer` + `FileView.reload()`); poll only while visible; no `console.log` of
  notification content or HA host; never bind `visible` to `visibleChildren`; `clip: true` ignores rounded shape; avoid binding loops from child `x`/`width`.
- VPN switching goes through `bin/vpn-switch` (exclusive vs coexist mode); Tailscale needs `tailscale set --operator=$USER` once.
- Home Assistant (`HA_URL`/`HA_TOKEN` in `config/hypr/.secrets`): test with `QS_HA_*` mocks, never service calls against the real HA. `bin/ai-usage` uses an
  undocumented endpoint and must never refresh OAuth tokens (rotates the refresh token); mocks `QS_AI_*`.

## Hyprland (`config/hypr`)

- Every bind needs a `description` (`bind(keys, desc, action)` in `binds.lua`): the launcher keybind sheet is built from them.
- Pinned PiP/mpv/Twitch boxes: Battlestation `scripts/pip-reserve.lua`, Workstation `scripts/pip-orientation.lua` + `side-pin.lua` (strip width hard-coded in
  both).
- `scripts/screenshot.sh`, `screenrec.sh`: headers list env overrides; AV1 widths must be a multiple of 8.
- Session: TTY1 autologin -> `scripts/session-supervisor.sh` (via `config/shell/bash_profile`). Corne udev rules are per machine: never install the Vial rule on
  Battlestation or the VIA rules on Workstation (`system/etc/udev/rules.d/`).
- Terminal = Ghostty (`apps.lua` `terminal`; kitty is the fallback). The scratchpad class must contain a dot (`dotfiles.scratchpad`) or GTK ignores it.

## Launcher (`Launcher.qml`, `launcher/`)

- Sources are QtObjects added to `sourceList` in `Launcher.qml`; id prefixes and `transient`/`private`/`confirm`/`alt` semantics: `Launcher.qml`,
  `launcher/js/README.md`.
- `launcher/` files cannot see root singletons: `Launcher.qml` wires `VmSource`/`Binds` to them. Wi-Fi passwords and tokens never go in argv.
- `vm-ctl`: quickemu exits 0 on errors (the script greps output); never put the vdagent port in a conf's `extra_args`. `code-open` relies on zellij's `<session>
  | <pane>` title format, and passes the tab cwd in a `--layout-string` (a resurrected session's new_tab_template cwd beats `new-tab --cwd`).

## systemd / gamescope TV session

`config/systemd/README.md` is authoritative (WAYLAND_DISPLAY must be UNSET in the rootful gamescope session; wake-source and delay-inhibitor notes). TV scripts:
`config/hypr/scripts/tv*.lua`, `tv-*.sh`, `steam-*.lua`, `gamescope-*`; read their headers. `steam-tv-dim.lua`/`steam-streaming.lua` re-apply the palette
wallpaper to hyprpaper on TV resyncs.

## Shell, url-router

- `config/shell/zshrc`: `eval "$(zoxide init zsh)"` stays the LAST line. Bash is the Linux login shell (`install.sh --chsh` switches to zsh).
- `config/url-router/bin/url-router` is the default http(s) handler (docs in its header, template `config.example`); Brave's "make default" resets the handler.

## macOS

Linked only by `./install-mac.sh` (symlinks, `--dry-run`, backups `*.bak.<timestamp>`). The theme engine never runs there (`theme.py` exits 0 on darwin;
`bin/theme-seed` copies `default/` into `out/`). Brew packages are not listed in the repo; Oh My Zsh is a git clone.
- Ghostty: shared `config/ghostty/config` + Mac overrides `macos.conf`. kitty: `${KITTY_OS}.conf` include.
- WM = own AeroSpace fork (`crossatko/AeroSpace`; build/sign/install in its README), config `config/aerospace/aerospace.toml`. Accessibility survives rebuilds
  only while the signing identity `aerospace-codesign-certificate` stays in the login keychain: do not delete it.
- `config/karabiner/karabiner.json` is GENERATED: edit the table in `generate.py`, run `python3 -I config/karabiner/generate.py` (`--aerospace` prints the
  matching bindings).
- SwiftBar plugin `config/swiftbar/ai-usage.10m.py` reads the Claude token from the Keychain. Set `user.name`/`user.email` on the Mac (else the hostname lands
  in commits).
- `wl-copy` for zellij is a host-local symlink to `pbcopy` (not in the repo).

## Open items

- Workstation: no glass on stock Hyprland; `qt_style = "kvantum"` needs `kvantum` there; AV1 wallpaper videos wait for the HEVC copy.

