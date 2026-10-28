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
  bar/popups/launcher/notifications/Settings/lock screen and the wallpaper image (theme.toml `wallpaper_backend`, default
  `quickshell`; `engine` = the wallpaper engine, a second Quickshell instance for wallpaper + videos + desktop clock;
  hyprpaper = optional fallback backend; hyprlock = fallback only, below).
- **Battlestation** (primary desktop): two 2560x1440 monitors (360 Hz OLED + 60 Hz), RX 9070 XT, a living-room 4K TV output for Steam Big Picture/gamescope
  sessions. Runs the user's **Hyprland fork** at `/usr/local/bin/Hyprland` (glass compositing: `solid_glass`, `layer_alpha_ref`, workspace-created-empty fix).
  Corne keyboard with VIA.
- **Workstation** (work): stock `/usr/bin/Hyprland` (no glass), 3440x1440 ultrawide + portrait monitor, RX 5700 (no AV1 hardware decode). Corne keyboard with
  Vial.
- **Mac** (secondary, shared, Apple silicon): see macOS. Never run `install.sh` there.
- Per-host differences: `config/hypr/hyprland/host.lua` (`is_battlestation`/`is_workstation`/`is_vm` hostname flags, `is_vm` = any hostname ending in `vm` such as `xyz-vm`; `$HOSTNAME` env overrides in tests) and
  `monitors.lua`. Fork-only options must load on stock: probe with `pcall(hl.get_config)` (`managed.lua`, `Theme.qml`). The empty-workspace app launch (`workspace.created` handler in `workspaces.lua`)
  is stock-compatible and needs no fork.
- Hyprland Lua: `hyprctl dispatch "hl.dsp.focus({workspace=N})"`; `hyprctl keyword` is refused; Lua objects are userdata (nil-check, never `type(x)=="table"`);
  `hl.dsp.window.pin` TOGGLES.
- Fonts: Paper Mono (UI), Font Awesome Pro Sharp + Brands (icons). A new machine needs `inode/directory` -> Nautilus in untracked `~/.config/mimeapps.list`.

## Repository map

```
install.sh        Arch bootstrap (stages below); install-mac.sh  macOS symlinks only (--dry-run)
packages/         pacman.txt aur.txt flatpak.txt; optional/NAME.txt = opt-in bundles (--with)
system/           root-owned files (udev, systemd units, getty autologin, mullvad-tailscale), needs sudo: system/README.md
.githooks/        pre-commit (privacy), post-merge/rewrite/checkout -> theme-render
config/shell/     zshrc bash_profile inputrc (linked into ~), README.md
config/theme/     wallpaper-driven theme engine: theme.py theme.toml templates/ default/ bin/ selftest.py, README.md
config/hypr/      hyprland.lua + hyprland/*.lua (host monitors rules binds autostart managed animations ...), scripts/ (lua/sh helpers, TV/gamescope, screenshot/rec)
config/quickshell/ the shell: shell.qml Theme.qml Bar*.qml Popups/PopupHost Settings*.qml Launcher.qml launcher/ (js/ bin/ data/) bin/ shaders/
                  Calendar chip/popup: bin/calendar-events serves events from `omacal` (CLI, if on PATH with calendars; right-click opens it, window class `omacal`); without it the popup is empty with an `error` string and right-click only notifies. omacal is not packaged: `install.sh` (packages stage, `install_omacal`) fetches the author's PKGBUILD (`packaging/aur` in github.com/x3me/omacal) from a pinned commit, checks its sha256, runs `makepkg` as the user and `sudo pacman -U` (bump `OMACAL_COMMIT` + `OMACAL_PKGBUILD_SHA256` after reviewing a new PKGBUILD; skip with `INSTALL_SKIP=omacal`; needs a Secret Service, gnome-keyring is in pacman.txt). Mail is Geary (`apps.mail`, class `org.gnome.Geary`, workspace 8). Discord is Vesktop (`apps.discord = vesktop`, class `vesktop`, workspace 7; rules also match the official `discord` class, which stays installed; its `~/.local/bin/discord` flags wrapper is untracked). Flags: tracked `config/vesktop-flags.conf` linked to `~/.config/vesktop-flags.conf`. The links stage sets xdg defaults (mailto -> Geary, text/calendar -> omacal, discord:// -> Vesktop) via `default_handler`, only for installed apps.
                  With omacal the popup also has an inline add form (`CalAddEvent`, an agenda-style card that replaces the agenda and grows the area away from the grid: flat title `FieldBox`, `FormRow` rows for times/all day, last day (`DateStepper`, steppers/wheel only), calendar (`CalPicker` = `DropSelect` inline dropdown); runner `CalCreate` -> `omacal events create ... --calendar ID`, argv/validation in `launcher/js/CalEvent.js`, last calendar in `cal-add.json`; `QS_OMACAL`/`QS_CAL_ADD_FILE` override). Never run a real omacal write when testing: stub `omacal` on PATH (exit 5 = not running -> `--autostart` + one retry).
config/launcher/  script commands (commands/) + Jellyfin helper (jellyfin/); config/url-router/ link router; config/xdg-desktop-portal
config/systemd/user units + README (gamescope session); config/librepods/ AirPods daemon build (README); config/vm-guest guest clipboard bridge
config/ kitty ghostty alacritty nvim zellij herdr nautilus opencode fastfetch wivrn firefox brave-flags.conf vesktop-flags.conf
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
  matching your own command line. Keep the test HOME, runtime dir, logs and screenshots in the agent scratchpad dir (the Wayland socket path must stay < 108 chars: use a short symlink into it).
  Nested outputs must be visible (no headless outputs): extra monitors via `hyprctl output create wayland <name>` against the nested instance.
  The nested window opens tiled on the CURRENT workspace (no scratchpad rule any more): its output size follows the live tiling, so keep
  sessions short, verify pointer coordinates (`hyprctl cursorpos` on the nested instance) before a virtual click, and stop everything by PID at the end.
  Caveats: find the nested instance signature as the `$XDG_RUNTIME_DIR/hypr/*/` dir whose `hyprland.lock` holds the nested PID (old dirs linger; a stale
  signature makes hyprpaper / quickshell talk to a dead instance); hyprpaper 0.8 takes `hyprctl hyprpaper wallpaper ",<path>"` (`preload` / `reload`
  are gone); a nested STOCK Hyprland shows the config-error overlay for the fork-only keys in `settings.lua` (they are not `pcall`-guarded), which
  covers part of the output; a nested window sometimes starts without an output (log stops after "New wayland pointer"): stop and start it again.
  A test harness (own HOME / runtime dir, pops / look / shape / glass / anim / wall / mode / measure scripts) lived in the agent scratchpad `dl/`.
- **Theme engine:** temp clone + temp `HOME` with `~/.config/theme` linked, `THEME_OUT_DIR`, PATH shims for `pkill hyprctl gsettings kwriteconfig6 herdr
  hyprpaper`. `apply` returns after the foreground and leaves a detached worker: `--wait` runs it in place, `THEME_ANALYZE=0` stops the library
  precompute, `THEME_PROFILE=<file>` times every stage; kill leftover workers / players by PID.

## Workflow shortcuts (save time and tokens)

- **The live desktop is this working tree.** `~/.config/{quickshell,hypr,theme,...}` are symlinks into this clone: checking out or merging a branch hot-reloads
  the LIVE shell and Hyprland, and the git hooks run `theme.py render` on this machine. Switch branches deliberately; test risky work in isolation (below).
- **Errors first:** `qs log | tail -80` (live shell: "X is not a type", ReferenceError, load failures), `hyprctl configerrors` after a Hyprland reload.
- **Agents have no sudo.** Never run `install.sh --system`/`--only repos`, `pacman -S/-U/-R`, `pacman-key`. Test the installer with `--dry-run`, a temp `HOME`,
  `PACMAN_CONF=<copy>` and PATH stubs (`sudo`, `pacman`, `lspci`); real runs happen on a clean Arch VM that the user drives. Say what stayed unverified.
- **Packages:** repo names in `packages/pacman.txt`, AUR in `aur.txt`, Flatpaks in `flatpak.txt`; big/optional ones get `packages/optional/NAME.txt` (see Quickshell
  "Optional bundles"). Verify names with `pacman -Si` / the AUR RPC. Deliberately manual: docker group, GPU kernel drivers, Hyprland fork, licensed fonts.
- **HDR (main OLED monitor, `hyprland/monitors.lua` monitor1):** auto HDR: `cm = "srgb"` + `render:cm_auto_hdr = 1`, 10-bit, `sdrbrightness = 1`, `sdrsaturation = 1.0`, `sdr_min_luminance = 0.005`, `sdr_max_luminance = 80`. HDR engages only for HDR content (native Wayland clients); the display blanks for a few seconds on each mode switch, which is why `cm = "hdr"` (always-on, SDR white ~250 nits via `sdr_max_luminance`) was tried and can be restored. The fork has no `max_luminance`/`min_luminance` monitor keys. Apply by editing and `hyprctl reload` (`hyprctl keyword` is refused under Lua). Avoid rapid cm changes while gamescope renders (DRM abort). Brave runs with WaylandWpColorManagerV1 disabled (`config/brave-flags.conf`).
- **Reading:** grep/offset-limit the source instead of whole files; component headers and the READMEs named above are authoritative, this file is not.

## Theme (`config/theme`, details in its README)

- Edit only `theme.toml` + `templates/`; never hard-code colours in app configs. Tracked: `theme.toml`, `default/`. Ignored: `theme.local.toml`, `out/` (a
  wallpaper switch changes no tracked file).
- `bin/theme-seed` fills a missing `out/` only on machines without `theme.local.toml` (fresh clone, Mac); elsewhere the hooks run `theme.py render`
  (`THEME_RENDER_SKIP=1` skips). herdr has no include: edits to its settings need `theme.py render`.
- Layout defaults in `theme.toml [settings]` drive Quickshell only; Hyprland's own values are hand-written in `hypr/hyprland/theme.lua`/`settings.lua`: keep in
  sync.
- Hyprland group bar (`group.groupbar` in `settings.lua`, values in `theme.lua` `M.groupbar` / `groupbar_colors` /
  `groupbar_rounding`): one glass pill per window, no titles, 12 px (slimmest that reads as glass; 14-16 = safe), 6 px between pills and above the window, pill tops
  level with the neighbours (`keep_upper_gap = false`). Radius = min(window radius, height / 2) (0 = square), re-applied by
  `managed.lua` `apply_groupbar` on `layout_apply()`. `groupbar.blur` puts the fork's solid_glass lens under each pill
  (stock: plain blur); fills are washes: half the card fill on glass, else max(0.3, 0.75 x plain_fill_min) plus a ~1 px
  lit top edge (gradient stops). Focused = accent glass, others neutral, locked = warn hue. Glass test at load =
  `decoration.blur.variant` solid_glass (as Theme.qml). Hyprland has no hover state, icons or per-tab widths, and an
  unfocused group shows every pill inactive. Colour / mode changes need `theme.py render` + `hyprctl reload`.
- GTK/Kvantum/Brave CSS is rendered per host into `out/host/` (alpha depends on fork vs stock): run `theme.py render` once after pulling on a new host.
- Toolkit glass: the compositor already tints/blurs behind translucent windows, so app CSS paints only the card fill (tint in CSS would double). `theme.py
  hypr_solid_glass()` and `Theme.qml` use the same test: keep in sync. GTK4 blur needs `backdrop-filter`.
- Wallpapers: who draws the image = `[settings] wallpaper_backend` (README "Wallpaper backend"): `quickshell` (default) = the shell's
  background layer reads `out/wallpaper.json` (the resolved blocks of `out/hyprpaper.conf`); theme.py never starts / restarts hyprpaper
  then (`start-hyprpaper.sh` asks `theme.py wallpaper-backend`). `hyprpaper` = the old path: for non-primary monitors the
  `hyprctl hyprpaper wallpaper` selector must match the config block's (`desc:<key>` vs connector), else it silently does nothing.
  `steam-tv-dim.lua` / `steam-streaming.lua` still set the TV wallpaper through hyprpaper directly (no effect with the quickshell backend). Video wallpapers (mpvpaper, optimize/bake): see README "Video wallpapers". Play-once without stored
  timing = play 0 / wind 5 / ease 0 (theme.toml); full length is `"play": "full"`.
  `engine` = `config/quickshell/engine.qml` (README "Wallpaper engine": switch / rollback, IPC, measurements): theme.py writes
  player RECORDS (`ep_start`, `theme-video/engine/players.json`) instead of starting mpvpaper / hyprpaper; selftest covers it.
- After theme changes run `selftest.py` and diff a dark render before/after.
- Wallpaper switch (README "Instant switch"): the foreground only saves the pick and switches hyprpaper / the players (< 100 ms); a detached
  worker (`apply-bg`, latest click wins via `$XDG_RUNTIME_DIR/theme-apply/status.json`) does stills, analysis (per-file cache, `theme.py analyze`
  precomputes the library), render, reloads. `blobs/` = `theme-blobs` (Rust, `theme.py build-helper`), bit-identical to the Python standout pass,
  which stays the fallback and selftest's oracle: change both together and bump `BLOBS_VERSION` / `EXTRACT_VERSION`.

## Quickshell (`config/quickshell`)

- **Where things live:** `shell.qml` (root, per-screen windows), `Theme.qml` (tokens), `Bar.qml` + `BarWidgets.qml` (bar, chip registry), `PopupHost.qml` /
  `Popups.qml` (popups), `Settings.qml` + `Settings*.qml` (Settings pages), `Launcher.qml` + `launcher/*Source.qml` (launcher sections), `Notifs.qml` /
  `NotifStack.qml` / `Toasts.qml` (notifications), `Osd.qml`, `Appearance.qml` (writes `appearance.json`), `Vm*.qml` + `launcher/bin/vm-ctl` (VM chip/panel),
  `bin/` (python/sh helpers behind sections).
  Caveat: `Theme.qml` watches `palette.json` with a FileView; in nested test shells (HOME/.config/theme a symlink re-created by the
  test scripts) a theme.py mode switch was sometimes not picked up until a shell restart. Not reproduced on the live shell.
- Use `Theme` tokens, never literal pixels/colours. One layer rule in `rules.lua` blurs `qs-.*`: layer-rule namespaces match the WHOLE name (a bare `^qs-`
  matches nothing and once turned all blur off).
- Reuse the shared building blocks (`PanelHeader`, `ListRow`, `Notice`, `Btn`, `Segmented`, `ModalMenu`, `PopupRegistration`, ...); extract repeated UI into its
  own file. New Settings page: `allPages` in `Settings.qml` + qmldir (hooks documented in its header), built with the Settings pattern below. New popup / bar
  widget / setting: `DESIGN.md` "Adding things". Bar chips: never set `implicitWidth`, never `BarLabel` with the icon font (use `BarIcon`).
- **Design language: `DESIGN.md`** (tokens, colour roles, icon rules and the `Icons.qml` registry, component anatomy, state and
  motion rules, how to add a bar widget / popup / setting). Rules of thumb: `Theme` tokens only (a content cap is a named property),
  `Icons.<name>` for every glyph, shared parts (`ListRow`, `Btn`, `EmptyState`, ...) instead of inline re-draws, one ink at rest and
  accent only for on / selected / open. A new shared file needs a qmldir entry and a shell restart.
- **Settings** (`Settings.qml`, `allPages`: `look` Look & feel = `SettingsLook.qml` (Colour mode; Glass / Motion / Shape presets with previews; folds
  `GlassAdvanced` / `MotionAdvanced` / `ShapeAdvanced` = the former Glass / Animations / Appearance pages, whose ids redirect there), `monitors`, `wallpaper`,
  `bar`, `lock`, `deskclock`). Page pattern: title only, no intro; the 1-3 primary choices first (`PresetCards` = visual cards with a live preview Component and a
  tick, `ChoiceRow` = `Segmented` + `CustomTag` + a <= 5-word `hint` + `InfoTip`), then one `AdvancedFold` ("Customise…", `detail` = a short badge such as
  "3 changed") holding every detailed row (`PrefSlider` / `PrefToggle` / `PrefSwitch` / `GlassOptRow`), then `PageReset`. Words: labels, value badges, an
  `InfoTip` (hover tooltip; lock / warning glyph for a disabled or unavailable thing) for the rare technical note; never sentences or footnotes. Presets =
  named value sets in `Presets.qml` (glass, motion, shape, bar look, lock layout / size / backdrop, morph, desk clock size): `<area>Current` says which
  set the saved values equal within a tolerance, else "custom" (nothing is migrated; Custom keeps the saved values until a preset is picked; a slider in the
  fold turns the choice into Custom), `apply<Area>()` writes through the stores' own setters. Adding a setting: a primary choice only when it is a clear
  few-way decision with a preview, otherwise a row inside the fold; a new preset = one table entry. Previews: `GlassSample` (a sketch; the Settings window
  itself is the real compositor glass), `MotionDemo`, `ShapeDemo`, `BarLookSample`, `LockSketch`, `LockPreview`, `DeskClockPreview`, `GridPick` (3x3
  position). Test hooks: `qs ipc call settingsui locate <objectName> | reveal <objectName> | scroll <y> | grab <png under /tmp> | size <w> <h> | fold <objectName> 1|0 | showAt <objectName> <y>` (`grab` = the card's own
  full-size rendering without the compositor glass: nested outputs are often too small for grim). Caveats: a light-mode glass set that differs from the
  dark one shows Custom in light mode (the saved light set has clarity 0, the Liquid preset 0.247); the 760 px minimum window fits the folds only with
  elided section details; older comments / notes saying "Settings > Glass / Animations / Appearance" mean the Look & feel folds.
- **Lock screen** (replaces hyprlock; `Lock.qml` service + `LockView/LockClock/LockField/LockDots/LockVideo/LockReveal.qml`, glass in
  `GlassShape/GlassText/GlassBead.qml`, `qs ipc call lock lock|locked|secure|status`; `status` lists per screen the still's file name and, while locked, the clip, `videoReady`
  and what the surface shows: still / video / none): an ext-session-lock inside the main shell. Callers go
  through `bin/lock-now` (hypridle `lock_cmd`, SUPER+SHIFT+L; falls back to hyprlock when the shell or the PAM service is missing), hypridle
  `before_sleep_cmd` (workstation) = `bin/lock-wait` (blocks until `secure`, 4 s cap). Password = PAM service `quickshell-lock`
  (`system/etc/pam.d/`, installed only by `install.sh --system`; until then the lock refuses with `missing-pam`). A crashed shell leaves
  Hyprland's failsafe; the restarted shell takes the lock over (`bin/lock-stranded`, needs `misc:allow_session_lock_restore`, set in
  `settings.lua`; a test shell killed while locked re-locks on restart).
  Each monitor shows its own wallpaper still (`LockWallpapers`: theme.py `wallpapers.json` by monitor key, else the primary's), pre-decoded at
  shell start (same url/size as the lock's Image: a cache hit), and its own video clip. Locking is immediate unless outputs changed in the
  last 1.5 s (then the old 500 ms settle); `LockView` is compiled once at start. Measured in the nested session: `lock-now` returns in
  ~15 ms; lock surfaces created ~5 ms later, the compositor's configure arrives ~150 ms after that and secure ~230 ms (compositor / window
  setup, not shell work). Look: blurred wallpaper, glass clock (one `GlassText` per character: no melting between glyphs; a changed digit
  morphs between two shape fields) forming left to right after the lock is up, flat date, no field/labels: typed characters are glass beads (`LockDots`, ListModel: only the new bead animates; pulse while PAM
  checks, red + shake + clear when wrong). Glass = `shaders/glassfield.frag` (once per mask, RGBA16F: coverage, smooth multi-radius blurred
  height clipped to the glyph, shadow blur) + `glasstext.frag` (normals from that height, refraction of the SHARP scene, fresnel
  reflection, soft highlights, shadow); rebuild with `qsb --qt6`. Masks render 2x (mipmapped) on scale-1 outputs. Driven by Settings > Glass
  (`GlassTuneCtl.effective`) but mapped: frost/clarity ignored, tint/darkening faint, aberration at half scale (0 = none, else >= 0.01:
  the full value fringed every stroke on high-contrast wallpapers). No compositor glass on a lock surface; the
  lettering / beads / slab are shell-drawn (`Theme.shellGlass`, also on stock Hyprland); `GlassTextFlat` + flat dots only
  when the shaders fail (or `QS_SHELL_GLASS=0`). All motion goes through `Theme.popupMs` (animation speed; off = instant).
  Lock/unlock transition: right before the lock is taken, `grim -t ppm` snapshots every output into `$XDG_RUNTIME_DIR/qs-lock` (0700,
  deleted on unlock; skipped on a stranded takeover; ~15 ms, 120 ms cap, a late one is dropped). The snapshot covers the surface from its first frame, a glass ring
  (`LockReveal`, `shaders/lockreveal.frag`) closes over it, and after a correct password the ring opens back onto it before
  `locked = false` (`Theme.lockRevealMs`). No snapshot = instant. Caveat: the desktop may have changed while locked (e.g. the video
  wallpaper advanced), so the last transition frame can differ from the real desktop.
  Settings > Lock screen (`SettingsLock.qml`, built like the Desktop clock page: monitor section (`MonitorSection` switchable: lock clock per monitor + All, objectNames `monitor-chip-<conn>-switch`, `lock-monitors-all`) > Preview head (eye-slash Off, Replay, Lock now) > `LockPreview` > Layout cards (`LockSketch`: the picked monitor's still with the saved backdrop) > Clock (Size / Seconds / Time / Morph) > Look (Backdrop) > Customise… > PageReset; Layout and Clock dim while the picked monitor has no lock clock) edits `LockPrefs` (lock.json next to animations.json,
  same storage pattern as Motion; `qs ipc call lockprefs ...`): dim (`Theme.lockDim`, blurred backdrop and what the glass refracts; MULTIPLIES by 1 - dim: a black veil
  over the blur and `glasstext.frag` `seen()`. MultiEffect `brightness` subtracts and turned a dark blurred video frame fully black on one
  monitor), blur,
  clock/dot size, date, 24h, seconds, morph time, clock screens (`clock` bool, default true, + `hidden` map by `Appearance.monitorKey`: the desktop clock's
  rule `launcher/js/MonitorShown.js` with `clock` as its `enabled`, read via `LockPrefs.clockOn(screen)` / `clockOnKey`, written only via `setClockOn` /
  `setAllClock` (lock page "Show", Monitors card); files without `clock` read as before; `ipc call lockprefs hideClockOn|showClockOn <key> | clockAll true|false`;
  off = no clock/date/playback card there, the dots keep their place), playback
  card, clock reveal, snapshot, unlock ring, video bursts; defaults = the stock look. Its preview (`LockPreview`) is
  a real `LockView` with `preview: true` (no input/video/lock, sample playback card) at a virtual 1920x1080, 16:9. Per-monitor stills: `LockWallpapers`. Backdrop chain is
  `bleed` px larger than the screen (no dark blur edges); the video goes in as its own layer (a ShaderEffectSource of the
  VideoOutput inside another layer stays empty). Play-once video wallpapers: `LockVideo` plays the same baked clip (QtMultimedia, paused =
  no decode, ~0 % CPU; `ready` only after a real decoded frame, else the still stays; re-parks if the backend stops a player on its own, seen on a
  second surface right after loading) and never seeks except to park and at the clip's wrap (seeking a paused player showed a keyframe: jumps); one burst
  when the lock engages (`LockView.engaged` = secure; surfaces exist earlier), and on typing / Enter (`bin/lock-video` reads the desktop
  player's state). The desktop player is NOT advanced while locked (hidden, it stalled and fast-forwarded at unlock): before the snapshot,
  `bin/lock-desktop-video hold` freezes a player that is mid-burst (`script-message winddown-hold` + pause: an unbaked clip's
  runtime wind-down ramp runs on wall time and, only paused, finished while locked and seeked to the stop frame = a jump at
  unlock; players started with an older winddown.lua get the pause only) and `release` continues it after unlock
  (`winddown-release` shifts the ramp by the time held), so the reveal ends on the frame
  the desktop is really on. Image/loop wallpapers show the still. Test hooks: `QS_LOCK_PAM_DIR`,
  `QS_LOCK_PAM_SERVICE`, `QS_LOCK_WALLPAPER`, `QS_LOCK_VIDEO`, `QS_LOCK_ARGS`, `QS_LOCK_CLOCK` (fixed clock text; several separated by spaces cycle every 3 s), `QS_WALLPAPERS_FILE`. Revert to hyprlock: point
  the two `lock_cmd`s and the bind back at `hyprlock` (`hyprlock.conf` is untouched).
  Playback card (`LockMedia`, under the dots, only while a media source exists: `MediaSources.current`, below): the media panel's parts `MediaArt` /
  `MediaSeek` / `MediaTransport` / `MediaStats` / `FitLabel` (shared with `MediaPanel`); title 2 lines then elided, artist 1 line, stats wrap
  onto more lines on a narrow card; only play / pause / previous / next there (never stop / show window / volume); glass slab = `GlassShape` over a rounded-rect mask, flat card without
  `Theme.shellGlass`. Pointer clicks work on the ext-session-lock surface and do not take the password field's focus (nested test: virtual
  pointer + mpv/mpris.so on the nested shell's bus; play/pause/next/previous reached the player, typing went on).
- **Media sources** (`MediaSources.qml` singleton; bar media chip, `MediaPanel` popup, `LockMedia`): one list of normalized
  `MediaSource` objects (title / subtitle / caption / category / name / chipText / artUrl / glyph, playing, live, viewers, liveSince,
  muted, volume, `can*` flags, `command` signal for toggle / previous / next / stop / raise / mute / unmute / volume:<n>). Providers:
  `MprisSource` (one per MPRIS player, pass-through; `mpris` = the raw player for the seek bar and the chip's brand guess) and
  `TwitchSource` (twitch-qs-mpv: embedded libmpv has no MPRIS). Pick rule (`active`, the chip): a playing MPRIS player, else Twitch if
  it plays, else a paused MPRIS player with a title, else Twitch (paused); `current` (cards) adds "any MPRIS player"; `list` =
  `current` first + the others with a title (popup switcher = `Segmented`, shown with 2+ sources). The TV card (`TvSource`): a
  sent session wins outright; an auto-detected one ranks after playing MPRIS / Twitch when playing, last when paused.
  Twitch status file (written by the app; the contract lives in its README "Now-playing status file"): `$XDG_RUNTIME_DIR/twitch-qs-mpv-now.json`,
  stale after 45 s. v1 = `{channel, playing, title, game, live, updated}`; v2 adds `paused, volume, muted, viewers, startedAt (ms),
  caps`. A control shows only when its cap is listed (`pause` = play/pause also on the lock card, `mute` / `volume` = the popup's
  volume row, `stop`, `raise`); no `caps` = a v1 app = stop + show window, popup only. Actions run the app's CLI
  (`twitch-qs-mpv pause on|off` (explicit, from the file's `paused`), `mute on|off`, `volume <0-100>` (sent at most every 120 ms;
  the requested value shows for 1.5 s until the file has it), `quit`); show window = hyprctl focus by title `Twitch - `. Picture = the
  app's cached avatar (`~/.cache/twitch-qs-mpv/avatars/<login>.*`), else the Twitch mark. Chip: channel · category, elided at 460 px;
  left = popup, other buttons = show window. Popup: title / subtitle `FitLabel` (2 lines then elided, full text in a `TipBubble`
  on hover), category line (gamepad), `MediaStats` (LIVE pill, viewers user glyph 999 / 1.2K / 45.6K / 1.1M cut not rounded,
  stream time clock glyph H:MM:SS ticking each second only while visible; caption = Offline / Paused / the player name), volume
  `LevelRow` for a source with `canVolume`. Add a source: a `MediaSource` subtype filling what it knows + `onCommand`, instantiated
  in `MediaSources` and added to `active` / `list`. Test hooks: `QS_TWITCH_NOW_FILE`, `QS_TWITCH_CACHE_DIR`, `LAUNCHER_TWITCH_DIR`
  (stub CLI). Nested-verified: a mock v2 writer + stub CLI (fresh / stale / paused / offline / viewers null / v1 / pause-only, long
  latin / no-space / CJK / emoji / RTL titles and categories, narrow 284 px lock card, light / dark, glass / stock, per-screen lock
  clock, pause from popup and lock card) and the real app (scratch copy, libmpv, mock Helix / streamlink) driven from the popup and
  lock card. Caveats: not run against real Twitch; the password field keeping focus after a lock-card click was not re-checked by
  typing (same MouseArea `Btn` as before).
- **Send to TV** (media popup only, never the lock card): `TvButton` (icon only, at the transport row's end outside its layout,
  fades in place) -> `TvCast.qml` (singleton: flow, TV state, IPC `tvcast`) -> Home Assistant via `HomeAssistant.request` (same
  URL / token). Pure logic in `launcher/js/TvCast.js` (node tests `tvcast.test.js`): `identify` (what plays) and `plan` (HA calls per
  integration = the `ADAPTERS` table). Target / options = `TvPrefs` (tv.json: `tv` = {name, entities: [{id, adapter}]},
  `entity` = its first id (a file with only `entity` still works and is migrated to `tv` on the first HA read), `pauseAfter`
  default on, `dryRun` = on while no entity, else off unless set; `QS_TVCAST_FILE`), Settings > TV (`SettingsTv`: ONE entry
  per physical TV, icon + device name + state dot, never a backend word: `Js.tvGroups` over every `remote.*` / `media_player.*`
  with an adapter plus its HA device from one read-only template (device_id / device_attr name, name_by_user, maker, model,
  MAC); devices merge on a shared MAC, or the same name with backend words ("- Remote", "- Google Cast") stripped, or the
  same original name + model, only while no adapter appears twice (two identical TVs stay apart; a model note shows only
  for same-named entries); Pause here, Dry run, Test = open the YouTube app home). Per send `Js.pickMember` takes the first
  entity not unavailable / unknown in `ORDER` (remote.* Android TV Remote, its media_player.*, ADB, Cast).
  Identification: Twitch app = status-file `channel`; mpv = its MPRIS `xesam:url` (Jellyfin stream `/Videos/<id>/stream` from
  jellyfin-qs, or a YouTube / Twitch URL); Firefox-like = cover URL (`i.ytimg.com/vi/<id>/`, `live_user_<login>-`); Chromium
  family (Brave, Chromium, Chrome, Vivaldi, Edge: no URL over MPRIS, cover = a local temp file) = `bin/browser-tab-url`
  reads the profile's newest `Sessions/Session_*` (SNSS, read-only) and prints the URL of the tab whose title contains the
  track title (Twitch: starts with the artist), else the newest matching row of the profile's `History` (SQLite, immutable
  read-only: Brave's session file can lag minutes behind an in-page YouTube navigation), youtube / twitch URLs only; asked
  when the card shows a title (paused too), a miss asked again every 5 s while the popup is open (24 tries per title, reset
  on reopen), a hit kept; the helper is killed after 5 s. Start position = MPRIS position (YouTube, Jellyfin); Twitch joins live.
  Button rule (`Js.shown`): shown only when it would work: HA configured and answering, TV entity set and not
  unavailable / unknown / missing (off / standby SHOWS: waking is the point), recognised kind with an id the adapter
  supports; otherwise hidden (no disabled state). TV state = one `GET /api/states/<id>` on popup open and every 10 s while it
  is open; nothing at rest. Flow: read state -> off/standby: wake (adapters with `launchWakes` send the launch itself, else
  `turn_on`) -> poll until on (25 s) -> 3 s grace -> launch (again) unless the foreground app already matches -> verify via
  `current_activity` / `app_id` (8 s), one retry -> state-gated calls (Cast seek once `playing`) -> pause here. Glyph = progress:
  tv, power (waking, pulses), circle-play (opening, pulses), check, warning (red; tooltip = the error); click while busy
  cancels. Adapters: `remote` + androidtv_remote = `remote.turn_on {activity: link}` (powers on + opens); `media_player` +
  androidtv_remote = `turn_on`, then `play_media {media_content_type: url}`; androidtv (ADB) = `turn_on`, then
  `androidtv.adb_command "am start -a <action> -d '<link>' <package>"` (VIEW; Wholphin: its PLAYBACK action); cast = YouTube only:
  `play_media {media_content_type: cast, media_content_id: {"app_name":"youtube","media_id":ID}}` + `media_seek`. Links
  (`APPS`): YouTube `https://www.youtube.com/watch?v=ID&t=Ns` (com.google.android.youtube.tv), Twitch
  `twitch://stream/<login>` (tv.twitch.android.app), Jellyfin = Wholphin `wholphin://play?itemId=<id>&position=<ms>`
  (com.github.damontecres.wholphin, its Intents.md; needs Wholphin's auto sign-in). Wholphin plays only on action
  `com.github.damontecres.wholphin.PLAYBACK` (IntentService.kt: the action wins, the URI host counts only without one); a
  VIEW (all Android TV Remote sends) opens the item's details page, so `APPS.jellyfin.afterOpen` presses `DPAD_CENTER` once
  (2.5 s after the app is in front; via the TV's remote.*, `remote.send_command`): the page focuses its first play button
  (Resume / Play; read from EpisodeDetails / ExpandablePlayButtons, movies assumed alike). Never pressed twice (playback is
  not observable; a second OK would pause). Real-TV checked by the user: wakes + opens the right episode; the OK press is not.
  Add an app: an `APPS` entry + `identify`
  rule + test; an integration: an `ADAPTERS` entry keyed `<domain>_<integration>` + test. Test hooks: `QS_TVCAST_TIMES`
  (wake,grace,verify,poll ms), `QS_BROWSER_TAB_URL`, `qs ipc call tvcast status|last|log|send|test|cancel|refresh|candidates`,
  `tvprefs get|set|unset|reset`; a stateful HA mock (states, template, device registry with one TV as two devices, service log, wake delay,
  boot-ignored launches) + a mock MPRIS player (Brave's shape: no DesktopEntry, no URL, temp cover, paused).
  Real TV procedure (the user): Settings > TV, pick the TV, turn Dry run on,
  `qs ipc call tvcast test` + `tvcast last` (the planned call), Dry run off, `tvcast test` again (wakes the TV, opens YouTube's
  home), then the button on a playing YouTube video. Caveats: verified against the mock only (never a real TV / HA); YouTube
  `t=` seeking, Twitch's TV app handling `twitch://stream/`, Wholphin's deep link and Android TV Remote's launch-while-booting
  are unverified on a device; Firefox tabs are not read (only its cover URL); a browser playing two tabs with the same title
  picks the most recent.
- **TV session** ("playing on TV", after a successful Send to TV): `TvSession.qml` (singleton: session, polling, controls,
  IPC `tvsession status|control <what>|disconnect|stop|poll|log`, tv-session.json next to tv.json, `QS_TVSESSION_FILE`,
  `QS_TVSESSION_TIMES` poll,off,away,hold ms) + `TvSource.qml` (a MediaSource, kind `tv`, key `tv`: first in `MediaSources`
  active / current / list while it lasts; local players stay in the switcher). Logic in `launcher/js/TvSession.js` (node
  tests `tvsession.test.js`): roles of the TV's entities (power + foreground app = remote.* `current_activity`, else a
  media_player `app_id`; metadata = Cast while its session is our app (`castActive`: playing / paused + the app's cast id;
  never Cast's `AndroidNativeApp`, a native app Cast only mirrors: HA accepts media commands to it and the TV ignores them),
  else the Android TV Remote / ADB media_player), `route` per control (Cast services while castActive and Cast's
  `supported_features` has that control (e.g. no PREVIOUS / NEXT on Cast: keys), else Android key codes on the remote.* via
  `remote.send_command` (MEDIA_PLAY_PAUSE, MEDIA_PREVIOUS / NEXT, MEDIA_REWIND / FAST_FORWARD, VOLUME_UP / DOWN / MUTE,
  Stop = BACK (MEDIA_STOP is accepted and ignored by native apps like Twitch; BACK leaves the player, a live stream may keep playing on its page), else ADB `input keyevent`, else the media_player's services where its features allow; `caps` = controls with
  a route). Every sent call is logged with its outcome: `tvsession: <what> -> <domain.service> [KEY] (<route>): ok` or
  `: HTTP <n> <HA's message>` (failure also rolls the optimistic state back), `tvsession: <what>: no route on this TV`. `view` (Cast title / position /
  volume where castActive, else what we sent + our optimistic play / pause; a control's expectation shows for 3 s, then the
  TV's state wins where it has one), `judge` (ends after 25 s off / unavailable / idle (a Cast send), or 20 s with another
  app in front; unread entities keep the timers). Polls every 5 s only while a session exists. Card: tv glyph art /
  chip (iconFont: `glyphBrand: false`), tv badge with the TV's name (`device`), transport prev / seek -10 s / play /
  seek +10 s / next / stop (stops the TV, ends) / disconnect (`linkOff`, detach; the TV keeps playing); volume = Cast's
  level slider, else `MediaVolumeSteps` (mute, down, up); lock card: play / pause only (`lockTransport: false`). Starts in
  `TvCast.finish` (not for the test / dry run), replaces an older one; the local player was paused there. Dry run logs
  controls. Caveats: verified against the mock only; Android TV Remote reports no play state (card = optimistic), the
  REWIND / FAST_FORWARD step is the TV app's own; the lock card in session mode was not checked visually.
- **TV auto-detect** (the same TV card for what the TV plays by itself: a remote, a phone's cast, its own app): `TvPrefs.autoDetect`
  (tv.json, default on; Settings > TV "Show TV playback"). The picked TV's entities (`tv.entities`, never hard-coded) are watched
  over HA's websocket (`HaWatch.qml`: `/api/websocket`, auth, `subscribe_entities` for those ids; HA pushes changes; backoff 2 s
  to 60 s; needs `qt6-websockets`, loaded by a Loader: missing module = REST reads every 10 s). `TvSession.card` = the sent
  session, else `Js.detect` (TvSession.js, tests): power entity on, a media_player (Cast / ADB) playing / paused / buffering,
  app in front not a home screen / screensaver (`HOME_APPS`, incl. Cast Backdrop), title or a known app name (`APP_NAMES`,
  HA's `app_name`) else nothing; a Cast session paused behind another app is skipped. Art = `entity_picture` (HA path + base),
  position extrapolated from `media_position_updated_at` (`TvSource.progress` -> MediaSeek, read-only). A gap while the TV
  stays on is held 3 s; off / standby / unavailable hides at once. Controls = `Js.control` on `Js.autoSession` (same routes:
  a native app such as Twitch / Wholphin = remote keys / ADB; volume steps, no Cast level slider), no disconnect; dry run applies. IPC `tvsession auto`; `QS_TVSESSION_TIMES` 5th / 6th =
  gap / REST poll ms. Nested-verified against a websocket HA mock (art / no art / paused / standby / home / unknown app /
  named app / switch off / with mpv, lock card, controls, reconnect) and a feature-checking mock (400 for unsupported services,
  AndroidNativeApp ignoring media commands). Caveats: key routes on a real TV unverified (the mock only logs them); an Android TV Remote-only TV never shows
  (no play state; needs Cast or ADB reporting); real HA's `subscribe_entities` diffs and the REST fallback are unverified.
- **Glass clocks: time, seconds, morph** (`ClockFace.qml`, used by LockClock and DeskClockView): text HH:mm[:ss] (12 h: h:mm[:ss]),
  `morphMs` = popup motion of `Motion.baseMs * 3` x the page's morph time (0 = plain swap), capped at 450 ms with seconds; `fitSize`
  shrinks the digits only if the row would not fit (lock: screen - 2 edgeGap; desktop: screen - 2 margins, posX/posY unchanged). Every
  character is its own GlassText; GlassShape keeps one field layer per mask and `flip` only swaps which one the optics read, so a tick
  re-renders just the changed glyph's mask + field (measured with `qt.scenegraph.time.renderer`: 3 layer renders per tick, 6 on a tens
  change, ~31 window frames for the 450 ms morph at the 60 Hz animation driver). Desktop clock with seconds, nested 2560x1440: shell
  ~1.1 % of a core + ~2.2 ms/s GPU (morph 0: ~0.4 % / ~0.8 ms/s); seconds off = idle as before (~0.2 %, ~0.05 ms/s).
- **Fork vs stock:** compositor glass (`Theme.glass`: solid_glass cards, per-surface profiles, group bar / borders, `GlassEdge`
  rim when absent) needs the fork; shell-drawn glass (`Theme.shellGlass`: `GlassShape` lettering, beads, lock slab, lenses) does not.
- **Shell glass** (all optics from Settings > Glass, `GlassTuneCtl.effective`): `GlassLens.qml` = the shared lens (`shaders/sliderlens.frag`,
  refracts the shell's own card, same on stock), only alive while `amount` > 0 (Slider handle while dragged, Toggle knob while pressed /
  sliding after a click, OSD level while it changes; `qs ipc call osd level volume|brightness <0-100>` shows the pill for tests, `volume -1` = muted).
  Toggle's knob slide runs on the popup move tokens. The lens retires in two steps (stop hiding the host + stop drawing, unload
  100 ms later): unloading the effect directly left one frame in which neither drew (the OSD content blinked). `GlassEdge.qml` (inside every `isGlassItem` card) = 1 px rim lit from `light_angle`, only
  without `Theme.glass`. Shell-only Glass keys (`shell: true` in `GlassTuneCtl.opts`, group "Shell", e.g. `edge`) are saved in glass.json
  but never sent to Hyprland (managed.lua ignores unknown keys). Without solid_glass (stock) the Glass page is still listed and edits /
  saves the values for the shell only (`GlassTuneCtl.editable`). Caveat: a workspace-switch lens on the bar was tried and dropped (on a flush
  bar it refracts nothing but chip pixels: a grey squircle that blurs the active chip). `RimLight.qml` (PopupHost card, ModalMenu card,
  Settings) = the 1 px rim near the pointer catches a radial light while hovered (one odd-even ring Shape, no layers; Glass > Shell
  "Pointer rim", key `pointer_rim`, 0 = off).
- **Per-surface glass** (Look & feel > Glass > Customise… > Surfaces, choice Uniform / Differentiated / Custom; fork builds whose `decoration:blur:solid_glass:per_surface` exists, probed
  as `Theme.glassPerSurface`; group bar / border options probed separately: `glassGroupbarOpt`, `glassBorderOpt`): a profile per
  surface = overrides of `depth refraction aberration specular_intensity frost clarity darkening`, unset = the global value; no
  profile = today's look. Surfaces: bar `qs-bar`, popups `qs-popup`, launcher `qs-launcher`, OSD `qs-osd`, notifications
  `qs-toast` (named layer rules `qs-glass-<id>`, `glass = "key:value ..."`), group bar (`group:groupbar:solid_glass`), window
  borders (`decoration:blur:solid_glass:border`: off / "on" / overrides; drawn only with border size > 0). Stored in glass.json
  `"surfaces"` (both modes) through `GlassTuneCtl.surfaces` (one writer); `GlassSurfaces.qml` = logic + live apply
  (`hyprctl eval "glass_surfaces_apply({...})"`, throttled), `managed.lua` `M.apply_surfaces` composes the strings at load,
  reload and from that eval (`M.read_surfaces` / `M.split_surfaces`: strip "surfaces" before parsing the mode sets). UI:
  `GlassSurfacesSection` > `GlassSurfaceProfile` (FoldSection) > `GlassOptRow` (also the page's global rows); preset
  "Differentiated" in `GlassSurfaces.presets`; IPC `qs ipc call glasssurfaces set|unset|reset|preset|border|dump` (exists once
  the Glass page was opened). Stock / old fork: nothing is sent (an unknown rule field is a config error there), the section
  is disabled with a note. Add a surface: `GlassSurfaces.surfaces` + `managed.lua` `M.SURFACE_LAYERS` / `M.SURFACE_IDS`.
  Caveats: re-registering a named rule appends its effect (last wins; Lua only re-sends changed strings, a reload clears
  them); the tray menu (xdg popup of the bar) cannot get a profile (the fork resolves the `glass` rule for layer surfaces
  and windows, not popups; from the source); Settings (a window) has none yet (would be a window rule); the shell's own
  lenses (GlassLens, glass lettering) keep the global values.
- **Blur variants** (Settings > Look & feel > Blur, `BlurSection.qml` > `BlurOptRow` (slider / switch / `ArgbRow` colour by kind); engine `BlurTuneCtl.qml`,
  `qs ipc call blurtune variant|set|get|reset|dump`, exists once the page was opened): picks any `decoration:blur:variant` of Hyprland v0.57
  (kawase, frost, ripple, drops, water, fluid_jar, prism, heat_shimmer, acrylic, aurora, haze) plus the fork's solid_glass (tuned in Glass > Customise),
  and tunes that variant's options + the shared ones (size, passes, noise, contrast, ..., popups; fold). One table (`BlurTuneCtl.variants` / `.opts`,
  from ConfigValues.cpp) drives the UI; a new variant/option = a table entry there + `managed.lua` `M.BLUR_VARIANTS` / `M.BLUR_OPTS` (same ranges). Probe:
  one batch `getoption` fills `present`; variants / options the running Hyprland lacks are hidden and never sent. Stored in glass.json `"blur"` (flat,
  keys = option path under `decoration:blur:` with ":", bools 0/1, colours AARRGGBB, shared by both colour modes; written by `GlassTuneCtl.setBlur`, split
  off before the glass parse by `M.split_blur`); `managed.lua` `M.apply_blur` applies it at load and on `M.apply`, each key guarded by `hl.get_config`.
  `Theme.glass` stays solid_glass only: any other variant gets the plain translucent fills (as stock), the group bar colours follow (`blur_variant_changed`).
  Caveats: reset writes Hyprland's built-in default (may differ from settings.lua); GTK/theme.py fills (`hypr_solid_glass`) follow at the next theme
  apply, not at the variant change; acrylic / aurora / fluid_jar colours are AARRGGBB like solid_glass tint.
  Stock: the page runs on `GlassTuneCtl.reachable` (hyprctl answers), not `ready` (= has solid_glass); stock 0.57 lists the 11 variants, 0.56 only Kawase (no
  `decoration:blur:variant`, the choice is saved but never sent). Nested stock check: a `hyprctl configerrors` taken at startup is empty, run `hyprctl reload` first.
- **Motion language** (`Motion.qml`, shell section; `Theme.popup*` are the same tokens): `Motion.ms(base)` = base / popup speed, 16 ms
  floor, 0 when style "none" (`Motion.reduced`); `pressMs` 80 / `hoverMs` 120 / `moveMs` 200 / `exitMs` 150 / `emphasisMs` 300 at 1x;
  `easeEnter`/`easeMove`/`easeExit` follow the Curve setting, `easeHover` = OutCubic; `stagger(i, max)`. Never hard-code a duration
  (state pulses like `busyPulseMs` excepted); overshoot only on press release and a toast landing; no SpringAnimation (no duration:
  cannot follow speed / off). Parts: `PressFeedback` (sink by ~2 px + overshoot release; Btn, Tile, ListRow, Chip, Settings nav;
  HoverGlow brightens under the pointer while pressed), `GlideHighlight` (one gliding selection marker: launcher rows / actions,
  Settings sidebar, `Segmented`; the selected item then draws no fill, `Btn.activeFill: false`), `Reveal` (fade + rise of content
  swapped in place: Settings page, launcher section / action panel, tray submenu), `OpenMotion` (open / close `t` of a small surface:
  OSD; unmaps after the close, glass tail via `glassScaleAt`, close forced after exitMs + 400 if frames stall; stock = unmap at
  once, the blur is the whole window), `FoldBox` + `Chevron` (DropSelect, DevicePicker, BtProfilePicker). Fade colours from
  `Theme.alpha(sameColour, 0)`, not "transparent" (lerps through black). Caveat: the tray menu (xdg popup, compositor blurs the
  whole surface) keeps no open / close motion of its own: a fading card would leave an empty blurred box.
- **Wallpaper engine** (backend `engine`; config/theme/README.md "Wallpaper engine" is authoritative): `engine.qml` is its own
  Quickshell instance (`quickshell -p ~/.config/quickshell/engine.qml`, kept alive by `hypr/scripts/start-wallpaper-engine.sh`,
  pid in `$XDG_RUNTIME_DIR/wallpaper-engine/pid`, its log `engine.log` there; at login it waits up to 60 s for Hyprland's
  `hyprland.lock` + Wayland socket, which appear after autostart runs) with `EngineWindow` / `EngineVideo` / `EngineVideoSlot`; `Wallpaper.engine`
  turns the main shell's `WallpaperLayer` and `DeskClock` off and `Lock.qml` talks to it over `bin/engine-ipc`. It does NOT
  hot-reload (`settings.watchFiles: false`): after editing a component it uses (WallpaperView, DeskClockView, Glass*, ...)
  run `theme.py wallpaper-engine restart` (never kill it by name). Tests: nested only, `QS_ENGINE_ALWAYS` / `QS_ENGINE_PLAYERS`
  / `QS_ENGINE_BENCH` / `QS_ENGINE_DEBUG`; `bin/engine-bench` = the user's real-monitor comparison with mpvpaper.
- **Wallpaper layer** (`Wallpaper.qml` singleton = per-monitor `entryFor/pathFor(screen)` from theme.py's `out/wallpaper.json`, FileView,
  `qs ipc call wallpaper reload|status`, `QS_WALLPAPER_FILE`; `WallpaperLayer.qml` = one Background-layer window per screen, namespace
  `qs-wallpaper`, no input / exclusive zone, empty blur region, `no_anim` layer rule in `rules.lua`, maps with its first decoded image;
  `WallpaperView.qml` = two `WallpaperImage` slots, latest wins, cross-fade `Motion.emphasisMs`, failed / `pending` keeps the old one;
  `WallpaperImage.qml` = hyprpaper fit modes, decoded at PHYSICAL px = logical x Hyprland scale (Qt does not apply a fractional DPR
  to `sourceSize`: decoding at logical size blurred a 1.25 monitor), at the file's own size when smaller). Drawn only with the
  `quickshell` backend and once theme.py has written `out/wallpaper.json` (first render / apply). `LockWallpapers.stillFor` delegates to it (lock, desktop clock, bar contrast, Settings thumbnails);
  `pathFor` keeps the still the layer shows while an entry is `pending`, so no consumer loads a missing file. Regression
  (nested session only): `bin/tests/wallpaper-consumers.sh <shell pid> <imgA> <imgB> [video]`.
  Nested-verified: pixel-exact 1:1 at 1.25 and rotated, crop aligned with hyprpaper, hot-plug, rapid switching, light / dark, stock +
  fork, motion off = instant, idle 0 % CPU, video (mpvpaper, bottom layer) above it. Caveats: WebP needs `qt6-imageformats`; a shell
  restart shows Hyprland's background colour for ~350 ms (process start + decode); a portrait monitor decodes a landscape image at
  cover size (the cropped part too).
- **Primary monitor** (`Monitors.qml`, singleton): `Monitors.ordered` (primary first, then by x, y, name), `.primary` / `.primaryName` / `.primaryKey`, `isPrimary(screen)`, `title(screen)`; new code uses these
  instead of indexing `Quickshell.screens` wherever order or "the first monitor" matters (Settings window default, Osd / Toasts default target, `Popups.focusedScreen` fallback, launcher default, Settings monitor choosers,
  wallpaper-theme source default). Per-screen windows that just iterate all screens stay on `Quickshell.screens`. Choice = `quickshell/monitors.json` next to appearance.json
  (`QS_MONITORS_FILE`; `{"version":1,"primary":"<Appearance.monitorKey>"}`; the shell is the only writer; `qs ipc call monitors get|set <connector>|clear`), set in Settings > Monitors (`MonitorPicker`
  thumbnails by real position; `PrimaryTag` marks the primary in every monitor list). No choice or the monitor is gone = automatic: highest refresh rate (Hyprland IPC), most pixels, connector name; the
  saved choice is kept and applies again when the monitor returns. `theme.py` (`shell_primary_key`) uses the same file / rule when the wallpaper `primary` is unset. Caveat: Hyprland's `monitors.primary` Lua table
  is not readable from the shell; a nested session shows every output at 60 Hz, so the refresh-rate rule was only checked by reading the code.
  **Settings > Monitors** (`SettingsMonitors.qml`, page id `monitors`): `MonitorPicker` = the MAP and selector (every monitor at real relative
  size / position, uniformly scaled to the width and <= 240 px tall, >= `controlGap` between tiles; each tile = its wallpaper still, cover crop,
  bottom scrim with connector + Hz and a Primary chip in `Theme.barInkLight` ink; accent outline = selected; click selects, double click / Enter
  makes primary, arrows move), then `ChoiceRow` Primary Auto | Manual (Auto = `clearPrimary`, Manual pins the selected one), then ONE `MonitorCard`
  for the selected monitor (name, connector, mode / scale `Pill`s from `Monitors.modeText` / `scaleText`, `PrimaryTag` or "Set as primary") with
  three `LabelSwitch` tiles writing the features' own stores: Bar = `BarConfig.set(s, "enabled")` (linked group together, last bar locked), Lock
  clock = `LockPrefs.setClockOn` (lock glyph), Desktop clock = `DeskClockPrefs.shownOn` / `setShownOn` (desktop glyph, never locked). The
  selection is the shared `Monitors.selected`. Badges re-read Hyprland (`refreshMonitors`) on open and on any geometry change. It is the place for these per-monitor
  switches together (the Bar / Lock screen / Desktop clock pages carry the same switch on their monitor strip). objectNames `monitor-pick-<conn>`, `monitor-card-<conn>`,
  `mon-bar|mon-lockclock|mon-deskclock-<conn>`, `mon-primary-<conn>`, `primary-auto|primary-manual`.
  **Monitor section** (`MonitorSection.qml` + `MonitorChip.qml` + `MonitorStateCell` (the eye / eye-slash cell, also in `LabelSwitch`) / `MonitorLink` (the seam bridge) / `MonitorThumb` / `MonitorAction`): the ONE monitor selector + per-monitor
  switch of Settings, first row of Wallpaper / Bar / Lock screen / Desktop clock (and the Shape smart gaps row); anatomy, options, keyboard and
  how to add a per-monitor page: DESIGN.md "Monitor section". Selection = the shared `Monitors.selected` (reset to the primary on open); switches call
  the features' single setters (`BarConfig.set(s,"enabled")`, `LockPrefs.setClockOn` / `setAllClock`, `DeskClockPrefs.setShownOn` / `setAllShown`,
  `Appearance.setSmartFor` / `setSmartAll`). objectNames `monitor-chip-<conn>` (+ `-switch`), `<strip objectName>-all`, `monitor-link-<i>`,
  `btn-bar-copy-<conn>`, `btn-wp-follow|palette`; test hook `qs ipc call monitors select <connector>|selected`. Wallpaper page: palette glyph = palette source (wallpapers.json `primary`, else the shell primary
  as theme.py), strip actions Follow primary (`theme.py clear`) and Use for palette (`theme.py primary`). Nested test arrangements: `hyprctl eval 'hl.monitor({output="TEST2", mode="1600x900@60",
  position="0x900", transform=1, scale=1.25})'` on the nested instance (a wayland output takes the mode until its host window is resized again).
- **Desktop clock** (opt-in, Settings > Desktop clock: Size presets, 3x3 position grid, sliders under Customise…; `DeskClockPrefs` -> deskclock.json, `QS_DESKCLOCK_FILE`, `qs ipc call deskclock
  get|set|unset|reset|hideOn|showOn|all true|false`). Which monitors show it = ONE rule, `launcher/js/MonitorShown.js` (node tests; shared with the lock clock):
  `enabled && !hidden[key]` on disk (old readers unchanged), read through `DeskClockPrefs.shownOn` by the shell, the engine and Settings, written
  only through `setShownOn` / `setAllShown` (one commit of both keys): on while off everywhere = that monitor only (other connected ones hidden),
  off on the last connected one = `enabled` false (`hidden` keeps where it was). Caveat: a monitor first plugged in while it is on shows it
  (`hidden` is an opt-out map). Settings > Desktop clock on / off = its monitor strip (switch per chip + All, primary first; objectNames
  `monitor-chip-<conn>-switch`, `deskclock-monitors-all`); the preview / rows below follow the strip's monitor and dim with an eye-slash "Off" while it shows no clock.
  `DeskClock.qml` = one bottom-layer window per shown monitor (`qs-deskclock`, empty blur region,
  clock area only; `rules.lua` layer rule `order = -1` keeps it above mpvpaper, which is on the bottom layer too), `DeskClockView.qml` =
  GlassText per character refracting what the desktop shows: the still / image (`LockWallpapers.stillFor`, cover crop like hyprpaper) or,
  for a play-once video wallpaper, `DeskClockVideo.qml` = the same baked clip in QtMultimedia following the desktop player: parked on the
  held frame (paused, no decode), the station file write (burst start, winddown.lua) plays the same burst from the same frame, a timer
  re-aimed by each position report pauses at the burst end (measured in the nested session against mpv time-pos: within ~1 frame during
  the burst, end within 0-2 frames; ~4 % CPU of one core while a burst plays, 0 at rest). Nothing is drawn behind the lettering.
  Looping video wallpaper (theme.py mode "loop", mpvpaper `loop-file=inf`): `bin/lock-video --desk <conn>` -> `{"mode":"loop",
  socket, pid, file}` (`burst` = the play-once record + mode, `still` otherwise; without `--desk` the lock's output is unchanged, so
  the lock keeps the still) and DeskClockVideo loads `DeskClockLoop.qml`: the same clip looping in QtMultimedia (VA-API), synced over
  the player's mpv socket (observe pause/path/duration/fps, `time-pos` every 2.5 s and after each wrap). Within half a frame: nothing;
  <=120 ms: playbackRate +-3 % or a hold (pause exactly the time it is early); beyond: a CUE = paused seek 1 s ahead, play when mpv
  gets there (a seek while playing stalls 0.35-1.4 s and lands 0-0.45 s late at random). Wrap: the copy holds its last frame as long
  as mpv's loop seek (~30-50 ms, learned). Decodes only while shown and not fullscreen-covered / DPMS off (monitors re-read every 3 s:
  no event) / mpv paused or not advancing; locked = hidden = paused. Socket retry 6x (theme.py writes the state file before mpv opens
  its socket); the source is set only while the socket answers (a broken file the player rejects is not looped: the FFmpeg backend
  spins and floods stderr on one). Nested, 2560x1440, frame-matched screenshots vs the clip: 60 fps clip 37/45 same frame, rest +-1;
  30 fps -1..+1, across 3 wraps; resume after pause/cover/DPMS within ~1 frame after 1-2 s. Cost: +~3 % of one core per copy (shell
  6.0 % vs 0.1-0.2 % for two copies), mpvpaper unchanged, GPU busy within noise. `QS_DESKCLOCK_SYNC_LOG=1` logs every sample.
  `DeskClockPreview` = 16:9 Settings preview (still only). Shell-drawn glass (`Theme.shellGlass`): the same on stock (nested fork vs
  stock: lock clock 63 dB, portrait clock identical). Backdrop = `stage` (the layer's two-slot `WallpaperView`,
  the video copy drawn over it, a hand-over snapshot) rendered only into `stageTex` (hideSource SES; a `visible: false`
  layer missed updates: stale mid-fade frames, jumps). Every switch fades with the desktop: image <-> image by the view
  itself (pick during a fade waits for its end), any change that swaps the picture (video <-> still, video -> video) by
  a snapshot armed on the wallpaper.json change, frozen at the swap, faded out (`Motion.emphasisMs`) once DeskClockVideo
  is not `busy`; motion off = cut. Nested frame sequences (`trans.py`-style: desktop + clock patches, 20-switch runs,
  images / loop / play-once mixed, 200 ms and 1.2-3 s spacing): no pops; clock 10 % / 90 % within ~1-3 frames of the
  desktop; loop video CPU 2.6 -> 2.8 %.
  Reveal = the lock clock's, shared: `GlassReveal` (timing, date fade) + `GlassGlyph` (one forming GlassText), used by LockClock and
  DeskClockView; the desktop clock forms on window creation (shell start, enabled, monitor added) and after an unlock (`Lock.unlocked`
  signal: the `locked` binding did not report the unlock), never on minute changes or bursts. Lock: the clock stays on screen and
  in the desktop snapshot; at the lock request `DeskClockView.grabClean` grabs its rect WITHOUT the clock (the backdrop it refracts;
  still / held video within ~0.5/255, a loop video ~2-3/255 at the rect edge: a frame or two apart) and `LockClockPatch` fades that
  over the snapshot once the lock is up (`Theme.popupMs(Motion.baseMs)`) and keeps it through the unlock ring. The grab must finish
  before the lock is up (the compositor stops the clock window's frames; a grab after the snapshot missed it under load = no patch
  = no ring). Once secure the clock windows are UNMAPPED: content opacity 0 under the lock was never presented while the clock
  redrew every frame (video), so the old clock flashed after the unlock. A clock covered by a window (6 px margin) / top or
  overlay layer (`bin/lock-clock-cover`, hyprctl JSON, run alongside the hold; it gets `DeskClockView.ink` = what the clock
  really paints: glyph box + 0.2 x pixelSize left/right, max(28 px, 0.06 x pixelSize) top/bottom, measured; NOT the layer window,
  whose GlassText pads are mostly empty; the clean rect is that same `ink` rect) or any clock while a video was held mid-burst is
  hidden BEFORE the snapshot instead (old snap; `Lock.snapHideS` 0.035 s). Hyprland's `no_screen_share` layer rule cannot exclude
  the clock from grim: it paints a black box. Nested: snapshot step ~38 ms (was ~55), lock -> secure ~135 ms. Caveat: the clock's first frame after an unlock comes ~0.3-0.4 s after the ring ends (nested measurement); starting the reveal
  earlier made the digits pop in half-formed. Wallpaper-aware glass (`adapt`, `adaptStrength`, Settings > Desktop clock):
  `bin/region-luma` samples the wallpaper under the clock box (16 columns, cover crop; a play-once video by its held frame,
  other videos still + clip average), each digit gets `airy` 0..1 (smoothstep of mean^(1/2.2) over 0.42-0.72 x strength) ->
  `glasstext.frag` `airy`: tint -> faint cool white, darkening / steep band / dark outline fade, brighter rim / highlights /
  body, stronger wider shadow; airy 0 = exactly the Settings > Glass look (the lock never sets it). Shader changes need a shell restart. `QS_DESKCLOCK_CLOCK` = test clock text
  (as `QS_LOCK_CLOCK`). GlassText morph caveat: its two mask texts are set, not bound to `text` (a binding changed both masks at once:
  no morph, the digit just switched), and a text change bumps `GlassShape.refresh` / `refresh2` so that mask's shape field re-renders.
  Desktop clock page: seconds, morph time ("Show morph" / a changed slider steps the preview a minute ahead and back); which
  monitors show it: its "Show" row or Settings > Monitors (same setter). Glyphs created after the reveal (character count changed) start formed.
- **Bar text contrast** (Settings > Bar > Text, shown for the Transparent look (= docked + transparent when flush; Floating / Docked / Transparent are the Look cards); bars.json per bar `contrast` auto|dark|light|off, `contrastSens` 0..100, `hoverFill` 0..100): while
  the bar has no backdrop (flush + "transparent when flush", `Bar.inkFlat`) its text sits on the wallpaper, so each section (left / centre / right)
  gets a `BarInk.qml` colour set, whatever the theme mode: dark text on a bright wallpaper, light on a dark one (`Theme.barInkDark/barInkLight` = the
  palette's hues clamped in lightness), chips are fully transparent at rest (no pill, no outline; contrast comes from the ink only), the hovered one gets a soft wash (grey-blue 0.26 x `hoverFill` behind dark text, white 0.32 x behind light text; default 35 % = ~9 / ~11 %), active
  chips keep their accent fill; with a backdrop (glass look unchanged) the palette as before (`Theme.inkOn`, theme.py `wall_ink`). The section Rows in `Bar.qml` hand it down as `barInk`; `Chip` finds it, `BarIcon` /
  `BarLabel` read `ink` of their chip (`ink.accent`, never `bar.ink`). Sampling = `BarContrast.qml` + `bin/bar-luma` (ImageMagick; python3 stdlib):
  64 columns {mean, darkest/brightest tenth} of the wallpaper strip under the bar, cover-cropped like hyprpaper, from `LockWallpapers.stillFor` (a video
  wallpaper: the still plus 5 clip frames via ffmpeg, ~0.2-0.8 s once), cached per (wallpaper, video, screen size, bar px, edge); runs only when that key
  changes (wallpapers.json / palette.json, size, bar height), 0 cost at rest (idle CPU unchanged, measured). Verdict: contrast of each ink over the
  section's columns, 15 % hysteresis, `Switch point` biases it; colours / fill animate with `Theme.popupMs(1.5 x base)`. Test hooks: `qs ipc call
  barcontrast status|refresh`, `QS_BAR_LUMA`, `QS_WALLPAPERS_FILE`; helper tests `bin/tests/test_bar_luma.py`. New types: restart the shell. Caveats: a clip
  that swings from very dark to very bright cannot be read in both states (decided on the clip's mean/extremes); neighbouring sections on a wallpaper right at
  the threshold can pick different inks; popups / tray menus keep the theme.
- `Theme.edgeGap` is NOT the user's `edgeGap` key (that is `Theme.gapOut`).
- Appearance (`appearance.json`) is written only by `Appearance.qml`; Hyprland side is `hypr/hyprland/managed.lua` (loaded last via `pcall(require)`, no
  hand-written settings there). Adding keys: deploy theme files, then Hyprland files, then Quickshell files (every intermediate state must load). Animation base
  `A.BASE_MS` (`animations.lua`) must equal `Motion.baseMs`. Springs need `hl.animation{ spring = ... }` (`bezier =` only logs).
- Popups: never `keyboardFocus: Exclusive` on `PopupHost` (breaks click-away and one-click chip switching). Settings is a `FloatingWindow` (`qs-settings`, rule
  `qs-modal`, which must not set `rounding = 0`); layer surfaces cannot be dragged.
- Sliders: `wheel: false` inside scrolling Settings pages (a wheel once triggered a full theme apply). Shader edits need the `.qsb` rebuilt (see
  `shaders/sliderlens.frag` header) and a restart. Every slider has notches (default + extras, magnetic, double-click reset): DESIGN.md
  "Slider notches". Caveat: in the nested test Tab never moved focus inside Settings (arrow keys were checked with focus forced).
- Optional bundles: `OptionalPackages.qml`/`launcher/js/Bundles.js` read names from `packages/optional/*.txt` (`bundles.test.js` fails on drift). New bundle:
  txt + `Bundles.BUNDLES` + `MissingPackage` where used.
- QML gotchas: `pragma ComponentBehavior: Bound` + `required property` in delegates; `??` not `||` where `0`/`false` is valid; `Process` takes argv arrays,
  never user data in `sh -c`; no endless shell loops in a `Process` (poll with `Timer` + `FileView.reload()`); poll only while visible; no `console.log` of
  notification content or HA host; never bind `visible` to `visibleChildren`; `clip: true` ignores rounded shape; avoid binding loops from child `x`/`width`.
- VPN switching goes through `bin/vpn-switch` (exclusive vs coexist mode); Tailscale needs `tailscale set --operator=$USER` once.
- Home Assistant (`HA_URL`/`HA_TOKEN` in `config/hypr/.secrets`): test with `QS_HA_*` mocks, never service calls against the real HA
  (Send to TV included: `QS_HA_SECRETS` at a mock, or Dry run).
  Optimistic layer (`HomeAssistant.qml`): `call()` creates a `pend[id]` record (expected state/attrs, `predict()`) merged over `serverById` into
  `byId`, which every consumer reads; `reconcile()` ignores states from requests started before the call finished, keeps the prediction for
  `hold` ms (2 s, vacuum 5 s), then the server wins; error/6 s timeout = `rollback()` + `actionError`; after a reply a single `GET /api/states/<id>`
  replaces the full refresh; the poll timer skips while `touch()`ed or records pend. Consumers must read `byId`, never `serverById`.
  Not predicted: stop_cover, number/select helpers, climate turn_on. Mock with latency/failures: any stateful HA mock (reply latency, delayed apply). `bin/ai-usage` uses an
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

- `config/shell/zshrc`: `eval "$(zoxide init zsh)"` stays the LAST line. zsh is the login shell (`install.sh --chsh` sets it); `~/.zprofile` (unmanaged) starts the TTY1 session supervisor. No bashrc is kept; agents still run bash.
- `config/url-router/bin/url-router` is the default http(s) handler (docs in its header, template `config.example`); Brave's "make default" resets the handler.
  Links sent to the fallback browser focus its plain window (class `Brave-browser`, never `--app` windows; waits up to 10 s for a cold start) via `hl.dsp.focus`; `focus_browser = no` opts out, Hyprland only (elsewhere it execs the browser as before). Web app links are not focused. Real focus is only unit-tested (fake hyprctl), not tried live.

## macOS

Linked only by `./install-mac.sh` (symlinks, `--dry-run`, backups `*.bak.<timestamp>`). The theme engine never runs there (`theme.py` exits 0 on darwin;
`bin/theme-seed` copies `default/` into `out/`). Brew packages are not listed in the repo; Oh My Zsh is a git clone.
- Ghostty: shared `config/ghostty/config` + Mac overrides `macos.conf`. kitty: `${KITTY_OS}.conf` include.
- WM = own AeroSpace fork (`crossatko/AeroSpace`; build/sign/install in its README), config `config/aerospace/aerospace.toml`. Accessibility survives rebuilds
  only while the signing identity `aerospace-codesign-certificate` stays in the login keychain: do not delete it.
  Magic Mouse 2-finger workspace swipe (`magic-mouse-swipe` in `[gestures]`) needs the fork build and macOS Mouse > "Swipe between full-screen apps" off.
- `config/karabiner/karabiner.json` is GENERATED: edit the table in `generate.py`, run `python3 -I config/karabiner/generate.py` (`--aerospace` prints the
  matching bindings).
- SwiftBar plugin `config/swiftbar/ai-usage.10m.py` reads the Claude token from the Keychain. Set `user.name`/`user.email` on the Mac (else the hostname lands
  in commits).
- `wl-copy` for zellij is a host-local symlink to `pbcopy` (not in the repo).

## Open items

- Workstation: no glass on stock Hyprland; `qt_style = "kvantum"` needs `kvantum` there; AV1 wallpaper videos wait for the HEVC copy.

