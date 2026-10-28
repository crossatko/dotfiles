# theme — one place for every color

```
theme.toml ─┐ (tracked defaults)
theme.local.toml ─┤ (this machine: wallpaper, local settings; git-ignored)
wallpaper ──┼─> theme.py ─> out/palette.{json,lua} + one file per app (templates/)
overrides ──┘                      │   (out/ is git-ignored; default/ is the committed fallback)
                                   └─> kitty ghostty alacritty zellij hyprland
                                       hyprlock hyprtoolkit hyprpaper nvim quickshell
```

| do this | to |
|---|---|
| `SUPER+T` | open quickshell Settings on the Wallpaper & theme page (`qs ipc call picker toggle`; again = close); click a wallpaper (or arrows + Enter) to apply it everywhere |
| `theme.py apply [image]` | show a wallpaper at once, then (background worker) palette, render, reload apps; `--wait` runs the worker in the foreground |
| `theme.py analyze` | fill the analysis cache for the whole wallpaper library (lowest priority; Settings and login run it) |
| `theme.py build-helper` | build `theme-blobs` (the native standout pass, `blobs/`, Rust; install.sh does it) |
| `theme.py render` | re-render after editing `theme.toml`, `theme.local.toml` or a template (no re-analysis) |
| `theme.py default` | (committer) regenerate the tracked default theme in `default/` from `default/wallpaper.jpg` and `theme.toml` |
| `bin/theme-seed` (`theme.py seed`) | fill a missing `out/` from `default/` (done by install.sh, the git hooks, theme.py) |
| `theme.py mode [get\|dark\|light\|toggle]` | switch the light / dark mode (also: Settings > Look & feel > Colour): saves it, re-renders from the cached wallpaper analysis and reloads every app, leaves hyprpaper running |
| `theme.py accent [get\|standout\|dominant]` | where the accent comes from (also: Settings > Look & feel > Colour > Accent): saves it (`~/.local/state/theme/accent`, default `[settings] accent_pick`, else `standout`), re-renders from the cached analysis like `mode` |
| `theme.py show` | print the resolved palette (current mode) |
| `python3 -I selftest.py` | run the extractor against 20 nasty synthetic wallpapers, the cache, `theme-blobs` vs Python, a sandboxed two-click switch |

## Editing
* **Pin a color**: `[overrides]` in `theme.toml` (e.g. `accent = "#c0392b"`; for this machine only: in `theme.local.toml`), then `render`.
* **Tone down / punch up terminal colors**: `ansi_saturation`, `ansi_lightness`.
* **Picker folders**: `wallpaper_dirs` (images), `video_dirs` (video wallpapers, default `~/Videos/wallpapers`).
* **Layout defaults** (`[settings]`, Quickshell only): `rounding` (default corner radius, px), `gap` (window gap, px),
  `border_size`, `bar_floating` (false = docked bar), `smart_gaps` (lone window: no gaps/border/rounding),
  plus `bar_border` and `bar_opacity`. They are static (the wallpaper only drives colors) and are written
  to `out/palette.json` as real booleans/numbers (`out/palette.lua` carries `rounding` and the active mode's `bar_opacity` / `card_fill` / `plain_fill_min`, for the Hyprland group bar).
  The old `bar_gap` / `bar_radius` keys are gone: the bar margin and radius are derived from `gap` /
  `rounding` when `bar_floating` is on. Hyprland does not read these: its own values are hand-written in
  `hypr/hyprland/` (theme.lua, settings.lua), so keep the two in sync if you change a default.
* **User overrides**: Settings > Look & feel > Shape (presets, sliders under Customise…) writes `~/.local/state/quickshell/appearance.json`
  (missing key = use the default). Quickshell: appearance.json > `theme.toml` > built-in fallbacks.
  Hyprland: `hypr/hyprland/managed.lua` applies only the keys set in appearance.json on top of the
  hand-written config. `theme.py` never reads or writes that file, so the overrides survive wallpaper
  applies and `hyprctl reload`.
* **Add an app**: drop a file in `templates/` using `{{key}}`, `{{key.bare}}` (no `#`),
  `{{key.rgb}}` (`r, g, b`), `{{key.argb}}` (`0xffRRGGBB`), or `{{font}}`/`{{wallpaper}}`.
  It renders to `out/<same name>`; point the app at it (include/import/symlink).
  Palette keys: `theme.py show`.
* **Per machine, nothing tracked changes on a switch.** Tracked: `theme.toml` (settings; `wallpaper` = the default) and
  `default/` (a generated neutral wallpaper + its outputs, `theme.py default`; paths written `~/...`). Git-ignored:
  `theme.local.toml` (this machine's `wallpaper`, written by `apply` / the picker; optional local `[settings]`,
  `[overrides]`, `[vars]` `tv_wallpaper` and `static_blocks` = this machine's hyprpaper per-monitor blocks, merged over
  `theme.toml`) and `out/` (what every app reads, incl. `out/host/`: `gtk3.css`, `gtk4.css`, `kvantum.kvconfig`,
  `brave-glass.css`, `vesktop-theme.css`, which depend on the running compositor; only `theme.py` links them).
* **Seeding:** `bin/theme-seed` (POSIX sh) copies `default/` into a missing `out/` (leading `~/` becomes `$HOME/`) and writes
  `out/.default`. install.sh, `theme.py` and the git hooks (`post-merge`, `post-rewrite`, `post-checkout` -> `theme-render`) call it, so a
  fresh clone and the Mac (the engine never runs there) have working files; while the marker exists `out/` follows changes
  of `default/`, the first `theme.py render/apply` deletes it and `out/` is then never touched by the seeder. A pull that
  changes `config/theme/` re-renders on Linux (`THEME_RENDER_SKIP=1` skips). On a machine with a `theme.local.toml` the default is never seeded: a missing / seeded `out/` (a rebase or merge replaying the untracking commit deletes it) is rendered from the selection by the hooks. Consumers that would fail hard have fallbacks
  (Hyprland `theme.lua` and nvim: `default/palette.lua`; ghostty `config-file = ?`).
* **Machines that still track the old `out/*` (one-off):** `theme-render` runs `theme.py adopt-legacy`, which reads a copy of the old `out/`, `theme.toml` and herdr config from `~/.local/state/theme/legacy/`
  (else the `ORIG_HEAD` blobs): the previous wallpaper goes into `theme.local.toml`, local `[settings]`/`[overrides]` edits become local overrides, then it renders. Git refuses to pull while the old
  tracked `out/*` has local edits: copy them to that folder first, then `git checkout -- config/theme config/herdr`.

## Light / dark mode
The chosen mode lives in `~/.local/state/theme/mode` (`dark` default; missing / unreadable = dark; `THEME_MODE` overrides it for one run, not for `theme.py mode`; `theme.py default` is always dark). `theme.py mode light|dark|toggle` writes it and runs an apply without re-extracting; every other `apply` / `render` uses the saved mode. Theme-writing commands (render / apply / mode / per-monitor wallpaper) take `~/.local/state/theme/apply.lock`, so a wallpaper apply and a mode switch run one after the other. `out/palette.json` carries `mode`, so the shell follows instantly.
* **Palette** (`build_palette(base, cfg, mode)`): same wallpaper analysis, mirrored. Light bg = pale low-chroma tint of the image's light side, fg = a soft deep tint of its dark side (not pure black), accent vivid then darkened only as far as contrast needs, ANSI darker and more saturated (`ansi_lightness_light`, `ansi_saturation_light`; also `light_bg_lightness`, `light_fg_lightness`), all forced to readable contrast, `muted` higher than in dark. The ramp keeps its meaning (bg -> bg_alt/surface/surface2/overlay -> fg); `bg_alt` is lighter than bg in light mode (views, like libadwaita), the others darker. ANSI black/white and bright_* swap sides. `[overrides_light]` pins colours for light mode only; `[overrides]` pins of neutral-ramp keys (bg, fg, greys) are ignored in light mode. `python3 -I selftest.py` checks both modes.
* **Per-mode template values** (`mode_extras`): libadwaita shade alphas, the Qt Light/Midlight/Dark roles. Everything else in `templates/` is palette-keyed and follows by itself.
* **Glass settings are per mode** (each tweakable, remembered, never leaking into the other mode):
  * theme.toml glass knobs (`GLASS_KEYS` in theme.py: `card_fill`, `plain_fill_min`, `bar_opacity`, `gtk_glass*`, `brave_glass_alpha`): dark = `[settings]`, light = `[settings_light]` only (missing keys: theme.py `LIGHT_GLASS_DEFAULTS`); `mode_cfg()` resolves them, `palette.json` carries the active mode's `card_fill` / `plain_fill_min` / `bar_opacity` for Quickshell (`Theme.cardFill` / `barFill`). Machine-local edits go into the same sections of `theme.local.toml`; apply with `theme.py render`.
  * Settings > Look & feel > Glass (presets Clear / Frosted / Smoked / Liquid, every solid_glass option under Customise…; `~/.local/state/quickshell/glass.json`): top-level keys = dark, a `"light"` object = light; the page edits the active mode's set and swaps sets on a mode switch (`GlassTuneCtl.qml`); `hypr/hyprland/managed.lua` applies the active set (mode read from palette.lua's bg luminance), unset keys = settings.lua's values, light tint / darkening default to the dark settings.lua glass mirrored. `tint_from_bg` (per mode, "Tint colour" toggle; light default on): tint colour = palette bg, alpha kept. theme.py splits an old single-set glass.json once (`migrate_glass_modes`): the existing values stay the dark set, light starts from a copy with the tint mirrored to a pale one and darkening off. A top-level `"surfaces"` object (per-surface profiles, shared by both modes; Look & feel > Glass > Customise… > Surfaces) is ignored by the mode sets and by the migration.
* **Bar on the wallpaper:** a bar without backdrop (Settings > Bar > Look "Transparent") draws its text on the wallpaper. In light mode `palette.json` also carries `dark` (the dark palette's text colours) and `wall_ink` (`wall_inks()`: per monitor connector and bar edge, which palette's fg reads better on the wallpaper strip under the bar); `Theme.inkOn()` is the palette used when Settings > Bar > Text contrast is Theme (the default Auto measures the wallpaper itself, in any mode: Quickshell `BarContrast`/`BarInk`), `Bar.qml` hands it down, `Chip` / `BarIcon` / `BarLabel` follow their chip's `ink`. Per-monitor wallpaper changes refresh `wall_ink` (`refresh_wall_ink`).
* **Apps:** freedesktop `color-scheme` (`prefer-dark` / `prefer-light`, gsettings -> Settings portal: running Chromium / Electron / libadwaita apps flip live), `gtk-application-prefer-dark-theme`, the GTK 3 theme `Wall` (stock light or dark stylesheet recoloured; GTK 4 imports `Adwaita.css` / `Adwaita-dark.css`), KDE `LookAndFeelPackage` (Breeze / Breeze Dark), Brave (`color_scheme2`, applied at its next start; the shim exports `GTK_THEME=Wall[-Glass]` with `:dark` only in dark mode), nvim (`background` from the palette). Autostart (`hypr/hyprland/autostart.lua`) sets `color-scheme` from the state file before the browsers start.
* **Kvantum:** colours with alpha are written as `#RRGGBBAA`, which is what Kvantum parses (`getFromRGBA`; stock themes use it).
* Known limits: GTK 4 / libadwaita windows already open keep their colours until reopened (the portal flip reaches apps that listen for it); Brave switches at its next start. `wall_ink` judges a video wallpaper by its still and assumes a 16:9 cover crop; dark mode does not use it (light text on a bright wallpaper stays as it was). The Glass sliders show their own built-in defaults (not settings.lua's) for keys the active mode's set does not contain.

## How the extractor picks colors
Background/foreground come from the darkest third / lightest quarter of the image,
clamped so the dark theme is dark with readable text (light mode: see above). The **accent is the most
chromatic region**, not the most common color, so art that is mostly greyscale with one
red streak (like drakengard.jpg) still gets its red. Greyscale images fall back to the
foreground as accent. Contrast is enforced: fg ≥ 9:1, accent ≥ 4.6:1, ANSI ≥ 4.5:1.

**Standout accent** (`accent_pick = "standout"`, the default; `standout_accent()` in theme.py, thresholds `SO_*`): small
but noticeable details (a red eclipse on a blue-grey sky, green eyes and red earrings, neon) win over the dominant
colour. OKLab, a 3 % border ignored (logos, watermarks); candidates have OKLCH chroma ≥ 0.06 and L 0.22-0.96 and form
same-hue blobs (4-connected, within ~26° of the seed). Two passes per frame:
* coarse, 320 px: blobs of 0.04 %-20 % of the frame (smaller = noise, bigger = the dominant colour);
* fine, 1280 px: ImageMagick keeps only pixels that are chromatic and differ from a 4 px blur (edges, small details),
  `theme-blobs` (or the Python reference) groups them; a blob needs ≥ 16 px (4x4 at 1280 wide), a compact box (filled ≥ 20 %, thinnest side ≥ 3 px), an
  isolated neighbourhood (≤ 35 % of the box around it pre-filtered: not noise, grain, foliage; frames over 50 % get no
  fine pass), and below 0.04 % chroma ≥ 0.10 with a local contrast ≥ 0.09.

Score = chroma² / 0.1 (the most intense spot beats a broad, moderately coloured area) × local contrast (OKLab distance
to the neighbourhood) × novelty (the share of the blob's colour the frame's mean colour cast does not explain, so a vivid
red on a dull peach scene counts) × a size ramp (full weight from 0.2 %) × a skin penalty (light orange with C ≤ 0.13). A video wallpaper is judged on its still plus
8 frames spread over the clip (parallel ffmpeg seeks, ~1 s, ~8 s for 4K AV1; cached per clip, precomputed): a hue (30° bins) must
show in half of them (flashes lose) and scores its mean over all frames. Hues within 40° of the dominant accent (unless ≥ 1.6× as
chromatic, C ≥ 0.15 and ≥ 15° away: red robot eyes on an orange-brown scene) and details darker than L 0.4 are skipped; the best remaining hue with score ≥ 0.004 is the accent, else the dominant
accent stays (monochrome, faint, same-hue). A second hue ≥ 50° away scoring ≥ 35 % of the winner becomes `accent2`
(else the dominant colour, else the ANSI blue/cyan as before); both are toned and contrast-checked like any accent.
`out/extracted.json` (`"v": 4`; an older cache is re-analysed once) holds `accent` (dominant), `standout`,
`standout_score`, `standout2` (`partial`: a video's still only, refined in the background), so switching the accent source is a render only. `"dominant"` reproduces the old output exactly.

## Instant switch (what a click in Settings > Wallpaper costs)
`apply` (also `link` / `primary` / `clear`) is split (theme.py "instant switch"):
* **Foreground** (`apply_fast`, ~10-20 ms in Python + ~45 ms interpreter start): saves the pick (`theme.local.toml` / `wallpapers.json`
  under the short `state.lock`, never `apply.lock`), re-renders `out/hyprpaper.conf` + `out/wallpaper.json` (the shell's wallpaper
  layer watches it: with the default backend that is the switch, see "Wallpaper backend"; with `hyprpaper` every output that shows
  something else is switched live, `hyprctl hyprpaper wallpaper <selector>,<image>,cover`, no restart) and starts / stops the video players. Nothing is decoded:
  a video's still and black-tail hold are only named (a clip whose hold is not cached is assumed to have none).
* **Worker** (`theme.py apply-bg`, detached, nice 10 / best-effort I/O 7, log `$XDG_RUNTIME_DIR/theme-apply/worker.log`): extracts
  missing stills (the hold scan runs in parallel; a wrong guess re-makes the entry and restarts its player), checks hyprpaper took the
  change (else restarts it), then for the primary: analysis (cache first), render (`palette.json` first, so the shell recolours
  before the apps), deploy, app reloads in parallel; apps whose files did not change are not reloaded (`write_atomic` skips identical
  content). A new video gets a quick palette from its still, refined once its frames are analysed, only when accent / accent2 move
  (OKLab ≥ 0.02). Quickshell cross-fades the palette (`Theme.paletteFadeMs`).
* **Latest wins:** each apply bumps `gen` in `$XDG_RUNTIME_DIR/theme-apply/status.json` (`{gen, state: working|done|failed, stage,
  pid}`, read by Settings: the palette glyph pulses while `working`) and SIGTERMs the previous worker, which dies with its
  ffmpeg / ImageMagick children unless it is inside render + reload (it finishes that first). Workers run one at a time and reconcile
  the whole state, so a superseded one leaves nothing undone. A failing worker (unreadable image) leaves the old palette (`failed`).
* **Cache:** `$XDG_CACHE_HOME/theme/analysis/` one JSON per file, keyed by path + size + mtime + `EXTRACT_VERSION` (bump = everything
  re-analysed; `analyze` prunes old versions): `img-*` (dominant colours + the image's / still's own blobs), `frames-*` (a video's 8
  frames). File probes (duration, codec, size, packet times) persist in `$XDG_CACHE_HOME/theme/video/probes.json`.
* **Precompute:** `theme.py analyze` (nice 19, idle I/O, 2 frames at a time, waits while a worker runs, one at a time) analyses every
  library image and video (frames + hold + probes, not the 4K stills); run after each worker, when Settings > Wallpaper scans the
  folders and 60 s after login (`start-hyprpaper.sh`).
* **theme-blobs** (`blobs/`, Rust, no dependencies; `theme.py build-helper`, install.sh): the standout blob pass natively, the same
  algorithm and float operations (CPython's compensated `sum()` and `math.hypot` / `dist` reproduced), so its results equal the Python
  `frame_blobs` bit for bit (selftest checks it, and both against each other on random input). Not built, stale (`BLOBS_VERSION`) or
  failing: the Python reference runs (same colours, slower). `THEME_BLOBS=<binary>|0`.
* **Profile:** `THEME_PROFILE=<file> theme.py apply ...` appends one JSON line per stage (`fast.*`, `worker.*`, `extract.*`,
  `analyze.*`: `{t, pid, stage, ms}`); `THEME_ANALYZE=0` keeps tests from starting the precompute.

Measured (sandbox with shims, 2 monitors, 16 cores; click = Settings' detached `python3 -I theme.py apply`; new = nothing cached,
cached = switching back or precomputed; "visible" = theme.py has issued the hyprpaper set / started the player):

| | before: visible | after: visible | after: palette.json | after: apps reloaded |
|---|---|---|---|---|
| image 4K / 6K, new | 1.0 s / 1.3 s | 55 ms | 0.35 s / 0.5 s | 0.75 s / 1.0 s |
| busy image (many details), new / cached | 1.9 s | 55 ms | 0.43 s / 0.13 s | 1.0 s / 0.7 s |
| video 4K h264 play-once, new / cached | 3.5 s / 2.7 s | 150 ms / 65 ms | 0.9 s, refined 1.7 s / 0.13 s | 2.0 s / 0.6 s |
| video 4K AV1 play-once, new / cached | 18.2 s / 11.8 s | 125 ms / 70 ms | 3.8 s, refined 11.6 s / 0.14 s | 12 s / 0.7 s |

Then hyprpaper shows the image ~45 ms after the set and mpvpaper its first frame 45-230 ms after start (nested Hyprland). Before =
`apply` did everything first (analysis 0.27-10 s, render, deploy, reloads incl. a 0.3 s sleep), then restarted hyprpaper and the
players. Library precompute: 73 files in 2.6 min wall, ~18 CPU-min at nice 19. `hyprctl reload` is a 150 ms shim (not measured live).

## Wallpaper backend (who draws the image)
`[settings] wallpaper_backend` (theme.toml; per machine in `theme.local.toml`; apply with `theme.py render`):
* **`quickshell`** (default): the shell draws each monitor's image, and the still under a video, on the background layer
  (`config/quickshell/Wallpaper.qml` + `WallpaperLayer.qml`, namespace `qs-wallpaper`) from `out/wallpaper.json` = the blocks of
  `out/hyprpaper.conf` as JSON (`write_wallpaper_json`: monitor rule, path, fit, the image's header size `w`/`h`, `pending` while a
  video's still is not extracted yet) + `backend`. Written in the click's foreground; the shell's file watch picks it up (no IPC poke
  needed: file write -> pixels 11-25 ms with motion off), decodes at the monitor's physical size off the UI thread and cross-fades
  (`Motion.emphasisMs`). theme.py never starts, restarts or waits for hyprpaper; a hyprpaper still answering on the instance socket
  (left from the old backend) is kept in step, never started. `scripts/start-hyprpaper.sh` starts it only for the `hyprpaper` backend.
  Until the shell is up (login, shell restart) Hyprland's background colour shows (nested: ~350 ms on a restart).
* **`hyprpaper`**: the old path (live set, worker listactive check + restart, players wait for it at login). Switching back:
  set it, `theme.py render`, start hyprpaper (`scripts/start-hyprpaper.sh` or a re-login); the shell then draws nothing.
* **`engine`**: the wallpaper engine (`config/quickshell/engine.qml`, its own Quickshell instance) draws images, videos and the
  desktop clock; theme.py writes the same files but no mpvpaper / hyprpaper. See "Wallpaper engine" below.
* hyprpaper stays in `packages/pacman.txt` as the optional fallback. WebP wallpapers in the shell need `qt6-imageformats`.

Measured in a nested Hyprland (fork and stock; 1600x900 @1.25 + 720x1280 portrait; 4K JPEG; click = detached `theme.py apply`):

| | hyprpaper | quickshell |
|---|---|---|
| click -> new image 10 % / 90 % | 90-215 / 175-280 ms (Hyprland's layer fade, the old image dims first) | 84-118 / 231-265 ms (300 ms OutCubic cross-fade); motion off: 81-92 ms |
| cover crop vs hyprpaper (PSNR) | - | 34-53 dB, aligned (resampling differs: Qt downsamples at decode, hyprpaper on the GPU); 1:1 images pixel-exact at 1.25 and rotated |
| memory, 4K image on 2 x 1440p | hyprpaper 132 MB RSS | shell +57-63 MB RSS |
| idle after the fade | - | 0 % CPU (one static texture) |

## Wallpaper engine (`wallpaper_backend = "engine"`)
A second, rarely restarted Quickshell instance owns everything under the windows: the wallpaper image, video wallpapers
(QtMultimedia instead of mpvpaper) and the desktop clock. The main shell then draws neither (`Wallpaper.engine`:
`WallpaperLayer` off, `DeskClock` off; `Lock` talks to the engine instead).
* **Files:** `config/quickshell/engine.qml` (root: player records, pause logic, workspace bursts, lock protocol, IPC),
  `EngineWindow.qml` (one background-layer window per monitor, namespace `qs-wallpaper`: `paper` = `WallpaperView` + `EngineVideo`,
  the clock = `DeskClockView` with `backdrop: paper`), `EngineVideo.qml` (two players, cross-fade, bursts, station),
  `EngineVideoSlot.qml` (one MediaPlayer + VideoOutput, stretch / park / hold), `bin/engine-ipc` (IPC client),
  `bin/engine-bench` (real-session benchmark + switch check), `hypr/scripts/start-wallpaper-engine.sh` (supervisor, autostart).
* **Isolation:** `quickshell -p ~/.config/quickshell/engine.qml` shares this directory's components but sets `settings.watchFiles:
  false`: editing the shell's QML hot-reloads the main shell only (nested: the engine's video kept playing through an edit of
  `DeskClockView.qml` + `Bar.qml`). The engine picks up QML changes only on `theme.py wallpaper-engine restart` (or IPC `reload`).
* **Players:** with this backend theme.py never starts mpvpaper / hyprpaper. `video_sync` writes the same per-connector state
  file as for mpvpaper but as a RECORD (`ep_start`: `"engine": true`, `pid` 0, `file` = the optimized / baked copy when it
  exists else the original, `bursts` (s, where each baked burst starts, then the file's end), `cyc`, `tag`, `station`, `stop`
  (unbaked play-once: play + wind x WIND_AVG or the black-tail hold)) and `engine_publish()` gathers them into
  `$XDG_RUNTIME_DIR/theme-video/engine/players.json`, which the engine watches (inotify; click -> first visible change
  84-121 ms nested, apply foreground included; an IPC poke would only be slower). Baking / optimizing run as before;
  a finished copy is a new record and the engine swaps itself (cross-fade, on the held frame or after the running burst).
* **Video:** loop = MediaPlayer loops (gapless in the decoder). Play-once = the same file looping too, with stretches:
  baked first play 0..bursts[0], burst i = bursts[i]..bursts[i+1] (winddown.lua's semantics; `cyc` after the last),
  unbaked 0..stop (a plain pause, no speed ramp). The backend reports the position every ~50 ms only, so frames are counted
  between reports and the stretch pauses on its exact last frame (the backend shows ONE more frame after `pause()`: it
  pauses on the second-to-last). A single-pass player at the file's end went EMPTY (EndOfMedia: the still showed
  through); looping avoids it. Nested, barcode clips: 60 fps held frames exact (179, 419, 539, 659, 839 = the frame before
  each burst start / the file's last frame), 30 fps exact 4 of 5 (one held a frame early); no black / background frame at
  bursts, the end or clip swaps.
  Workspace bursts: Quickshell.Hyprland `monitor.activeWorkspace` per monitor, compared by workspace NAME (Quickshell
  leaves the id at -1 for a workspace it first saw through a window: an id test missed every switch on the live
  session), special workspaces ignored, ignored while a burst plays (as replay.py); `video-replay.lua` returns early for
  this backend (it reads `out/wallpaper.json`). The unlock wakes it the same way: `lockRelease` (sent when the ring has
  revealed the desktop) starts one burst per play-once monitor (nested: with the unlock, < 30 ms); a burst the lock
  paused continues from the snapshot's frame instead (no second burst).
  A new clip loads in the hidden player (drawn at opacity 0.004: an undrawn VideoOutput gets no frames) and fades in over
  the old one / the still once it has a frame (`Motion.emphasisMs`); only during a fade do two clips decode.
* **Pause** (no decode, position kept): the lock (below), a fullscreen window on that monitor
  (`activeWorkspace.hasFullscreen`), DPMS off (`hyprctl monitors` every 3 s while a clip plays: no event), IPC `pause`.
* **Persistence:** the burst index in `theme-video/<conn>.station` (winddown.lua's format; bin/lock-video reads it), each
  clip's position in `$XDG_STATE_HOME/quickshell/wallpaper-engine.json` (burst start / end, pause, every 10 s while a loop
  plays) and `$XDG_RUNTIME_DIR/wallpaper-engine/positions.json` (every second; preferred at start): a restart parks /
  resumes there. **Crash:** the supervisor starts it again 0.1 s after it exits (Quickshell's own crash handler is off,
  `QS_DISABLE_CRASH_HANDLER=1`: it relaunched a crashed engine as a second, detached process next to the restarted one).
  Nested, SIGKILL: Hyprland's background showed for ~0.36 s, then the still, the clip ~0.8 s after the kill at the
  position it had (+0.3 s); SIGSEGV: the same after ~0.9 s of core dump. Quick repeated exits back off (2-30 s); the
  supervisor stops when the backend is no longer `engine`.
  **Hyprland instance:** Quickshell reads `HYPRLAND_INSTANCE_SIGNATURE` once; a stale one (an old shell's env after a
  session restart) means no workspace events. The supervisor passes the RUNNING instance's signature and Wayland socket on
  every (re)start (the caller's when alive, else the `$XDG_RUNTIME_DIR/hypr/*/hyprland.lock` whose pid is a live
  Hyprland; none = it exits), and the engine exits (-> restart) when its instance's lock / pid disappears (checked every
  30 s). `status` shows `hyprland: {signature, instanceAlive, events, lastEventAgoMs}` and per screen `workspace`,
  `wsChanges`, `wsBursts`, `unlockBursts`, `lastWsAgoMs`.
* **Clock:** `DeskClockView` with `backdrop` = the `paper` item of the same window: the glass samples the live wallpaper
  (a `ShaderEffectSource` of `paper` limited to the clock's area), so the old hidden copies (stage, `DeskClockVideo` /
  `DeskClockLoop` mpv-socket sync, hand-over snapshot) stay idle; every fade / burst under the clock is the same item the
  desktop shows. Check (IPC `debugGrab <prefix>`: the glass's texture and the same rect of `paper` in one grab pass): 45 dB
  during a burst, vs 15-16 dB between consecutive grabs = the same frame. Prefs, monitors, reveal, morph, seconds, adapt:
  unchanged (the engine has its own `DeskClockPrefs` reading the same JSON; FileView watches work across processes).
* **Lock** (`Lock.qml`, `engineMode`; every call through `bin/engine-ipc`, ~12 ms, 150 ms cap, exit 3 at once without an
  engine): `lockPrepare <gen> <dir>` before the snapshot (clips paused: the snapshot is the frame the desktop stays on;
  each clock's clean rect written to `<dir>/clean-<conn>-<gen>.png`, renamed when complete, "clean <conn>" once there) ->
  `lockCover "<conns>"` for a clock covered by a window (bin/lock-clock-cover, rects from the engine's
  `$XDG_RUNTIME_DIR/wallpaper-engine/clock.json`) -> `lockHide` once secure (the clock is never drawn under the lock, so the
  buffer Hyprland keeps has none) -> `lockRelease` after the unlock (clips continue, clocks form). A lock whose release never
  came (shell died) is released when `<dir>/held` disappears (checked every 2 s). Nested: lock-now -> secure 97-216 ms
  (was ~135), ring opens onto the clean rect, no old clock after the unlock (6 ms sampling), a burst paused mid-way continues
  from the snapshot's frame.
* **IPC** (`quickshell ipc --pid <pid> call engine ...`, or `bin/engine-ipc ...`, or `theme.py wallpaper-engine ...`):
  `status` (JSON per screen: still, video, mode, pos, playing, idx, held, fullscreen, dpmsOff, clock, ink), `reload`, `poke`,
  `pause`, `resume`, `replay <conn>`, `form`, `lockPrepare`, `lockCover`, `lockHide`, `lockRelease`, `debugGrab <prefix>`.
  `theme.py wallpaper-engine status | start | restart | stop | <ipc function>`. Test hooks: `QS_ENGINE_ALWAYS=1`,
  `QS_ENGINE_PLAYERS=<file>`, `QS_ENGINE_BENCH=<connector>` (overlay, no clock, writes nothing), `QS_ENGINE_DEBUG=1`
  (positions / frames of every stretch).
* **Adding something to the engine:** a per-monitor visual goes into `EngineWindow` (above `paper` if it should sample the
  wallpaper: `backdrop`-style, sample `paper` with a `ShaderEffectSource`; never a copy of the wallpaper), engine-wide
  state / IPC into `engine.qml`; reuse shell components by type (same directory). New types need a qmldir entry; the
  engine needs `theme.py wallpaper-engine restart` (no hot reload), the main shell a restart only if it uses them.

**Switch** (per machine): `wallpaper_backend = "engine"` in `theme.local.toml [settings]`, then `theme.py wallpaper-engine start`
(supervisor + engine; it shows nothing until the next step), `theme.py render` (wallpaper.json says "engine": the shell's layer
and desktop clock hand over to the engine), `theme.py video restart` (mpvpaper players stop, records are written). Check with
`theme.py wallpaper-engine status`; `config/quickshell/bin/engine-bench` compares both players on a monitor first.
At login `hyprland/autostart.lua` runs `start-wallpaper-engine.sh` (exits at once for the other backends).
**Rollback:** `wallpaper_backend = "quickshell"` (or remove the line), `theme.py render`, `theme.py video restart`
(mpvpaper starts again), `theme.py wallpaper-engine stop`.

Measured (nested Hyprland, 1259x677 + 900x1600 portrait @1.25, 2560x1440 HEVC 25 Mbit/s 60 fps loop, VA-API; per process):

| | mpvpaper | engine |
|---|---|---|
| CPU, 1 / 2 monitors playing | 2.9 % / 5.2 % (2 processes) | 3.8 % / 5.4 % |
| video decode (VCN) per stream / gfx | 13.9 % / 2.3 % | 14.0 % / 0.7 % |
| memory, 1 stream: RSS / private | 229 / 85 MB | 457-583 / 285-390 MB |
| memory, 2 streams: RSS / private | 2 x 215-229 / 2 x 85 MB | 787-807 / 620-640 MB, flat over 16 min |
| image only / paused (lock, fullscreen, DPMS) | - | 0 % CPU, 0 decode (RSS 336 MB image only) |
| clock with seconds (2 monitors) | (old clock: ~1.1 % per monitor) | +5.3 % CPU, nested Hyprland +2.7 % (full-window redraw per morph frame) |
| start -> first video frame | 45-230 ms | 520-555 ms (the still maps first) |

| main shell + players, clock on, loop video on both | shell 877 / 694 MB (its clock copies decode both clips AGAIN: 4 decodes) + 2 x 212 / 87 MB | shell 329 / 171 MB + engine ~800 / 620 MB (2 decodes) |

Caveats: the engine process itself costs more memory than mpvpaper (Qt's FFmpeg frame pools: ~+200 MB private per 1440p
stream, plus ~200 MB for a Qt Quick process), but the main shell drops its wallpaper layer and clock copies: with the clock on
the total is lower (private ~790 vs ~870 MB) and half the video decodes. A clock animation redraws the whole wallpaper
window (Qt Quick has no partial updates; the compositor recomposites the output): seconds + morph cost more than with the old
separate clock window. 10-bit originals without an optimized copy play without dithering (mpv dithers; the optimized copies
are 8-bit, made by ffmpeg, the same file for both players). DPMS pause, real 360 Hz pacing, HDR, real login / autostart: not
verified (nested outputs ignore DPMS; run `engine-bench` on the real monitor).
After the user's soak these become removable (keep them while `quickshell` / `hyprpaper` stay selectable): `mpvpaper`,
`theme/mpv/winddown.lua` + `replay.py`, `hypr/scripts/video-replay.lua`, `quickshell/bin/lock-desktop-video`,
`DeskClockVideo.qml` / `DeskClockLoop.qml` + `bin/lock-video --desk`, `WallpaperLayer.qml`, DeskClock's stage / hand-over
snapshot, `vp_start` / `vp_ipc` / `vp_stop` and the mpv options in theme.py.

## What follows the wallpaper, and how it reloads

| app | how it gets colors | live reload |
|---|---|---|
| kitty, ghostty | `include` / `config-file` of `out/` | yes (SIGUSR1 / SIGUSR2) |
| alacritty | `general.import` | yes (watches imports) |
| nvim | catppuccin fed from `out/palette.lua` | yes, every running instance (RPC `ThemeReload()`) |
| zellij | theme file `themes/wall.kdl` | yes (rewrite of config.kdl triggers its watcher) |
| herdr | `~/.config/herdr/config.toml` is generated (tracked `config/herdr/config.toml` + this machine's `[theme]` block; herdr has no include) | `herdr server reload-config` |
| hyprland, hyprlock, hyprtoolkit, hyprpaper | `dofile` / `source` / symlink | yes (`hyprctl reload`, hyprpaper restart with that backend); hyprlock reads its wallpaper path on each lock |
| desktop wallpaper (quickshell backend) | `out/wallpaper.json` (Wallpaper.qml) | instant, cross-fade |
| Omarchy apps (omacal, omamail, ...) | `out/omarchy/` is a complete Omarchy theme, linked as `~/.local/state/omarchy/current/theme` (+ `current/theme.name`); see below | their own file watch |
| quickshell bar + Settings | watches `out/palette.json` | instant |
| notifications | quickshell `Notifs.qml` server + toasts + notification center | instant, palette-driven |
| launcher / menus | quickshell `Launcher.qml` | instant, palette-driven |
| Qt / KDE apps (Dolphin, Ark, ...) | KDE platform theme (`QT_QPA_PLATFORMTHEME=kde` in `hyprland/env.lua`) reading `~/.config/kdeglobals`: color scheme `Wall`/`WallB` + accent, fonts, icons (`Wall-Adwaita-Qt`), widget style (`qt_style`: Kvantum `Wall`) | backgrounds, text and icons live; selection highlight on next window |
| GTK 3 apps, Brave dialogs | named theme `Wall` (`~/.local/share/themes/Wall`): GTK's stylesheet (dark or light, by mode) re-colored by `recolor_gtk_css`; Brave gets `GTK_THEME=Wall:dark` (`Wall` in light mode) from its shim | GTK 3 apps reload on theme change; Brave on restart |
| GTK 4 / libadwaita apps, nautilus | `~/.config/gtk-4.0/gtk.css` -> `out/host/gtk4.css` (= `out/gtk.css` + translucent backgrounds and a compositor blur request, `gtk_glass*` in theme.toml); `gtk-3.0` -> `out/host/gtk3.css` (= `out/gtk.css` + the same glass for client-side-decorated GTK3 windows only; Firefox and SSD windows stay opaque) | **after the app restarts** (see below) |
| Adwaita icons | generated hue-rotated copy `Wall-Adwaita` (see below) | new windows / apps that reload icons |
| Vesktop (Vencord) | `templates/vesktop-theme.css` -> `out/host/vesktop-theme.css` (Discord CSS variables remapped, glass via the `gtk_eff_*` alphas) -> copied atomically to `~/.config/vesktop/themes/wall.theme.css` when vesktop is installed (`vesktop = false` in `[settings]` skips) | Vencord watches `themes/` and re-applies live; first enabling: see Vesktop below |
| Brave | seed-color theme written into its Preferences by the `~/.local/bin/brave` launcher shim | at next start (Brave rewrites Preferences on exit, so it can't be edited while running) |
| Geary 46 (GTK3 + libhandy) | window chrome: Geary block in `templates/gtk3.css` (scoped to `window.geary-main-window`: accent-tint selection, unread = accent edge + accent sender, read dimmed, starred yellow, thread badges, in-app toast `box.app-notification` restyled like a Quickshell notification card); plain-text bodies: `out/geary-user-style.css` linked as `~/.config/geary/user-style.css` (`deploy()`, only when Geary is installed) | at next start |

* **GTK4/libadwaita cannot restyle an open window**: nothing re-reads the user CSS (tested
  with color-scheme / gtk-theme / accent-color / settings.ini changes). Open windows keep
  the old colors until reopened. Optional: `quit_on_apply = ["nautilus -q"]` in theme.toml.
* **Icons**: Adwaita 51's folder SVG has a hardcoded blue and no accent hook, and the
  `accent-color` setting had no effect here (the Settings portal is not served, because
  `~/.config/xdg-desktop-portal/portals.conf` only routes to hyprland). So `theme.py`
  writes `~/.local/share/icons/Wall-Adwaita{,B}`: Adwaita with its blue family rotated to
  the accent hue (other hues keep their meaning). It alternates between the two names so
  every apply is a real theme change. Turn off with `icons = false`.
* **Brave**: "Use GTK theme" can never follow generated colors (Chromium resolves GTK colors
  in its own context and ignores `gtk.css`; tested on a fresh profile). So the theme writes
  Brave's own seed color (`brave_seed`, `brave_variant`) into the profile Preferences and
  switches it off "GTK" mode. That file is rewritten by a running Brave on exit, so it is applied by
  `~/.local/bin/brave` (a shim to `config/theme/bin/brave`) right before Brave starts, and by
  `theme.py apply` when Brave is closed. Profiles with a web-store theme are left alone.
* **Nautilus** keeps its icon theme for the whole process, new windows included. `theme.py apply`
  quits it when it has no windows; with windows open it just prints a hint. Close them or `nautilus -q`.
* **Blur**: the quickshell bar opts in to Hyprland's own blur via the `qs-bar` layer rule in
  `hypr/hyprland/rules.lua`; tune with `bar_opacity`.
* Not themed: web page contents.
* **Vesktop**: the file is a real copy (a symlink target change would not fire Vencord's folder watch). `theme.py` writes `enabledThemes` + `transparent` in `~/.config/vesktop/settings/settings.json` (read-modify-write, other keys kept) ONLY while Vesktop is closed, else it prints the manual step (Settings > Vencord > Themes > Wall; Vencord settings > transparent window; restart). The transparent window needs no flag; Hyprland's default blur already covers it (no window rule). Radius is a fixed 6 px. Verified in a nested Hyprland with the real logged-in profile (checkerboard backdrop): glass with blur behind, accent selection/unread/focus, engine mono font, status colours, server/DM/friends panes, channel view, context menu, settings modal. The current-name variables (`--background-base-*`, `--background-surface-*`, `--bg-base-*`, `--chat-background-default`, `--app-frame-*`, `--input-background*`, `--background-mod-*`, `--interactive-*`, `--text-*`, `--control-primary-*`, `--brand-*`) drive nearly everything; Discord's hashed class names (`menu_xxxxxx`) change, so rules use `[role=...]` / `[class*="name_"]`. Menus, listboxes and dialogs sit over live page content, so they get a near-opaque fill plus `backdrop-filter` (the glass alpha of the panes is unreadable there). A blanket `[class*="unreadMentionsIndicator"]` background paints solid accent blocks on the server rail: keep accent rules on the badge only. Still Discord-coloured: user avatars/media, the fullscreen User Settings view (dialog fill, dark and flat), login art, status-dot/brand icons, and the "Add Friend" tab clips its text with the wider mono font (fixed width, not fixed). Discord can rename variables: recheck after big UI changes (inspect with `--remote-debugging-port` on a nested instance, never on live).
* **Geary limits** (46): HTML mails keep their own white page (only `div.plaintext` bodies are recoloured; forcing a
  dark page breaks mails that set dark text). The folder tree is a GtkTreeView: no per-folder colours or hover, and
  its unread badges are cairo-drawn `#888` (`CountBadge`), not CSS. Selectors come from Geary 46.0's UI files and
  `geary.css` (`gresource list /usr/lib/geary/libgeary-client-*.so`); recheck them on a Geary upgrade.
  The toast card uses a fixed 12 px radius (the shell's `rounding` is not a template variable), fill `gtk_a_popover`; scoped, other GTK3 apps keep Adwaita's `.app-notification`.

## Omarchy theme dir
`templates/omarchy/colors.toml` -> `out/omarchy/colors.toml` (all 28 keys Omarchy knows, lower-case `#rrggbb`; Omarchy derives `color0..15` and `selection_foreground` itself, so they are not written). Mapping (`omarchy_extras()`): `background`=bg, `lighter_background`=surface, `selection`=overlay, `dark_foreground`=subtle, `muted`/`accent`/ANSI = palette; `dark_background` / `darker_background` = bg mixed 25 % / 50 % toward black (light mode 6 % / 12 %, as catppuccin-latte; 25 % would be mid-grey), `light_foreground` = fg +10 % white, `bright_foreground` = fg +20 % white (light mode: = fg, as latte), `brown` = orange mixed 50 % toward black. Also in `out/omarchy/`: `alacritty.toml`, `kitty.conf`, `ghostty.conf` (our own outputs, same formats), and on a host render `backgrounds/wallpaper.*` (the wallpaper still), `preview.png` and `icons.theme` (Yaru variant by accent hue; omitted for a grey accent). `default/omarchy/` holds only the four text files (`bin/theme-seed` copies it). Linux `deploy()` points `~/.local/state/omarchy/current/theme` at `out/omarchy` (symlink swapped atomically); a REAL directory there (a real Omarchy install) is left alone with a note. Files are rewritten with tmp + rename like all outputs. `selftest.py` parses the generated `colors.toml` under Omarchy's rules for both modes.
* Skipped (Omarchy renders them from its own templates, no equivalent output here): btop, neovim, helix, foot, vscode, obsidian, chromium, hyprland, keyboard.rgb, shell.toml, ...
* Caveats: apps watching `current/theme/colors.toml` through the symlink and our rename-replace writes is NOT verified (a watch on the file or the resolved directory sees the rename; a watch on the `current/` directory does not see the link target change). The wallpaper name inside `backgrounds/` is fixed (`wallpaper.<ext>`), the theme name is `wallpaper`.

## Launcher
`SUPER+D` = `qs ipc call launcher toggle` (Raycast-style launcher, `config/quickshell/Launcher.qml`).
`~/.local/bin` is put on Hyprland's PATH in `hyprland/env.lua` so shims like `brave` resolve everywhere.

## Bar popups, notifications, OSD (quickshell)
* **Notifications** (`Notifs.qml`, `Toasts.qml`, `NotifCard.qml`): toasts top-right of the focused monitor,
  history in the notification center (bell chip; right-click = do-not-disturb, remembered in `~/.cache/qs-dnd`).
  Icons are Adwaita *symbolic* icons tinted with the palette (`NotifIcon.qml`, index in `Icons.qml`);
  app-specific icons (steam, discord) keep their own colors, real images (avatars/art) are untouched.
* **Popups** (`PopupHost.qml`): network (wired + Wi-Fi), bluetooth, calendar, now-playing, notification center.
  `qs ipc call popup toggle center|net|bt|cal|media` opens one on the focused monitor.
* **OSD** (`Osd.qml`): volume follows Pipewire, so `wpctl` keybinds just work; brightness keybinds call
  `qs ipc call osd brightness` (needs `brightnessctl`).
* `nm-applet` / `blueman-applet` stay running as the NetworkManager secret agent and bluez pairing agent;
  their tray icons are hidden in the bar.

## Qt / KDE notes
* `qt6ct` made KDE apps fall back to stock Breeze Light; the KDE platform theme reads `kdeglobals`, which
  `theme.py` keeps current. Qt 5 apps (a few utilities) are unthemed because there is no Qt 5 KDE plugin.
* Per-app KDE color pins (`[UiSettings] ColorScheme=` in `*rc`, e.g. Dolphin's was `Oxygen`) beat the system
  scheme, so `theme.py` removes them. KDE's own accent (`AccentColor`, `accentColorFromWallpaper`) is also
  overridden, otherwise selection/focus colors stay an old wallpaper's.
* One UI font for Qt, KDE and GTK: `ui_font` / `ui_font_size` in `theme.toml` (`ui_font = ""` leaves fonts alone).

## GTK / Brave dialogs / Oxygen cleanup
* Chromium's Open/Save dialogs ignore `gtk-3.0/settings.ini` and user CSS, but obey `GTK_THEME`. GTK's compiled
  dark stylesheet has colors inlined, so `@define-color` overrides don't reach most rules; `theme.py` extracts it
  (`gresource extract`) and remaps greys / the blue family onto the palette. `GTK_THEME` is exported only by the
  Brave shim; globally it would break libadwaita apps.
* `gtk-button-images` / `gtk-menu-images` are forced off: stock images on buttons pull in legacy icons.
* `purge_oxygen()` moves the KDE leftovers (look-and-feel, `kdedefaults/*`, kwin decoration) to Breeze Dark /
  Fusion / our scheme. Cursor themes (`Oxygen_White`, `Oxygen_Black`) are a separate choice and untouched.

## File dialogs (portal) and the empty XDG_DESKTOP_PORTAL_DIR
* Brave/Chromium Open/Save dialogs go through the **xdg-desktop-portal FileChooser**, routed in
  `config/xdg-desktop-portal/portals.conf` (symlinked to `~/.config/xdg-desktop-portal/`): `gnome;gtk`, i.e.
  Nautilus's own libadwaita chooser once `xdg-desktop-portal-gnome` is installed, the (themed) GTK 3 one until then.
  Screen sharing (ScreenCast/Screenshot/RemoteDesktop) stays pinned to the Hyprland backend, and every other
  interface the GTK backend provides is pinned to it so the GNOME backend cannot take anything over.
* A previous gamescope/KDE session left `XDG_DESKTOP_PORTAL_DIR=` (empty) in the systemd user manager, which makes
  the portal load no backends at all. `hyprland/autostart.lua` clears it at login and restarts the portal if needed.
* To test a native dialog without clicking in your session: launch a throwaway `brave --user-data-dir=... --remote-debugging-port=N`
  and click a `<input type=file>` through the Chrome DevTools protocol (`Input.dispatchMouseEvent`).

* **GNOME portal on Hyprland**: the packaged `xdg-desktop-portal-gnome.service` has `Requisite=graphical-session.target`,
  which Hyprland never activates, so it refuses to start and (because the portal does not fall back to the next
  backend) every Open/Save dialog would break. `config/systemd/user/xdg-desktop-portal-gnome.service` overrides it
  without that requirement (a drop-in with `Requisite=` did not take effect, hence the full override). With it,
  Brave's dialogs are Nautilus's own chooser, themed through the usual GTK 4 CSS.

## Twitch player (separate project)

`SUPER+SHIFT+T` opens a menu of the Twitch channels you follow (live first); picking one opens a Quickshell
window with the stream in an embedded mpv and Twitch's own chat beside it. The app lives in its own project,
`~/code/crossatko/twitch-qs-mpv` (see its README/AGENTS.md); this repo only holds the glue:
the launcher's twitch section (`config/quickshell/launcher/SectionsSource.qml`),
the bind in `hypr/hyprland/binds.lua`, and the `twitch-player` / `twitch-popout-chat` window rules in
`hypr/hyprland/rules.lua` (class `org.quickshell`, title `^Twitch - `). The player reads this theme's
`out/palette.json` live, so it recolours with the wallpaper like the bar does. `qs ipc call menu close`
cancels an open dmenu overlay (added for testing it without keystrokes).

## Brave glass tab strip (`brave_mode = "gtk"`)

Brave in GTK mode takes its frame colours from the GTK theme named by `GTK_THEME`. The shim (`bin/brave`) exports
`GTK_THEME=Wall-Glass:dark`: `~/.local/share/themes/Wall-Glass` = `Wall` + `out/host/brave-glass.css` (header bars,
focused and `:backdrop`, at the base fill + `gtk_glass_header`, `brave_glass_alpha` overrides). Chromium keeps that alpha for the tab strip,
so the compositor glass shows through; the toolbar / omnibox row stays opaque. `theme.py brave` (run by the shim
while Brave is closed) sets `extensions.theme.system_theme = 1` and `browser.custom_chrome_frame = true` in GTK mode (with "Use system
title bar and borders" Chromium makes the window opaque and the strip is solid bg). `brave_mode = "seed"` restores the
seed-colour theme on the next shim launch.

Active tab: Chromium's GTK mode draws the selected tab with the toolbar surface (`window.background`, solid, one surface
for tab + toolbar + bookmarks row; it cannot be set separately and CSS cannot reach Brave's native tab strip). That
surface is `brave_active` = bg tinted with the accent (`brave_active_tint`, default 0.2), so the selected tab is a calm
accent block and the toolbar shares it; the active title is fg, inactive titles `brave_dim` (`brave_inactive_ink`, 0.55
fg share). Hover shading is Chromium's own and not configurable. Applies at Brave's next start (GTK theme is read at
launch). Verified in a throwaway Brave in a nested Hyprland.

## Qt / KDE glass (Kvantum, `qt_style = "kvantum"`)

`theme.py` generates the Kvantum theme `Wall` (`~/.config/Kvantum/Wall`): Kvantum's KvFlat recoloured to the palette,
with `templates/kvantum.kvconfig` on top (translucent windows at the base fill, menus at `gtk_glass_popover`,
views at the GTK view layer, Kvantum's own blur off; Hyprland draws the glass). kdeglobals `widgetStyle` and qt6ct
`style` are set to `kvantum`. Video apps and the shell are in Kvantum's `opaque=` list. `qt_style = "Fusion"` +
`theme.py apply` reverts to opaque Fusion. The widget shapes are generated by `kvantum_svg.py` in libadwaita
style (libadwaita is the design reference): radii, Btn fills, accent checks / slider / progress, flat tool buttons.


### libadwaita design match (Qt + GTK3)

libadwaita (with `out/host/gtk4.css`) is the design source; Qt (Kvantum) and GTK3 copy its measured metrics:
34 px buttons / entries / combos / spin boxes (9 px corners, fg 10 % fill, hover 15 %, pressed 30 %, bold labels),
flat 34 x 34 header / tool buttons (hover 7 %), 46-47 px header bar / toolbar, 36-38 px sidebar rows with 6 px
corners and fg 10 % selection, 20 px check boxes / radios (fg 15 % ring -> accent with accent_fg mark), 4 px scale
trough + 20 px knob, 8 px progress, pill tabs, popover menus (12 px corners, 6 px padding, 32 px items, 1 px
separator with 6 px margins). Numbers live in `kvantum_svg.py` (`ALPHA`, shapes), `templates/kvantum.kvconfig`
(geometry) and `templates/gtk3.css`.
* Kvantum tricks: buttons / entries / menus use `frame.expansion` with `expand-*` SVG twins (padding 6-7 px, corners
  9 / 12 px); a default button is drawn with the status `default` (`button-default-*`, accent); Kvantum caps item-view
  frames and text margins at 6 px; unfocused windows ask for `itemview-*-inactive`; QtSvg leaves fully transparent
  shapes out of an element's bounds (spacer rects use opacity 0.001).
* Icons (`qt_symbolic_icons`): `gen_qt_icons()` writes `~/.local/share/icons/Wall-Adwaita-Qt` (Qt / KDE only; GTK
  keeps Wall-Adwaita): Adwaita's symbolic actions under their plain names + KDE aliases (`QT_ICON_ALIASES`), Breeze
  Dark's monochrome actions for the rest, symbolic places / devices for 16-24 px requests, then the colour
  Wall-Adwaita dirs (symlinks). `deploy()` points kdeglobals / qt5ct / qt6ct at it and writes 16 px icon-only
  toolbars (kdeglobals) and Dolphin's places panel at 16 px (dolphinrc). It is generated with the icons on `apply`.

## Video wallpapers and per-monitor wallpapers (invariants)
State is `~/.local/state/theme/wallpapers.json` (written only by `theme.py`; schema in the source); what each output shows is resolved into `out/hyprpaper.conf` / `out/wallpaper.json` (see "Wallpaper backend"). With the hyprpaper backend every `apply` live-sets hyprpaper with `hyprctl hyprpaper wallpaper "<selector>,<path>,cover"` (`hyprpaper_show`, per output that shows something else):
the selector must match the config block's (`desc:<key>` for description keys, connector only for connector keys), else it exits 0 silently (the worker polls `listactive` and restarts hyprpaper).
Videos run as one `mpvpaper` per output (pid files and logs in `$XDG_RUNTIME_DIR/theme-video/`; stop only if `/proc/<pid>/comm` is `mpvpaper`); `MPV_OPTS` keep `load-scripts=no` (else `mpv-mpris`
makes wallpapers MPRIS players) and `display-fps-override` must equal the real refresh. "Optimize for monitor" builds an HEVC/H.264 copy per (video, monitor) in `$XDG_CACHE_HOME/theme/video/opt/`;
`hevc_vaapi` + `hvc1` needs `-bsf:v extract_extradata`; stills and the palette always come from the original; with no hardware decode (AV1 on the Workstation GPU) the still stays until the copy exists.
Play-once timing: an entry without a stored `play` gets the defaults (theme.toml `replay_play_default = 0`, `replay_wind_default = 5`, `replay_ease_in = 0`: wind down at once over 5 s, stop at 2.5 s); full length is stored explicitly as `"play": "full"` (`apply --play full`; Settings: Play for at its maximum); stored values are never rewritten.
Baked wind-down/replay bursts use RIFE (`rife-ncnn-vulkan`, fallback ffmpeg `minterpolate`); keep `BAKE_VERSION`/`OPT_VERSION` in the cache keys when changing the pipeline. `THEME_BAKE=0` disables baking.
