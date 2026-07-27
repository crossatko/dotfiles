local host = require("hyprland.host")
local monitors = require("hyprland.monitors")

local TV_OUTPUT = monitors.tv.output
local GAME_WORKSPACE = "9"
local RESTORE_BRIGHTNESS = 80
local DIM_BRIGHTNESS = 1
local DIM_WALLPAPER = "~/.config/hypr/black.png"
local DEFAULT_WALLPAPER = "~/.config/hypr/nier.jpg"

-- Temporary diagnostic logging while chasing the TV-wake input-switch race
-- -- remove once root-caused for good.
local function debug_log(msg)
	os.execute("echo \"$(date +%s.%N) LUA: " .. msg .. "\" >> ~/.local/state/androidtv-remote/poll-debug.log")
end

-- DP connector-to-I2C-bus enumeration on this GPU/driver isn't guaranteed
-- stable across boots, so the bus number is resolved by EDID model match
-- rather than hardcoded (see scripts/ddc-bus.sh).
local function resolve_ddc_bus(model)
	local p = io.popen("bash ~/.config/hypr/scripts/ddc-bus.sh " .. model .. " 2>/dev/null")
	if not p then
		return nil
	end
	local out = (p:read("*a") or ""):gsub("%s+", "")
	p:close()
	return tonumber(out)
end

-- On the battlestation GPU, enabling/disabling the TV's DRM output (see
-- enable_tv_monitor/disable_tv_monitor) has been observed to shift the other
-- monitors' i2c-dev bus numbers -- confirmed live: the Dell drifted from
-- /dev/i2c-6 to /dev/i2c-9 mid-session with no reboot or cable change, right
-- after a TV enable/disable cycle. Resolving once at load time and caching
-- would silently break brightness dim/restore for a monitor from that point
-- on, with no visible error (ddc-set-brightness.sh is fired detached with
-- stderr discarded). Resolving fresh on every call is the only way that
-- stays correct across such a shift.
local ddc_bus_models = {}
local static_ddc_buses = {}
if host.is_battlestation then
	ddc_bus_models = { "MPG271QX", "U2515H" }
elseif host.is_workstation then
	static_ddc_buses = { 8, 6 }
end

local dimmed = nil
local last_gate_reason = nil

local function current_ddc_buses()
	if #ddc_bus_models > 0 then
		local buses = {}
		for _, model in ipairs(ddc_bus_models) do
			local bus = resolve_ddc_bus(model)
			if bus then
				table.insert(buses, bus)
			end
		end
		return buses
	end
	return static_ddc_buses
end

local function set_external_brightness(level)
	for _, bus in ipairs(current_ddc_buses()) do
		hl.exec_cmd("bash ~/.config/hypr/scripts/ddc-set-brightness.sh " .. bus .. " " .. level .. " >/dev/null 2>&1 &")
	end
end

local function restart_hypridle()
	hl.exec_cmd("systemctl --user restart hypridle >/dev/null 2>&1")
end

local function switch_tv_input(target)
	debug_log("switch_tv_input(" .. target .. ") firing hl.exec_cmd")
	hl.exec_cmd("~/.config/hypr/scripts/tv-input.sh " .. target .. " >/dev/null 2>&1 &")
end

local function is_tv_connected()
	return hl.get_monitor(TV_OUTPUT) ~= nil
end

-- is_tv_connected() only reflects our OWN decision to enable the Hyprland
-- output, not whether the physical TV is actually reachable -- checked
-- separately here so opening Big Picture while the TV is off doesn't still
-- dim the other displays for a TV session that can't actually happen.
--
-- This must NEVER call `adb connect` directly from here: that blocks for
-- however long the OS takes to time out an unreachable host (many seconds),
-- and since this runs inside Hyprland's own Lua execution, a direct network
-- call previously froze the entire compositor while the TV was off. Instead
-- read scripts/tv-input-poll.sh's cached result -- a local file read/stat,
-- never touching the network from here -- treating anything older than 10s
-- (a few missed 3s poll cycles) as unreliable and defaulting to unreachable.
local function is_tv_reachable()
	local path = os.getenv("HOME") .. "/.local/state/androidtv-remote/reachable"
	local p = io.popen(
		'f="'
			.. path
			.. '"; if [ -f "$f" ] && [ $(( $(date +%s) - $(stat -c %Y "$f" 2>/dev/null || echo 0) )) -lt 10 ]; then cat "$f"; else echo 0; fi'
	)
	if not p then
		return false
	end
	local out = (p:read("*a") or ""):gsub("%s+", "")
	p:close()
	return out == "1"
end

-- Used to go through hl.send_shortcut (a synthesized ALT+e/ALT+z keypress,
-- matching the real keybinds in binds.lua) instead of dispatching
-- hl.dsp.focus directly, because a plain dispatch didn't reliably make
-- XWayland-hosted Steam/Proton windows pick up real input focus (same
-- quirk documented in steam-streaming.lua's refocus_stream_workspace) --
-- Hyprland's own idea of the focused window and XWayland's X11-level input
-- focus can drift apart without an actual keypress through the real input
-- pipeline. But hl.send_shortcut is nil outside a native event callback --
-- exactly the context hypr_tv_dim_force_resync() runs in when invoked via
-- `hyprctl eval` from tv-wake-and-resync.sh/tv-input-poll.sh -- so this
-- silently no-opped every time enable_tv_monitor() ran from there, leaving
-- the TV correctly on the right workspace/monitor but never actually
-- focused (confirmed live: gamescope's window is native Wayland, not
-- XWayland, so it doesn't have that X11-level drift -- hl.dispatch alone
-- correctly moves Hyprland's own focus AND updates `hyprctl activewindow`,
-- confirmed live from the exact same external context this needed to work
-- from). Still hopping through workspace 7 first (not straight to 9) --
-- it always has Discord open, so there's reliably a real window to focus
-- mid-hop, which is what actually triggers Hyprland's focus-tracking to
-- update rather than a same-workspace no-op.
local function refocus_game_workspace()
	hl.dispatch(hl.dsp.focus({ workspace = 7 }))
	hl.dispatch(hl.dsp.focus({ workspace = tonumber(GAME_WORKSPACE) }))
end

-- The TV otherwise stays "connected" to Hyprland at all times (it never drops
-- HDMI hot-plug-detect even when powered off), so it's kept disabled here and
-- only enabled for the duration of an actual Steam Big Picture session. The
-- game workspace's monitor binding must move dynamically with it -- a static
-- `monitor = ...` window rule is only evaluated once at config load, before
-- the TV is ever enabled.
local function enable_tv_monitor()
	debug_log("enable_tv_monitor called")
	local spec = { disabled = false }
	for k, v in pairs(monitors.tv) do
		spec[k] = v
	end
	hl.monitor(spec)
	hl.exec_cmd("hyprctl dispatch moveworkspacetomonitor " .. GAME_WORKSPACE .. " " .. TV_OUTPUT)
	hl.workspace_rule({
		workspace = GAME_WORKSPACE,
		monitor = TV_OUTPUT,
		layout = "monocle",
		no_border = true,
		no_rounding = true,
		gaps_in = 0,
		gaps_out = 0,
	})
	refocus_game_workspace()
end

local function disable_tv_monitor()
	debug_log("disable_tv_monitor called")
	hl.exec_cmd("hyprctl dispatch moveworkspacetomonitor " .. GAME_WORKSPACE .. " " .. monitors.primary.output)
	hl.workspace_rule({
		workspace = GAME_WORKSPACE,
		monitor = monitors.primary.output,
		layout = "monocle",
		no_border = true,
		no_rounding = true,
		gaps_in = 0,
		gaps_out = 0,
	})
	hl.monitor({ output = TV_OUTPUT, disabled = true })
end

-- Keyed specifically off Steam's own Big Picture window, not a broader
-- process heuristic: a leftover/orphaned "steam -tenfoot" process can outlive
-- the session it belonged to (seen in practice), and matching on process
-- flags alone falsely kept treating that as still active. It's also the
-- literal trigger the user wants -- entering/leaving Big Picture -- so
-- manually enabling the TV for something else is left alone rather than
-- fought.
--
-- Matches on initial_class/initial_title, not the current class/title:
-- rules.lua's own pre-existing Big Picture rule does the same, because the
-- current title can go stale/change during Steam's shutdown sequence --
-- that's what silently broke the window.close-triggered restore when fully
-- quitting Steam (open was always detected fine, close wasn't).
-- Checks class/title AND initial_class/initial_title independently, not one
-- preferred over the other: a plain Steam window's current title can go
-- stale during shutdown (only initial_title stays reliable then), but a
-- gamescope-wrapped session (scripts/../../Applications/steamtv.sh) is the
-- opposite -- it maps as initial_class/initial_title "gamescope" and only
-- gets its real title ("Steam Big Picture Mode") once Steam actually starts
-- inside it, so only the *current* title is ever correct there. Preferring
-- either field over the other breaks one of the two cases.
local function is_big_picture_window(win)
	local class_a = (win.class or ""):lower()
	local class_b = (win.initial_class or ""):lower()
	local title_a = (win.title or ""):lower()
	local title_b = (win.initial_title or ""):lower()
	local class_ok = class_a:find("steam", 1, true) ~= nil or class_a == "gamescope"
		or class_b:find("steam", 1, true) ~= nil or class_b == "gamescope"
	local title_ok = title_a:find("big picture", 1, true) ~= nil or title_a:find("gamepadui", 1, true) ~= nil
		or title_b:find("big picture", 1, true) ~= nil or title_b:find("gamepadui", 1, true) ~= nil
	return class_ok and title_ok
end

local function is_game_window(win)
	return (win.class or ""):match("^steam_app_%d+$") ~= nil
end

local function is_big_picture_active()
	for _, win in ipairs(hl.get_windows()) do
		if is_big_picture_window(win) then
			return true
		end
	end
	return false
end

local function set_wallpaper(wallpaper)
	for _, mon in pairs(monitors) do
		hl.exec_cmd('hyprctl hyprpaper wallpaper "' .. mon.output .. "," .. wallpaper .. '"')
	end
end

local function set_gate_reason(reason)
	if reason == last_gate_reason then
		return
	end
	last_gate_reason = reason

	-- if reason then
	-- 	hl.notification.create({ text = "steam-tv-dim idle: " .. reason, timeout = 3000 })
	-- end
end

local function apply_dim()
	debug_log("apply_dim called (-> switch_tv_input hdmi2)")
	set_external_brightness(DIM_BRIGHTNESS)
	set_wallpaper(DIM_WALLPAPER)
	switch_tv_input("hdmi2")
	hl.notification.create({ text = "Steam Big Picture on TV: dimmed other displays", timeout = 2500 })
end

local function apply_restore(show_notification)
	debug_log("apply_restore called (-> switch_tv_input home)")
	set_external_brightness(RESTORE_BRIGHTNESS)
	restart_hypridle()
	set_wallpaper(DEFAULT_WALLPAPER)
	switch_tv_input("home")
	if show_notification then
		hl.notification.create({ text = "Restored display brightness + restarted hypridle", timeout = 2500 })
	end
end

local function sync_dim_state()
	if #ddc_bus_models == 0 and #static_ddc_buses == 0 then
		set_gate_reason("no ddc buses configured (host='" .. (host.raw or "") .. "')")
		return
	end

	local big_picture = is_big_picture_active()
	local tv = is_tv_connected()
	-- Always re-verified, not just when tv is false: Hyprland's own
	-- "enabled" state never knows when the physical TV loses power on its
	-- own (HPD doesn't drop even when it's off -- the original reason this
	-- whole TV-disable mechanism exists), so `tv` alone can be stale-true
	-- long after the real TV went dark outside of disable_tv_monitor()'s
	-- own path.
	local reachable = is_tv_reachable()
	debug_log(
		"sync_dim_state ENTER big_picture="
			.. tostring(big_picture)
			.. " tv="
			.. tostring(tv)
			.. " reachable="
			.. tostring(reachable)
			.. " dimmed="
			.. tostring(dimmed)
	)

	if big_picture and not reachable and tv then
		-- Was connected and just went unreachable: a genuine "it just
		-- turned off" transition (possibly the user deliberately turning
		-- it off mid-session) -- disable and respect that. Deliberately
		-- NOT attempting a wake here: that used to run unconditionally on
		-- any big_picture+unreachable state, which meant turning the TV
		-- off while Big Picture was running immediately fired a WoL packet
		-- right back at it, fighting the user's own action.
		disable_tv_monitor()
		tv = false
	elseif big_picture and not reachable and not tv then
		-- Never was connected (e.g. Big Picture just opened while the TV
		-- was already off): proactively wake it rather than just giving
		-- up. Fires a detached background script (never blocking here --
		-- a raw network call inside Hyprland's own Lua execution already
		-- froze the whole compositor once) that just sends a WoL packet --
		-- nothing more. Detecting when the TV actually comes back online
		-- and completing enable/dim/switch is entirely tv-input-poll.sh's
		-- job; this script used to ALSO do that itself, which raced with
		-- the poller's own transition-triggered resync and left the TV's
		-- input framework in limbo (confirmed via debug logging).
		hl.exec_cmd("bash ~/.config/hypr/scripts/tv-wake-and-resync.sh >/dev/null 2>&1 &")
	elseif big_picture and reachable and not tv then
		enable_tv_monitor()
		tv = true
	end

	local should_dim = tv and reachable and big_picture

	if should_dim then
		set_gate_reason(nil)
		if dimmed ~= true then
			apply_dim()
			dimmed = true
		end
		return
	end

	set_gate_reason("tv=" .. tostring(tv) .. ", big_picture=" .. tostring(big_picture))
	if dimmed ~= false then
		apply_restore(dimmed == true)
		dimmed = false
	end

	if tv and not big_picture then
		disable_tv_monitor()
	end
end

-- Deliberately event-driven only (no polling timer, no monitor.added/removed
-- hooks): those would re-run this on every unrelated window/monitor event
-- and fight a manual TV enable done outside of a Big Picture session. Gated
-- to Steam's main window class so entering/leaving Big Picture (and quitting
-- Steam entirely) is the only thing that triggers a change.
hl.on("hyprland.start", sync_dim_state)

-- A short one-shot delay, not a recurring poll: at the exact instant a
-- window opens or closes, its title (checked by is_big_picture_window,
-- inside is_big_picture_active) isn't reliably settled yet for this
-- Xwayland app -- unlike the window class, which is set before mapping and
-- is safe to check immediately. Re-scanning fresh via sync_dim_state()
-- after a brief settle, rather than trusting the event's own window
-- argument, is what actually catches Big Picture opening/closing reliably.
local function schedule_dim_sync(source)
	debug_log("schedule_dim_sync scheduled from " .. source)
	hl.timer(sync_dim_state, { timeout = 500, type = "oneshot" })
end

-- "steam" for a plain desktop-launched Big Picture, "gamescope" for the TV's
-- gamescope-wrapped session (scripts/../../Applications/steamtv.sh) -- both
-- class and initial_class checked independently, not one preferred over the
-- other, same reasoning as is_big_picture_window below. This is just the
-- gate for "is it worth bothering to check further" -- sync_dim_state's own
-- is_big_picture_active() does the real determination once scheduled.
local function is_steam_or_gamescope_class(win)
	local class_a = (win.class or ""):lower()
	local class_b = (win.initial_class or ""):lower()
	return class_a == "steam" or class_a == "gamescope" or class_b == "steam" or class_b == "gamescope"
end

hl.on("window.open", function(win)
	if is_steam_or_gamescope_class(win) then
		schedule_dim_sync("window.open")
	end
end)

hl.on("window.close", function(win)
	if is_steam_or_gamescope_class(win) then
		schedule_dim_sync("window.close")
	end
end)

-- Purely a program -> workspace assignment, deliberately decoupled from
-- which display that workspace currently lives on -- enable/disable_tv_monitor
-- own that separately (workspace -> monitor binding only, never touching
-- which windows go where). A game doesn't need to know or care whether
-- workspace 9 is currently on the TV or the MSI monitor; it only needs to
-- reliably end up on workspace 9, in either case.
--
-- rules.lua's static "steam-game" window rule (class = "^steam_app_\d+$" ->
-- workspace "9") can miss entirely: Proton/Steam game windows often take a
-- moment after mapping to settle their final class, and a window rule is
-- evaluated once at that point -- if it's not "steam_app_<id>" yet, the
-- rule just never applies and the window falls onto whatever workspace was
-- previously focused (seen in practice: landed on the primary monitor's
-- own workspace instead of the TV). Actively correcting this after a
-- settle delay, not just hoping the static rule caught it -- unconditionally,
-- not just during a Big Picture session, since a normally-launched desktop
-- game is just as exposed to the same race.
local function ensure_game_on_workspace()
	for _, win in ipairs(hl.get_windows()) do
		if is_game_window(win) and tostring(win.workspace and win.workspace.id) ~= GAME_WORKSPACE then
			hl.dispatch(hl.dsp.window.move({ workspace = tonumber(GAME_WORKSPACE), window = "address:" .. win.address }))
			-- The controller-focus hop is a Big Picture-specific need (no
			-- keyboard/mouse to just click the window into focus), not a
			-- workspace-placement concern -- kept conditional here.
			if is_big_picture_active() then
				refocus_game_workspace()
			end
			return
		end
	end
end

hl.on("window.open", function()
	hl.timer(ensure_game_on_workspace, { timeout = 500, type = "oneshot" })
end)

-- Called externally via `hyprctl eval` from scripts/on-wake.sh. A sleep/wake
-- cycle can silently drift real hardware state (ddcutil brightness, DRM
-- output enablement) out from under the `dimmed` flag, so this forces a
-- full recompute instead of relying on the flag's last-known value, which
-- the regular edge-triggered sync_dim_state() would otherwise trust and
-- skip re-applying.
function hypr_tv_dim_force_resync()
	debug_log("hypr_tv_dim_force_resync CALLED (via hyprctl eval)")
	dimmed = nil
	sync_dim_state()
end

