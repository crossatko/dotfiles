# DESIGN.md — the shell's design language

The one document for how the Quickshell shell (bar, popups, launcher, notifications, OSD, Settings, lock and desktop clock)
looks and behaves. Tokens live in `config/quickshell/Theme.qml` (the "Design language" block), motion in `Motion.qml`, glyphs in
`Icons.qml`, presets in `Presets.qml`. A component never carries a literal px / colour / duration / radius / glyph: a content cap
(list height, art size) is a named `readonly property` with a one-line comment. AGENTS.md holds the rules of the repo; this file
holds the rules of the look.

## 1. Principles

- **Calm, and colour carries state.** An icon is accent where its feature is connected / on / live, muted where it is off
  or missing, red / green / yellow where that means something, plain ink only for always-present information. Nothing
  pulses or glows without a reason.
- **Polish, not restructure.** A pass over the look adjusts type, spacing, radii, alignment and hairlines with the tokens
  below; it does not change which chips / rows / labels exist, their order, their glyphs or their colour roles.
- **One system.** The same row, the same button, the same empty state everywhere. A part that appears twice is a shared file.
- **Words are labels.** Titles, labels and values; an empty / off state is two to three words; a technical note is an `InfoTip`.
  No sentences in popups, no footnotes.
- **The wallpaper is part of it.** Glass cards refract it, the flat bar's ink adapts to it (`BarInk`). The look must hold on a
  bright, a dark and a busy wallpaper, in light and dark mode, with every glass preset and on stock Hyprland (no glass).

## 2. Tokens

### Colour (palette from `theme.py`, `Theme.<name>`)

| role | token | used for |
|---|---|---|
| text | `fg` | titles, values, always-present informational icons (clock, calendar, control center, a Bluetooth adapter that is merely on) |
| secondary | `fgDim` | sub lines, captions, section heads, a slider's value, the leading icon of a tile / card / launcher row at rest |
| tertiary / off | `muted` | an off / unavailable / muted state's icon and text, the empty-state row, placeholder text, hint lines |
| accent | `accent` | **connected / on / live / selected / open**: a wired or Wi-Fi link, a connected Bluetooth device, unmuted audio, a playing player, a usable AI account, a running VM, lights on, caffeine on, the focused workspace, the open popup's chip, a connected row's icon and check, an "on" tile or toggle, a primary button, a badge (notification count) |
| second series | `accent2` | a second data series next to an accent one (the memory sparkline, the RAM meter) |
| semantic | `red` / `green` / `yellow` / `orange` | only with meaning: danger / recording / low battery, ok / charging / online, warning, a VPN in lockdown |
| fills | `itemFill` `itemHover` `itemActive` `accentFill` `accentHover` | L1 items (below) |
| edges | `edge` `accentEdge` `dangerEdge` | the L2 card hairline; an open / focused / asking control; a danger box |

A bar chip's icon shows the chip's state; the value next to it stays `fg` (the number is information, the glyph is the state).
Brand marks and bitmap icons follow the chip's role too (the media chip's Spotify mark is accent while playing, muted while
paused). Light mode: the same roles, the palette flips. Bar on a bare wallpaper: the same roles from the section's `BarInk`
set (dark or light variant of every state colour).

### Type (Paper Mono; digits line up by themselves)

`fontTitle` 17 popup / modal / Settings title · `fontLead` 15 the one prominent line of a card (media title, a big value) ·
`fontSize` 13 body · `fontSmall` 12 buttons, secondary lines, values next to sliders · `fontCaption` 11 sub lines, captions,
section heads · `fontTiny` 10 badges. Bold only for titles and a primary button.

### Icons (Font Awesome 7 Sharp Regular, brands from Font Awesome 7 Brands)

`iconSm` 12 inline markers (check, chevron, pill glyph, InfoTip) · `iconMd` 15 default: bar chips, buttons, compact rows ·
`iconLg` 18 the leading icon of a list row or tile (in an `iconCol` 22 column) · `iconXl` 22 OSD, empty states.

### Spacing, heights, widths

`gapTight` 4 items of a list, label to value · `controlGap` 6 adjacent controls · `gapRow` 8 rows, head to list ·
`padSm` 10 inset of a compact control · `pad` 12 card padding, row insets, between blocks.
`controlH` 30 buttons, dropdown rows, fields · `rowH` 44 list rows · `rowTallH` 54 two-line tiles.
`popupW` 380 lists and controls · `popupWide` 420 grids and cards. Bar: `barHeight` 40, `chipHeight` 28, `chipIcon` 16.

### Radius (Look & feel > Shape; `Theme.inner(outer, inset)` keeps corners concentric)

`radius` the card · `radiusItem` an item inside a card · `radiusDeep` inside an item · `radiusChip` a bar chip ·
`radiusModal` the launcher / modal. A button never rounds past a third of its height.

### Elevation

- **L0 chip** (`Chip`): flat on the bar. No fill at rest on a bare bar, a faint `bg` wash on a backdrop; a soft `accent` fill
  with a 1 px accent outline while `active` (its popup is open, its state is on); the ink set's hover wash while hovered.
- **L1 item** (`ListRow`, `Tile`, `Notice`, `Btn`, pickers, cards inside a popup): `itemFill`, `itemHover`, `itemActive`;
  selected / on = `accentFill` / `accentHover`. Boxes that must read as separate objects keep a hairline (`Notice`, `Tile`,
  the keycap `KeyBadge`); `accentEdge` marks an open / focused / asking / selected control and `dangerEdge` a danger box.
- **L2 card** (`PopupHost`, OSD, toast, `ModalMenu`, Settings): `cardFill` over the compositor's glass + the `edge` hairline +
  `GlassEdge` (stock) / `RimLight`. The tray menu (an xdg popup without glass of its own) keeps its opaque fill, same tokens.

### Motion (`Motion.qml`; Look & feel > Motion presets)

`pressMs` 80 · `hoverMs` 120 · `moveMs` 200 · `exitMs` 150 · `emphasisMs` 300 at 1x; `Motion.ms(base)` scales with the speed
setting (16 ms floor, 0 when off). Curves `easeEnter` / `easeMove` / `easeExit` follow the Curve setting, `easeHover` is OutCubic.
State pulses (`busyPulseMs` 380, `heartbeatMs` 760) are states, not transitions: never speed-scaled. Overshoot only on a press
release and a toast landing. Parts: `PressFeedback`, `HoverGlow`, `GlideHighlight`, `Reveal`, `OpenMotion`, `FoldBox` + `Chevron`.
Fade colours with `Theme.alpha(sameColour, 0)`, never "transparent" (lerps through black).

## 3. Colour logic, in five lines

1. A state icon is `accent` while its feature is connected / on / live and `muted` while off / missing / muted; the bar
   must show at a glance what is connected (Bar.qml lists every chip's rule).
2. `accent` also means selected / open: the open popup's chip, the focused workspace, an "on" tile, toggle or row, a
   connected list row's icon and check, a primary button, a badge (notification count).
3. `fg` is for information that is always there (clock, calendar, values next to a state icon); `fgDim` for secondary
   lines and the leading icons of tiles / cards / launcher rows.
4. `red` / `green` / `yellow` / `orange` only carry meaning (recording, danger, low battery / ok, charging, online / warning / lockdown).
5. Brands and bitmaps follow the role of the thing they stand for, never a fixed white.

## 4. Icons

- Every glyph is a name in `Icons.qml`, chosen once by meaning (`Icons.home`, `Icons.wifiOff`, `Icons.dock`); a state has its
  own name (`bellOn` / `bellOff`); `Icons.volumeGlyph` / `wifiGlyph` / `batteryGlyph` map levels. `launcher/*.qml` cannot see root
  singletons and keep code points, with the glyph name in a comment.
- Pick by meaning, not by look. A new glyph: find its code point in the installed Sharp Regular font (`fontTools` over the font
  file; the Pro fonts live in `~/.local/share/fonts/FontAwesomePro/`, never in this repo), add it with the font's glyph name.
- One glyph per meaning across bar, popups, launcher and Settings (a monitor is `desktop`, a VM is `desktop` too, Home Assistant is `house`).
- Do not use: `charging-station` for a vacuum dock (it is an EV charger), `plug` for anything but "connect", a brand mark for a
  generic feature, a Solid weight glyph next to Regular ones (the bar's AirPods battery is the one deliberate Solid), Nerd
  Font glyphs (the icon font is Font Awesome). The control center chip is `menu` (bars) by the user's choice; `controlCenter`
  (sliders) is for the Settings list only.
- Bar chips use `BarIcon` (ink-centred box, never `BarLabel` with the icon font); popups use `Icon` (a Label in the icon font).

## 5. Components

| part | anatomy | notes |
|---|---|---|
| `Chip` + `BarIcon` / `BarLabel` | chipHeight tall, icon-only = a square; `active`, `dim` (`dimOpacity`), `show` | never set `implicitWidth`; the ink set comes from the section's `BarInk` |
| `PanelHeader` | bold title, optional status, trailing `Btn` / `Toggle` | one per popup, first row |
| `SectionHead` | caps caption, hairline, detail, trailing items (a `Toggle`) | `FoldSection` = a SectionHead that folds its body |
| `ListRow` + `RowText` + `RowState` | rowH tall, leading icon (iconCol), title / sub, trailing mark (check / busy / hover hint) | `selected` = on; `outlined` = asking / open; expandable `body` |
| `Tile` | rowTallH, leading iconLg, title + state line | control-center quick toggles; `on` = accentFill + accent icon |
| `Notice` | the L1 box: a column of children on itemFill, `danger` = red | messages, confirmations, compact cards |
| `EmptyState` | one inline row, left-aligned with the section: iconSm glyph + two-to-four words, both `muted`, optional wrapping caption `hint`; controlH tall | the only empty / off state (Wi-Fi off, no events, nothing playing, no VMs); never a large centred glyph or a blank box (an empty agenda shrinks to the row). `big` only for a whole empty Settings page |
| `Btn` | controlH, itemFill, `active` = accentFill + accentEdge; `icon: true` for a glyph | concentric radius via `outerRadius` + `inset` |
| `Toggle` / `Slider` / `Meter` | the real state is what they show; a change is a signal, never a local flip | `busy` pulses; the knob and the slider handle grow a `GlassLens` |
| `DropSelect` | the one dropdown (`DevicePicker`, `BtProfilePicker`, `CalPicker` wrap it) | open head = itemActive + accentEdge |
| `Segmented` / `ResetBtn` | a joined row of equal options (`GlideHighlight` marks the choice); the per-key undo at the end of a Settings row, dim at the default | `KeysReset` in MotionAdvanced wraps ResetBtn for several keys |
| `StatusDot` / `Pill` / `InfoTip` | 8 px state dot (semantic tint, `pulse`), a caption badge, a hover tooltip glyph | the InfoTip is where a technical note goes |
| `PopupHost` | the L2 card, `pad` padding, width from `Popups.panels` | content keeps its target size while the card morphs |
| `MonitorChooser` + `MonitorChip` | a strip of L1 chips (wallpaper still, model / connector, `PrimaryTag`), gliding accent marker, optional link buttons between neighbours, trailing actions | the only monitor picker of a Settings page; reads / writes `Monitors.selected` |

States: hover = the item's hover fill + `HoverGlow`; press = `PressFeedback`; disabled = `disabledOpacity`; a dimmed chip =
`dimOpacity`; busy = the pulse tokens; focused / asking = `accentEdge`; selected / on = `accentFill`.

## 6. Settings

Pages: Look & feel (Colour mode; Glass / Motion / Shape presets with previews and `GlassAdvanced` / `MotionAdvanced` /
`ShapeAdvanced` folds), Monitors, Wallpaper, Bar, Lock screen, Desktop clock. Page pattern: title only; the one to three primary choices
first (`PresetCards` = visual cards with a live preview and a tick, `ChoiceRow` = `Segmented` + `CustomTag` + a hint of five
words at most + `InfoTip`), then one `AdvancedFold` ("Customise…", `detail` = a short badge) with every detailed row
(`PrefSlider` / `PrefToggle` / `PrefSwitch` / `GlassOptRow`), then `PageReset`.
Monitors are always in `Monitors.ordered` order (primary first) with a `PrimaryTag`. A page that edits one monitor's settings picks it with the
one `MonitorChooser` (chips, the shared `Monitors.selected`, hidden with one monitor; links / an "All" chip / a status line / an accent mark as
options); the Monitors page selects on its `MonitorPicker` map, same selection. Everything per monitor that is on / off (primary, bar, lock clock,
desktop clock) lives only on the Monitors page (one `MonitorCard` with `LabelSwitch` tiles for the selected monitor); feature pages keep only
their own settings.
Presets drive tokens: a preset is a named value set in `Presets.qml`; `<area>Current` reports which set the saved values equal
(else Custom; nothing is migrated), `apply<Area>()` writes through the stores' own setters. Glass presets feed
`GlassTuneCtl.effective` (compositor glass, `GlassLens`, glass lettering), Motion presets feed `Motion.*`, Shape presets feed the
radii and gaps, the Bar look cards feed `bars.json` (Floating / Docked / Transparent; Transparent switches `BarInk` on).

## 7. Do / don't

- Do: `BarIcon { text: Icons.wifi; color: connected ? ink.accent : ink.muted }`: the glyph says connected / off.
- Don't: a white glyph for every chip (the colour had a reason); a red icon for anything but danger / recording.
- Do: `EmptyState { icon: Icons.wifiOff; text: "Wi-Fi is off" }` as a row where the list would be.
- Don't: a big centred glyph over a blank area, a muted Label "There is nothing playing right now.", a Notice with a paragraph.
- Do: a polish pass that aligns baselines, evens padding and uses the radius tokens.
- Don't: a pass that moves chips, drops labels, changes glyphs or colour roles, or re-lays out a popup.
- Do: `Btn { outerRadius: Theme.radiusItem; inset: Theme.gapRow; text: "Connect"; active: true }` inside a Notice.
- Don't: `Rectangle { radius: 6; color: "#2a2a2a"; border.width: 1 }` built inline, `font.pixelSize: 14`, `duration: 150`.
- Do: one `rowH` row with `RowText` for a device; `selected` while connected.
- Don't: a one-off card with its own padding, a custom toggle, a second dropdown style.

## 8. Adding things

- **Bar widget:** a registry entry in `BarWidgets.widgets` (id, title, `Icons.<name>`, section) + a `Component { Chip { ... } }`
  in `Bar.qml` added to `widgetComps`; per-machine state goes into a singleton gated by `BarWidgets.shown(id)`; the icon's colour
  follows section 3 (accent while connected / on / live, muted while off / missing, plain only for information).
- **Popup:** `XPanel.qml` (loaded by URL: no qmldir entry) built from `PanelHeader` / `SectionHead` / `ListRow` / `EmptyState`,
  one entry in `Popups.panels` (source, `popupW` or `popupWide`), and the chip's `bar.pop("x", chip)` / `bar.reg`.
- **Setting:** a row (`PrefSlider` / `PrefToggle` / `PrefSwitch` / `ChoiceRow`) in the page's `AdvancedFold`, backed by the
  feature's prefs singleton (`spec` + `defaults` + a readonly accessor, the `LockPrefs` pattern); a primary choice only when it is a
  clear few-way decision with a preview, then also a `Presets.qml` table entry.
- **Shared UI** that appears twice becomes its own file + qmldir entry (a new type needs a full shell restart).
- **Checking a change:** nested Hyprland (AGENTS.md), screenshots of the user's saved look first, then dark / light, the three
  bar looks, a bright / dark / busy wallpaper, the glass presets and the stock shim; `qmllint` clean against the baseline.
