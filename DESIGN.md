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
- **The wallpaper is part of it.** The shell draws it (`WallpaperLayer`, background layer; a change cross-fades over
  `Motion.emphasisMs`), glass cards refract it, the flat bar's ink adapts to it (`BarInk`). "What does this monitor show"
  = `Wallpaper.pathFor(screen)` (or `LockWallpapers.stillFor`, which delegates), never a re-derivation. The look must hold on a
  bright, a dark and a busy wallpaper, in light and dark mode, with every glass preset and on stock Hyprland (no glass).
  Stock has no compositor glass (`Theme.glass`: cards fall back to fills + `GlassEdge`), but the shell's own glass (clocks,
  beads, lock slab, lenses: `Theme.shellGlass`) is the same there: it refracts the wallpaper in the shell's shaders.

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

### Icons (Vadivam outline, brands from Font Awesome 7 Brands)

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
| `Toggle` / `Slider` / `Meter` | the real state is what they show; a change is a signal, never a local flip | `busy` pulses; the knob and the slider handle grow a `GlassLens`; every slider has notches (below) |
| `DropSelect` | the one dropdown (`DevicePicker`, `BtProfilePicker`, `CalPicker` wrap it) | open head = itemActive + accentEdge |
| `Segmented` / `ResetBtn` | a joined row of equal options (`GlideHighlight` marks the choice); the per-key undo at the end of a Settings row, dim at the default | `KeysReset` in MotionAdvanced wraps ResetBtn for several keys |
| `StatusDot` / `Pill` / `InfoTip` / `TipBubble` | 8 px state dot (semantic tint, `pulse`), a caption badge, a hover tooltip glyph, the hover bubble itself | the InfoTip is where a technical note goes; `TipBubble` (as wide as its wrapped text) also shows a cut `FitLabel` in full |
| `PopupHost` | the L2 card, `pad` padding, width from `Popups.panels` | content keeps its target size while the card morphs |
| `MediaPanel` / `LockMedia` + `MediaArt` / `MediaSeek` / `MediaTransport` / `MediaStats` / `MediaBadge` / `LivePill` / `FitLabel` | art (cover, channel picture or the source's brand mark), title (fontLead), subtitle (fgDim), category (gamepad badge), stats row (LIVE pill, viewers `user` + 12.3K, stream time `clock` + H:MM:SS; badges = iconSm glyph + caption, fgDim, no box; caption muted last), seek bar (MPRIS only), transport, volume `LevelRow` (a source with its own volume) | any `MediaSources` source; a control the source lacks is not drawn (no dead buttons); several sources = a `Segmented` switcher above the card, active first; the lock card shows only play / pause / previous / next. Long text never overflows: `FitLabel` wraps to 2 lines then elides (popup: full text in a `TipBubble` on hover), badges elide, the stats wrap on a narrow card |
| `TvSource` + `MediaVolumeSteps` | the TV card as a media source (a Send to TV session, or what the TV plays by itself): cover from HA else tv glyph art (iconFont), a `tv` badge with the TV's name, a read-only seek bar when the TV reports a length, transport prev / seek back / play / seek forward / next / stop / disconnect (`linkOff`, sent sessions only), volume = a level slider (Cast) or icon steps mute / down / up | a sent session is first in the popup, chip and lock card while it lasts; an auto-detected one follows the pick rule (a playing local player wins); lock: play / pause only; local sources stay in the switcher; nothing at all while the TV is off / idle / on its home screen |
| `TvButton` | Send to TV (TvCast): one icon `Btn` at the media card's transport row end, outside the row's layout (it fades in / out, nothing moves); the glyph IS the progress: `tv` -> `power` (waking) -> `circlePlay` (opening; both pulse with `busyPulseMs`, still when motion is off) -> `check` -> `warning` (red) -> `tv`; hover = `TipBubble` ("Send to <TV>", the error) | shown only when it would work (no disabled state); never on the lock card; Settings > TV picks the target: one entry per physical TV (icon, device name, state dot; never a backend word) |
| `MonitorSection` + `MonitorChip` (+ `MonitorThumb`, `MonitorStateCell`, `MonitorLink`, `MonitorAction`, `LabelSwitch`) | the monitor section: equal split chips (wallpaper still, name over connector, `PrimaryTag` dot, badge; the state cell at the end) on a constant 28 px seam, gliding accent marker, link bridges on the seams, "All" tile + icon actions at the row's end | the only monitor selector and per-monitor switch of Settings; see "Monitor section" below |
| `MonitorLink` | the bridge on a seam: a plain chain glyph (no pill, no border), accent with a short accent connector line on both sides while linked, a faint fg glyph alone while not; the whole seam is the hit area | links two neighbouring monitors (Wallpaper, Bar); never a slashed glyph or a disabled look for "not linked" |
| `MonitorStateCell` | a square cell: eye (accent) = on here, eye-slash (muted) = off, lock = cannot change; hairline on its left, hover wash + tooltip | the per-monitor switch everywhere (chips, "All", the Monitors card's `LabelSwitch` tiles); never a `Toggle` knob for a per-monitor on / off |

States: hover = the item's hover fill + `HoverGlow`; press = `PressFeedback`; disabled = `disabledOpacity`; a dimmed chip =
`dimOpacity`; busy = the pulse tokens; focused / asking = `accentEdge`; selected / on = `accentFill`.

**Slider notches** (`NotchSnap` + `NotchTicks`, used by `Slider` and `HaStrip`):
- Every slider has one default notch (where it sticks, what a double-click resets to) and at most a few extras (preset
  values, full scale, centre). Only the media seek bar (a `Meter`) has none.
- Look: a 2 px tick per notch at the handle centre, default 12 px at `fg` 50 %, extras 8 px at 30 %; on the HA colour
  strips the ticks sit under the strip.
- Feel: a drag snaps within max(2 % of the travel, 8 px) and lets go only past max(14 px, capture + 6); wheel and arrow
  steps stop on a notch they cross, Shift + arrow jumps notch to notch; Tab focuses (accent ring). A snap swells the handle /
  lens by 3 px for `Motion.moveMs` (none with reduced motion), no sound.
- Adding: `notches: [default, extras...]` in the track's 0..1 units (a bare number is the default when first, else an
  extra; or `{ v, kind }`). Shared sets in `Presets.qml`: `volumeNotches` 80 / 100 %, `micNotches` 100 %,
  `brightnessNotches` 80 / 100 %, `centreNotches` 50 %. `PrefSlider` takes the store default plus `extras` (key units,
  e.g. `Presets.lockSize.map(p => p.v)`), `GlassOptRow` the option default (a surface profile: the global value via `mark`).
  A row whose reset means "unset the key" sets `resetToNotch: false` and handles `resetRequested()`.
- Home Assistant controls are optimistic: a click shows its expected result in the same frame (predicted overlay in `HomeAssistant.byId`);
  the only sign of a slow server is the Toggle knob pulse after 1.2 s, a failure rolls back and shows the existing error strip.

## 6. Settings

Pages: Look & feel (Colour mode; Glass / Motion / Shape presets with previews and `GlassAdvanced` / `MotionAdvanced` /
`ShapeAdvanced` folds), Monitors, Wallpaper, Bar, Lock screen, Desktop clock. Page pattern: title only; the one to three primary choices
first (`PresetCards` = visual cards with a live preview and a tick, `ChoiceRow` = `Segmented` + `CustomTag` + a hint of five
words at most + `InfoTip`), then one `AdvancedFold` ("Customise…", `detail` = a short badge) with every detailed row
(`PrefSlider` / `PrefToggle` / `PrefSwitch` / `GlassOptRow`), then `PageReset`.
Monitors are always in `Monitors.ordered` order (primary first) with a `PrimaryTag`. Every page with per-monitor settings starts with
the monitor strip (below); the Monitors page selects on its `MonitorPicker` map (same selection, same `PrimaryTag`, `MonitorThumb` in the card
head) and lists all of one monitor's switches in a `MonitorCard` (`LabelSwitch` tiles). Lock clock = lock glyph, desktop clock = desktop glyph
(`Icons.desktop`) wherever both appear. A row a per-monitor state dims shows why (`OffMark`: an eye-slash "Off" on its section head). A button
with a glyph = `Btn.glyph`, never the glyph inside `text` (the text font has none); an icon-only button names itself with `Btn.tip`.

**Monitor section** (`MonitorSection`): one unit, one layout on every page; the pages only turn options on. Two channels, never
mixed: the FILL says which monitor the page edits (the gliding `accentFill` marker, as `Segmented`), the GLYPH says on / off (accent eye /
muted eye-slash, as a bar chip's icon). A third device, the BRIDGE, says "these two are one" (`MonitorLink`). No knobs, no words beyond
the names and "All"; nothing above it, nothing under it: the page title, the unit, then the first section head (`topMargin` 6).
- Place: the page's first row (Wallpaper, Bar, Lock screen, Desktop clock; the smart gaps row of Shape), full width, chips `rowH` (44 px)
  tall, all the same width (the widest name, capped at 240) on a constant 28 px seam, so a monitor's chip sits at the same place on
  every page whether or not the page links; "All" and the page actions at the row's right end. A page never repeats the unit's state in
  words (no "linked" in a section head).
- Chip anatomy (`MonitorChip`, a split chip): BODY = wallpaper still in the monitor's aspect (`MonitorThumb`, 26 px), name (model, else
  connector) over the connector, `PrimaryTag` dot, optional accent badge (`markFor`: the palette source); STATE CELL (`MonitorStateCell`) at
  the end behind a hairline on switchable pages. Padding: `padSm` from the chip edge to the still and from the last body item to the
  hairline; the cell is a `rowH` square with its glyph centred (the "All" tile the same: `padSm` around glyph + label, then the cell). A cut name shows in full on hover. Narrow window: "All" and the actions move under the
  chips; chips that no longer fit compact (still + a few letters + cell) wrap onto a second row (a row break has no seam).
- Click the body = the monitor this page edits: the marker glides there; shared across pages (`Monitors.selected`) while Settings is open.
- `switchable` (a per-monitor on / off: bar, lock clock, desktop clock): the cell is the switch (click = `switched(screen, want)` through the
  feature's single setter, never flipped locally); the tooltip says what it does ("Hide bar on X"); an off monitor's body dims
  (`disabledOpacity`) but it stays selectable; a cell that cannot change shows a lock (the last bar) with the reason in its tooltip. "All"
  = a `LabelSwitch` tile (feature glyph, "All", the same cell) at the strip's end; `allTip` is its hover note. `glyphOn` / `glyphOff` change
  the pair for a page whose state is not "shown" (Shape smart gaps: the window glyph). No separate "Show" rows.
- `linkable` (relations: Wallpaper, Bar): a `MonitorLink` bridge fills the seam between neighbours: a plain chain glyph in the middle
  (no pill, border or fill); linked = accent glyph with an accent connector line from each chip edge to it (the two read as one), not
  linked = the glyph alone in faint fg (40 %) that brightens on hover (80 %); the whole seam clicks, the tooltip names the pair ("Link A and B" / "Unlink …"). Chips linked to the
  picked one get the accent outline without the fill. A pair split by a row break has no seam: both chips show a chain badge after
  the name instead (state only; widen the window to change it).
- Actions (`MonitorAction` children: Follow primary, Use for palette, Copy layout from): chip-tall square glyph buttons, name in `tip`, no
  text (text only where glyphs alone cannot tell two apart: copy from one of several monitors).
- `selectable: false`: a switch list without selection (Shape smart gaps): the whole chip is the switch, same look (the glyph carries
  the state, the body dims while off, no fill: fill means selection).
- Hover on a chip's body: a cut name in full and the word "Primary" for the primary (its dot alone says nothing).
- One monitor: hidden, except `showSingle` + switchable pages (lock / desktop clock) show that chip with its cell, no tag, no "All".
- Keyboard: Tab focuses the strip (ring), Left / Right pick, Space / Enter / T toggle the picked chip's cell; Tab reaches "All", the link
  buttons and the actions (Space / Enter).
- The same cell is the per-monitor switch on the Monitors page card (`MonitorCard` > `LabelSwitch` tiles), so "eye = shown on this
  monitor" reads the same everywhere; `OffMark` (eye-slash "Off") on the dimmed sections below is its echo.
- Adding a per-monitor page: `MonitorSection {}` first (+ `switchable` / `onFor` / `onSwitched` / `allOn` / `onAllSwitched` / `allIcon` if it
  has an on / off, through the feature's single setters; `switchEnabledFor` / `switchTipFor` for a locked state), read `Monitors.selected`
  (key via `Appearance.monitorKey`), dim the rows below with `OffMark` on their heads while the picked monitor is off. Never a second
  monitor list, switch row or `Toggle` for a per-monitor state.
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
- **Something under the windows** (wallpaper backend `engine`): a per-monitor visual goes into `EngineWindow.qml`, above
  `paper` when it should refract / sample the wallpaper (sample `paper` itself with a `ShaderEffectSource` limited to its
  rect, as the desktop clock's `backdrop`; never a copy of the wallpaper or a second player); engine-wide state and IPC in
  `engine.qml`. The engine does not hot-reload: `theme.py wallpaper-engine restart` (config/theme/README.md "Wallpaper engine").
- **Checking a change:** nested Hyprland (AGENTS.md), screenshots of the user's saved look first, then dark / light, the three
  bar looks, a bright / dark / busy wallpaper, the glass presets and the stock shim; `qmllint` clean against the baseline.
