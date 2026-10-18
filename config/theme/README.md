# theme — one place for every color

```
theme.toml ─┐
wallpaper ──┼─> theme.py ─> out/palette.{json,lua} + one file per app (templates/)
overrides ──┘                      │
                                   └─> kitty ghostty alacritty tofi zellij hyprland
                                       hyprlock hyprtoolkit hyprpaper nvim quickshell
```

| do this | to |
|---|---|
| `SUPER+T` | open quickshell Settings on the Wallpaper & theme page (`qs ipc call picker toggle`; again = close); click a wallpaper (or arrows + Enter) to apply it everywhere |
| `theme.py apply [image]` | re-analyse a wallpaper, render everything, reload apps |
| `theme.py render` | re-render after editing `theme.toml` or a template (no re-analysis) |
| `theme.py show` | print the resolved palette |
| `python3 -I selftest.py` | run the extractor against 20 nasty synthetic wallpapers |

## Editing
* **Pin a color**: `[overrides]` in `theme.toml` (e.g. `accent = "#c0392b"`), then `render`.
* **Tone down / punch up terminal colors**: `ansi_saturation`, `ansi_lightness`.
* **Picker folders**: `wallpaper_dirs`.
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
* `out/` is committed on purpose so a fresh clone works before the first `apply`.

## How the extractor picks colors
Background/foreground come from the darkest third / lightest quarter of the image,
clamped so the theme is always dark with readable text. The **accent is the most
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
| herdr | managed `[theme]` block injected into `config/herdr/config.toml` | `herdr server reload-config` |
| hyprland, hyprlock, hyprtoolkit, hyprpaper | `dofile` / `source` / symlink | yes (`hyprctl reload`, hyprpaper restart); hyprlock reads its wallpaper path on each lock |
| quickshell bar + Settings | watches `out/palette.json` | instant |
| notifications | quickshell `Notifs.qml` server + toasts + notification center | instant, palette-driven |
| launcher / menus | quickshell `Menu.qml` (replaced tofi; fzf does the matching) | instant, palette-driven |
| tofi (fallback only) | symlinked config | read at launch; used only if quickshell is down |
| Qt / KDE apps (Dolphin, Ark, ...) | KDE platform theme (`QT_QPA_PLATFORMTHEME=kde` in `hyprland/env.lua`) reading `~/.config/kdeglobals`: color scheme `Wall`/`WallB` + accent, fonts, icons, Fusion style | backgrounds, text and icons live; selection highlight on next window |
| GTK 3 apps, Brave dialogs | named theme `Wall` (`~/.local/share/themes/Wall`): GTK's dark stylesheet re-colored by `recolor_gtk_css`; Brave gets `GTK_THEME=Wall:dark` from its shim | GTK 3 apps reload on theme change; Brave on restart |
| GTK 4 / libadwaita apps, nautilus | `~/.config/gtk-{3,4}.0/gtk.css` -> `out/gtk.css` | **after the app restarts** (see below) |
| Adwaita icons | generated hue-rotated copy `Wall-Adwaita` (see below) | new windows / apps that reload icons |
| Brave | seed-color theme written into its Preferences by the `~/.local/bin/brave` launcher shim | at next start (Brave rewrites Preferences on exit, so it can't be edited while running) |

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
* Not themed: Discord, web page contents.
* `out/` is committed on purpose so a fresh clone works before the first `apply`.

## Menus (tofi replacement)
`SUPER+D` = `qs ipc call menu drun`: full-screen launcher laid out like the old tofi config,
fuzzy matching by `fzf --filter`, ranking = your tofi launch history + new launches
(`~/.cache/qmenu/drun-history`). Other menus pipe into `qmenu --prompt-text 'X: '`
(`config/quickshell/bin/qmenu`, a drop-in for `tofi --prompt-text`): prints the chosen line,
exit 1 on cancel, falls back to tofi if quickshell isn't running. `~/.local/bin` is put on
Hyprland's PATH in `hyprland/env.lua` so shims like `brave` and `qmenu` resolve everywhere.

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
  Fusion / our scheme. Cursor themes (`Oxygen-White`, `Oxygen_Black`) are a separate choice and untouched.

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
`hypr/scripts/twitch-menu.lua` (menu launcher, absolute paths because Hyprland's PATH differs),
the bind in `hypr/hyprland/binds.lua`, and the `twitch-player` / `twitch-popout-chat` window rules in
`hypr/hyprland/rules.lua` (class `org.quickshell`, title `^Twitch - `). The player reads this theme's
`out/palette.json` live, so it recolours with the wallpaper like the bar does. `qs ipc call menu close`
cancels an open dmenu overlay (added for testing it without keystrokes).
