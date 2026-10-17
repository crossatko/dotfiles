local host = require("hyprland.host")
local monitors = require("hyprland.monitors")

local STREAM_SINK_MATCH = "Steam Streaming Playback"
local STREAM_MONITOR = "HEADLESS-STREAM"
local STREAM_MODE = "1920x1080@60"
local STREAM_WORKSPACE = "9"

local RESTORE_BRIGHTNESS = 0
local DIM_BRIGHTNESS = 0
local DIM_WALLPAPER = "~/Pictures/wallpapers/black.png"
-- the restore target is whatever the theme currently has (changes with the picker)
local function default_wallpaper()
	local ok, palette = pcall(dofile, os.getenv("HOME") .. "/.config/theme/out/palette.lua")
	return (ok and palette.wallpaper) or "~/Pictures/wallpapers/black.png"
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

local ddc_buses = {}
if host.is_battlestation then
	local msi_bus = resolve_ddc_bus("MPG271QX")
	local dell_bus = resolve_ddc_bus("U2515H")
	if msi_bus then
		table.insert(ddc_buses, msi_bus)
	end
	if dell_bus then
		table.insert(ddc_buses, dell_bus)
	end
elseif host.is_workstation then
	ddc_buses = { 8, 6 }
end

local streaming = false

local function stop_hypridle()
	hl.exec_cmd("systemctl --user stop hypridle >/dev/null 2>&1")
end

local function resume_hypridle()
	hl.exec_cmd("systemctl --user restart hypridle >/dev/null 2>&1")
end

local function cmd_output(cmd)
	local handle = io.popen(cmd)
	if handle == nil then
		return ""
	end
	local result = handle:read("*a") or ""
	handle:close()
	return result:gsub("%s+", "")
end

local function is_stream_sink_active()
	return cmd_output("wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep -F '" .. STREAM_SINK_MATCH .. "'") ~= ""
end

local function get_media_output()
	local tv = monitors.tv
	if tv ~= nil and tv.output ~= nil and hl.get_monitor(tv.output) ~= nil then
		return tv.output
	end
	return monitors.primary.output
end

local function set_external_brightness(level)
	for _, bus in ipairs(ddc_buses) do
		hl.exec_cmd("ddcutil --bus " .. bus .. " setvcp 0x10 " .. level .. " >/dev/null 2>&1")
	end
end

local function set_wallpaper(wallpaper)
	for _, mon in pairs(monitors) do
		hl.exec_cmd('hyprctl hyprpaper wallpaper "' .. mon.output .. "," .. wallpaper .. '"')
	end
end

-- Third-party launcher windows (Ubisoft Connect, Epic, EA App, ...) share the
-- same steam_app_<id> class as the actual game, so they're excluded by title.
local NON_GAME_TITLES = {
	["ubisoft connect"] = true,
	["epic games launcher"] = true,
	["ea app"] = true,
	["battle.net"] = true,
	["gog galaxy"] = true,
}

local function is_game_window(win)
	local class = win.class or ""
	local title = win.title or ""

	if not (class:find("gamescope", 1, true) or class:find("steam_app_", 1, true)) then
		return false
	end

	-- Empty-title windows are transient placeholders (e.g. a taskbar-icon
	-- stand-in window some Proton/launcher apps spawn while loading), not
	-- the real game window, so they must not steal focus.
	if title == "" then
		return false
	end

	if NON_GAME_TITLES[title:lower()] then
		return false
	end

	return true
end

-- Neither an external `hyprctl dispatch` nor a native hl.dispatch(hl.dsp.focus)
-- call made the stream client pick up the game, even though Hyprland reported
-- the workspace/window focused the whole time -- only the user's actual
-- keypress did. Both of those dispatch the focus change directly, with no
-- real input event behind it. hl.send_shortcut instead synthesizes an actual
-- keyboard shortcut through Hyprland's real input pipeline, the same as a
-- physical keypress, which is what XWayland/Steam's own focus tracking
-- appears to require. Mirror the user's manual fix exactly: leave to another
-- workspace, then send the workspace-9 shortcut (ALT + z) to return.
local function refocus_stream_workspace()
	hl.send_shortcut({ mods = "ALT", key = "a" })
	hl.send_shortcut({ mods = "ALT", key = "z" })
end

local function focus_window_class(class)
	refocus_stream_workspace()
	hl.exec_cmd('hyprctl dispatch focuswindow "class:' .. class .. '"')
end

local function focus_game_window()
	for _, win in ipairs(hl.get_windows()) do
		if is_game_window(win) then
			focus_window_class(win.class)
			return
		end
	end
end

local function create_stream_monitor()
	hl.exec_cmd("hyprctl output create headless " .. STREAM_MONITOR .. " >/dev/null 2>&1")
	hl.monitor({ output = STREAM_MONITOR, mode = STREAM_MODE, position = "auto-right" })
end

local function remove_stream_monitor()
	hl.exec_cmd("hyprctl output remove " .. STREAM_MONITOR .. " >/dev/null 2>&1")
end

local function move_workspace_to(output)
	hl.exec_cmd("hyprctl dispatch moveworkspacetomonitor " .. STREAM_WORKSPACE .. " " .. output)
	hl.workspace_rule({ workspace = STREAM_WORKSPACE, monitor = output })
end

local function apply_stream_active()
	create_stream_monitor()
	move_workspace_to(STREAM_MONITOR)
	set_external_brightness(DIM_BRIGHTNESS)
	set_wallpaper(DIM_WALLPAPER)
	stop_hypridle()
	focus_game_window()
	hl.notification.create({ text = "Steam Streaming: displays dimmed, hypridle paused (no sleep)", timeout = 2500 })
end

local function apply_stream_inactive()
	move_workspace_to(get_media_output())
	remove_stream_monitor()
	set_external_brightness(RESTORE_BRIGHTNESS)
	set_wallpaper(default_wallpaper())
	resume_hypridle()
	hl.notification.create({ text = "Steam Streaming ended: displays + hypridle restored", timeout = 2500 })
end

local function sync_stream_state()
	if #ddc_buses == 0 then
		return
	end

	local active = is_stream_sink_active()
	if active and not streaming then
		streaming = true
		apply_stream_active()
	elseif not active and streaming then
		streaming = false
		apply_stream_inactive()
	end
end

hl.on("hyprland.start", sync_stream_state)
hl.timer(sync_stream_state, { timeout = 2000, type = "repeat" })

-- The stream client only shows the focused window, not the whole virtual
-- display, so any game window that spawns/respawns while streaming (e.g.
-- launched after the session already started, or relaunched mid-session)
-- must be explicitly focused or it never appears on the client.
hl.on("window.open", function(win)
	if streaming and is_game_window(win) then
		focus_window_class(win.class)
	end
end)
