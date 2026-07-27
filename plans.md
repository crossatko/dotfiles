# TV behavior: implementation + test plan

Maps every line in `tv-behavior.md` to what actually implements it and how to
verify it. Two concerns are kept deliberately decoupled throughout:

- **program -> workspace** (which workspace a window belongs on) -- owned by
  `rules.lua`'s window rules plus `scripts/steam-tv-dim.lua`'s
  `ensure_game_on_workspace()` correction. Never touches monitor placement.
- **workspace -> display** (which monitor workspace 9 currently lives on) --
  owned entirely by `enable_tv_monitor()`/`disable_tv_monitor()` in
  `scripts/steam-tv-dim.lua`. Never touches which windows are on it.

The TV itself has no CEC (this GPU doesn't expose `/dev/cec*`) and its HDMI
hot-plug-detect doesn't reflect input selection, so all TV hardware control
(input switching, power, reachability checks) goes over the network via ADB
(`scripts/tv-input.sh`) or the Android TV Remote protocol, never CEC/HPD.

## Section 1 -- Steam, not Big Picture

| Checklist item | Implementation |
|---|---|
| workspace 9 on msi monitor | `hyprland/workspaces.lua` binds workspace 9 to `monitor1.output` (MSI) by default at boot; `disable_tv_monitor()` explicitly rebinds it back there whenever Big Picture ends. |
| game launched is put on workspace 9 | `hyprland/rules.lua`'s static `steam-game` rule (`class = "^steam_app_\d+$"` -> `workspace = "9"`), backed by `ensure_game_on_workspace()` in `steam-tv-dim.lua`, which runs unconditionally on every `window.open` (not just during Big Picture) to correct the case where the rule missed because the window's class hadn't settled yet at map time. |

**Test**: with Big Picture closed and the TV off/uninvolved, launch a game
from the regular desktop Steam library. `hyprctl clients` should show it on
`workspace: 9`, `monitor: 0` (DP-2/MSI).

## Section 2 -- Steam Big Picture

| Checklist item | Implementation |
|---|---|
| tv on | `enable_tv_monitor()`, gated by `is_tv_reachable()` (real `adb connect` check -- not just "did we enable it ourselves") and `is_big_picture_active()` (matches Steam's Big Picture window by `initial_class`/`initial_title`, not the live `class`/`title`, which can be unsettled at open time). Triggered via `window.open`/`window.close` on Steam's main window class, through a 500ms one-shot settle-delay (`schedule_dim_sync`) before re-checking fresh state -- not a recurring poll. |
| tv input hdmi2 | `apply_dim()` -> `switch_tv_input("hdmi2")` -> `scripts/tv-input.sh hdmi2`, which sends the `content://android.media.tv/passthrough/...` intent over ADB, retrying for a few seconds since the network may not be instantly ready. |
| workspace 9 on tv | `enable_tv_monitor()`'s `hl.workspace_rule` + `moveworkspacetomonitor` call, plus monocle layout / no border / no rounding / zero gaps on workspace 9. |
| audio output tv | Independent of all of the above: `scripts/tv.lua` has its own `monitor.added` hook (`reconcile_tv_state` -> `handle_tv_connected` -> `enable_tv_audio`) that switches the default sink to the TV's HDMI audio output ("HDMI 4") whenever `HDMI-A-1` becomes enabled -- fires automatically as a side effect of `enable_tv_monitor()` enabling the output, no direct coupling needed. |
| steam big picture on workspace 9 | `rules.lua`'s `steam-big-picture-media-workspace` rule (`initial_title = "Steam Big Picture Mode"`, battlestation-only), `workspace = "9"`. |
| game launched on workspace 9 | Same mechanism as Section 1, plus `refocus_game_workspace()` (the ALT+e -> ALT+z workspace-hop trick, needed because a plain focus dispatch doesn't reliably work for Steam/Proton windows) -- gated specifically on `is_big_picture_active()`, since that's a controller-navigation need, not a workspace-placement one. |
| other displays dimmed | `apply_dim()` -> `set_external_brightness(1)` via `ddcutil` on the MSI/Dell buses (resolved by EDID model match through `ddc-bus.sh`, not hardcoded, since DP connector numbering isn't stable across boots) + `set_wallpaper` to the black placeholder. |

**Test** (TV already reachable):
1. Launch Big Picture (icon click or `steamtv.sh`).
2. Within ~1s (settle delay), check: `hyprctl monitors` lists `HDMI-A-1` at `3840x2160@120`; `hyprctl clients` shows the Big Picture window on `workspace: 9`, `monitor: 1`; `wpctl status` default sink is the TV's HDMI audio; `ddcutil --bus <msi> getvcp 0x10` and `--bus <dell>` both read `1`.
3. Confirm on the physical TV: input switched to HDMI2, picture showing.
4. Launch a game from Big Picture. Re-check `hyprctl clients` (workspace 9, monitor 1) and confirm controller input actually reaches the game, not Big Picture underneath it (`hyprctl activewindow` should be the game's class).
5. Quit the game back to Big Picture's menu -- confirm Big Picture's own window is still fullscreen (monocle layout doing its job, not a one-shot `fullscreen` rule that could've been dropped).

## Section 3 -- Steam Big Picture close

| Checklist item | Implementation |
|---|---|
| tv back to homescreen | `apply_restore()` -> `switch_tv_input("home")`. |
| workspace 9 back to msi monitor | `disable_tv_monitor()`'s `hl.workspace_rule` + `moveworkspacetomonitor` back to `monitors.primary.output`. |
| other displays restored | `apply_restore()` -> `set_external_brightness(80)` + default wallpaper + `hypridle` restart. |
| *(not itemized, but happens automatically)* audio reverts | `tv.lua`'s `monitor.removed` hook fires when `disable_tv_monitor()` disables `HDMI-A-1`, restoring whatever the default sink was before the TV connected. |

**Test**: quit Big Picture entirely (or quit Steam outright -- both must
work, see reliability notes below). Within ~1s: `hyprctl monitors` no longer
lists the TV output; `ddcutil getvcp 0x10` back to `80` on both buses;
`wpctl status` default sink back to the non-TV device; workspace 9 bound to
MSI again; TV itself shows its home launcher.

## Reliability notes (why the settle-delay / dynamic corrections exist)

- **Window properties aren't settled at map time** for these Proton/Xwayland
  windows. Static window rules evaluate once and never re-apply later even
  after the "correct" class arrives (confirmed empirically -- a misplaced
  game window did not self-correct even long after its class had settled).
  This is why detection uses `initial_class`/`initial_title` where possible,
  and why a 500ms one-shot re-check follows every relevant `window.open`/
  `window.close` instead of trusting the event's own window argument.
- **The `dimmed` flag can drift from real hardware state** if brightness/TV
  input is changed outside the normal code path (manual testing, the TV's
  own remote, etc.). `hypr_tv_dim_force_resync()` is the manual escape
  hatch (`hyprctl eval 'hypr_tv_dim_force_resync()'`); `on-wake.sh` calls it
  automatically after every sleep/wake cycle for the same reason.
- **DP/HDMI connector-to-port numbering isn't stable across boots or
  replugs** on this GPU/driver -- `ddc-bus.sh` resolves brightness control
  buses by EDID model match, not hardcoded numbers, and `monitors.lua`'s
  `tv.output` / `hyprpaper.conf` need manual updates if the TV is physically
  moved to a different port (as happened once already this session).

## End-to-end test procedure

1. **Baseline**: Steam fully closed, TV off. Confirm: TV output absent from
   `hyprctl monitors`; workspace 9 bound to MSI; brightness at 80 both
   buses; default wallpaper active.
2. **Section 1**: launch a game from the regular desktop Steam client (no
   Big Picture). Confirm it lands on workspace 9 / MSI monitor. Quit it.
3. **TV comes online independently of Big Picture**: wake the TV (WoL) and
   point it at HDMI2 manually. Confirm `tv-input-poll.sh` (via
   `tv-manual-connect.lua`) enables the Hyprland output on its own, with no
   dimming/workspace/audio side effects (those are Big-Picture-only).
   Switch the TV away from HDMI2 and confirm it disables again.
4. **Section 2**: open Big Picture. Walk through every row in the Section 2
   table in order, confirming each. Launch a game from Big Picture; confirm
   placement and controller focus.
5. **Section 3, normal path**: back out of Big Picture to the desktop
   Steam client (don't quit Steam). Confirm every row in the Section 3
   table.
6. **Section 3, quit-Steam path**: repeat step 4, then fully quit Steam
   instead of backing out. Confirm the same Section 3 results -- this path
   broke once already (close-detection relying on live `title` instead of
   `initial_title`) and needs its own explicit check every time this logic
   changes.
7. **Reachability gate regression**: with the TV off/unreachable, open Big
   Picture. Confirm nothing dims or attempts to switch input (should stay
   fully passive until the TV is actually reachable).
8. **Sleep/wake regression**: with Big Picture + a game active, sleep and
   wake the PC. Confirm `on-wake.sh` correctly re-applies dim + TV input
   state matching whatever's actually still running post-wake, not a stale
   pre-sleep flag.
9. **Port-move regression** (only after physically moving the TV cable):
   confirm `ddc-bus.sh`, `monitors.lua`'s `tv.output`, and `hyprpaper.conf`
   all still agree, and that Section 2/3 still pass end to end.
