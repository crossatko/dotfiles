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
| `theme.py apply [image]` | re-analyse a wallpaper, render everything, reload apps |
| `theme.py render` | re-render after editing `theme.toml`, `theme.local.toml` or a template (no re-analysis) |
| `theme.py default` | (committer) regenerate the tracked default theme in `default/` from `default/wallpaper.jpg` and `theme.toml` |
| `bin/theme-seed` (`theme.py seed`) | fill a missing `out/` from `default/` (done by install.sh, the git hooks, theme.py) |
| `theme.py mode [get\|dark\|light\|toggle]` | switch the light / dark mode (also: Settings > Wallpaper & theme > Color mode): saves it, re-renders from the cached wallpaper analysis and reloads every app, leaves hyprpaper running |
| `theme.py show` | print the resolved palette (current mode) |
| `python3 -I selftest.py` | run the extractor against 20 nasty synthetic wallpapers |

## Editing
* **Pin a color**: `[overrides]` in `theme.toml` (e.g. `accent = "#c0392b"`; for this machine only: in `theme.local.toml`), then `render`.
* **Tone down / punch up terminal colors**: `ansi_saturation`, `ansi_lightness`.
* **Picker folders**: `wallpaper_dirs` (images), `video_dirs` (video wallpapers, default `~/Videos/wallpapers`).
* **Layout defaults** (`[settings]`, Quickshell only): `rounding` (default corner radius, px), `gap` (window gap, px),
  `border_size`, `bar_floating` (false = docked bar), `smart_gaps` (lone window: no gaps/border/rounding),
  plus `bar_border` and `bar_opacity`. They are static (the wallpaper only drives colors) and are written
  to `out/palette.json` as real booleans/numbers (`out/palette.lua` only carries `rounding`, as before).
  The old `bar_gap` / `bar_radius` keys are gone: the bar margin and radius are derived from `gap` /
  `rounding` when `bar_floating` is on. Hyprland does not read these: its own values are hand-written in
  `hypr/hyprland/` (theme.lua, settings.lua), so keep the two in sync if you change a default.
* **User overrides**: Settings > Appearance writes `~/.local/state/quickshell/appearance.json`
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
  * Settings > Glass (Hyprland solid_glass options, `~/.local/state/quickshell/glass.json`): top-level keys = dark, a `"light"` object = light; the page edits the active mode's set and swaps sets on a mode switch (`GlassTuneCtl.qml`); `hypr/hyprland/managed.lua` applies the active set (mode read from palette.lua's bg luminance), unset keys = settings.lua's values, light tint / darkening default to the dark settings.lua glass mirrored. `tint_from_bg` (per mode, "Tint colour" toggle; light default on): tint colour = palette bg, alpha kept. theme.py splits an old single-set glass.json once (`migrate_glass_modes`): the existing values stay the dark set, light starts from a copy with the tint mirrored to a pale one and darkening off.
* **Bar on the wallpaper:** a bar without backdrop (Settings > Bar "transparent when flush") draws its text on the wallpaper. In light mode `palette.json` also carries `dark` (the dark palette's text colours) and `wall_ink` (`wall_inks()`: per monitor connector and bar edge, which palette's fg reads better on the wallpaper strip under the bar); `Bar.qml` `ink` / `Theme.inkOn()` pick it, `Chip` / `BarIcon` / `BarLabel` follow their chip's `ink`. Per-monitor wallpaper changes refresh `wall_ink` (`refresh_wall_ink`).
* **Apps:** freedesktop `color-scheme` (`prefer-dark` / `prefer-light`, gsettings -> Settings portal: running Chromium / Electron / libadwaita apps flip live), `gtk-application-prefer-dark-theme`, the GTK 3 theme `Wall` (stock light or dark stylesheet recoloured; GTK 4 imports `Adwaita.css` / `Adwaita-dark.css`), KDE `LookAndFeelPackage` (Breeze / Breeze Dark), Brave (`color_scheme2`, applied at its next start; the shim exports `GTK_THEME=Wall[-Glass]` with `:dark` only in dark mode), nvim (`background` from the palette). Autostart (`hypr/hyprland/autostart.lua`) sets `color-scheme` from the state file before the browsers start.
* **Kvantum:** colours with alpha are written as `#RRGGBBAA`, which is what Kvantum parses (`getFromRGBA`; stock themes use it).
* Known limits: GTK 4 / libadwaita windows already open keep their colours until reopened (the portal flip reaches apps that listen for it); Brave switches at its next start. `wall_ink` judges a video wallpaper by its still and assumes a 16:9 cover crop; dark mode does not use it (light text on a bright wallpaper stays as it was). Settings > Glass shows its own built-in defaults (not settings.lua's) for keys the active mode's set does not contain.

## How the extractor picks colors
Background/foreground come from the darkest third / lightest quarter of the image,
clamped so the dark theme is dark with readable text (light mode: see above). The **accent is the most
chromatic region**, not the most common color, so art that is mostly greyscale with one
red streak (like drakengard.jpg) still gets its red. Greyscale images fall back to the
foreground as accent. Contrast is enforced: fg ≥ 9:1, accent ≥ 4.6:1, ANSI ≥ 4.5:1.

## What follows the wallpaper, and how it reloads

| app | how it gets colors | live reload |
|---|---|---|
| kitty, ghostty | `include` / `config-file` of `out/` | yes (SIGUSR1 / SIGUSR2) |
| alacritty | `general.import` | yes (watches imports) |
| nvim | catppuccin fed from `out/palette.lua` | yes, every running instance (RPC `ThemeReload()`) |
| zellij | theme file `themes/wall.kdl` | yes (rewrite of config.kdl triggers its watcher) |
| herdr | `~/.config/herdr/config.toml` is generated (tracked `config/herdr/config.toml` + this machine's `[theme]` block; herdr has no include) | `herdr server reload-config` |
| hyprland, hyprlock, hyprtoolkit, hyprpaper | `dofile` / `source` / symlink | yes (`hyprctl reload`, hyprpaper restart); hyprlock reads its wallpaper path on each lock |
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
State is `~/.local/state/theme/wallpapers.json` (written only by `theme.py`; schema in the source). A non-primary `apply` live-sets hyprpaper with `hyprctl hyprpaper wallpaper "<selector>,<path>,cover"`:
the selector must match the config block's (`desc:<key>` for description keys, connector only for connector keys), else it exits 0 silently (`live_set_wallpaper()` polls `listactive` and restarts hyprpaper).
Videos run as one `mpvpaper` per output (pid files and logs in `$XDG_RUNTIME_DIR/theme-video/`; stop only if `/proc/<pid>/comm` is `mpvpaper`); `MPV_OPTS` keep `load-scripts=no` (else `mpv-mpris`
makes wallpapers MPRIS players) and `display-fps-override` must equal the real refresh. "Optimize for monitor" builds an HEVC/H.264 copy per (video, monitor) in `$XDG_CACHE_HOME/theme/video/opt/`;
`hevc_vaapi` + `hvc1` needs `-bsf:v extract_extradata`; stills and the palette always come from the original; with no hardware decode (AV1 on the Workstation GPU) the still stays until the copy exists.
Baked wind-down/replay bursts use RIFE (`rife-ncnn-vulkan`, fallback ffmpeg `minterpolate`); keep `BAKE_VERSION`/`OPT_VERSION` in the cache keys when changing the pipeline. `THEME_BAKE=0` disables baking.
