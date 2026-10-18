-- Battlestation counterpart of pip-orientation.lua (which only runs on the workstation).
--
-- Pinned video windows (PiP, mpv, the Twitch player) live in a 16:9 box in the bottom-right of the
-- secondary monitor, on top of the bar. Tiled windows must never go under them, so the monitor's
-- right strip is reserved while such a window is on it.
--
-- This used to be a workspace rule (`m[..]w[p1-9]` with a right gap). It only matched the workspace
-- that *owns* the pinned window, and pinning latches that ownership to whatever workspace the window
-- had when it was pinned, so the strip silently did not exist on the other workspaces of the monitor
-- (tiled windows then ran full width under the video). reserved_area is per monitor, so it always
-- applies; the pinned window is found by its monitor, not its workspace.
local host = require("hyprland.host")

if not host.is_battlestation then
	return
end

local monitors = require("hyprland.monitors")
local monitor2 = monitors.secondary

local BOX = { w = 1588, h = 893 } -- 16:9, the width of the reserved strip

-- Bar height and floating gap come from hyprland/managed.lua (Settings -> Appearance); fallbacks = docked 40px bar.
local ok_managed, managed = pcall(require, "hyprland.managed")
if not ok_managed or type(managed) ~= "table" then
	managed = nil
end

-- The space a bottom bar takes off the screen edge: its height, plus the gap below it when it floats.
local function bar_reserve()
	if managed ~= nil then
		local ok, e = pcall(managed.get)
		if ok and type(e) == "table" and type(e.barReserve) == "number" then
			return e.barReserve
		end
	end
	return 40
end

-- Small-file read that cannot block on a FIFO or swallow a huge file (managed.lua); plain read as fallback.
local function read_state(path)
	if managed ~= nil and type(managed.read_small_file) == "function" then
		local ok, text = pcall(managed.read_small_file, path, 65536)
		return ok and text or nil
	end
	local f = io.open(path, "r")
	if f == nil then
		return nil
	end
	local text = f:read(65536)
	f:close()
	return text
end

-- Where is the bar on this monitor? Mirrors config/quickshell/BarConfig.qml: ~/.local/state/quickshell/bars.json
-- (keyed "<monitor model>|<serial>", the serial is usually empty there) with the pre-settings layout as the
-- fallback. Returns "top", "bottom" or "none". Lua has no JSON parser; the file is tiny and flat.
local FALLBACK = { ["DP-5"] = "bottom", ["DP-3"] = "bottom", ["Virtual-1"] = "bottom", ["HDMI-A-1"] = "top" }

local function bar_edge(mon)
	local text = read_state(os.getenv("HOME") .. "/.local/state/quickshell/bars.json")
	if text then
		-- Lua monitors have no `model` field, only a description ("Dell Inc. DELL U2515H 9X2VY5AK1D5L"), so
		-- match the key's model (and serial, when it has one) inside that
		local desc = mon.description or ""
		for key, body in text:gmatch('"([^"]+)"%s*:%s*(%b{})') do
			local model, serial = key:match("^(.-)|(.*)$")
			if model and model ~= "" and desc:find(model, 1, true) and (serial == "" or desc:find(serial, 1, true)) then
				if not body:find('"enabled"%s*:%s*true') then
					return "none"
				end
				return body:match('"edge"%s*:%s*"(%a+)"') == "top" and "top" or "bottom"
			end
		end
	end
	return FALLBACK[mon.name] or "none"
end

-- How far the box is lifted off the bottom edge: over a bottom bar (and its floating gap), flush with the
-- edge otherwise.
local function bottom_offset(mon)
	return bar_edge(mon) == "bottom" and bar_reserve() or 0
end

local function is_video_window(window)
	return window.title == "Picture in picture"
		or window.initial_class == "mpv"
		or (window.class == "org.quickshell" and type(window.title) == "string" and window.title:find("^Twitch %- ") ~= nil)
end

-- monitor2.output is a "desc:..." selector on this host, while windows report connector names (DP-5)
local function secondary()
	return hl.get_monitor(monitor2.output)
end

local function pinned_video_windows()
	local list = {}
	local mon = secondary()
	if mon == nil then
		return list
	end
	for _, w in ipairs(hl.get_windows()) do
		if w.pinned and is_video_window(w) and w.monitor ~= nil and w.monitor.name == mon.name then
			list[#list + 1] = w
		end
	end
	return list
end

-- Hyprland pushes a floating window inward when reserved_area grows over it and never pushes it back
-- when the area shrinks again, so put the box back where the window rules place it.
local function reposition(window)
	local mon = secondary()
	if mon == nil then
		return
	end
	local selector = "address:" .. window.address
	hl.dispatch(hl.dsp.window.resize({ x = BOX.w, y = BOX.h, window = selector }))
	hl.dispatch(hl.dsp.window.move({
		x = mon.x + mon.width - BOX.w,
		y = mon.y + mon.height - bottom_offset(mon) - BOX.h,
		window = selector,
	}))
end

-- Switching to a workspace on the OTHER monitor can drag a pinned window along to that monitor (Hyprland
-- does it after the dispatch returns, so scripts/switch-workspace.lua can only guard the keybind path;
-- the bar's workspace chips and anything else bypass it). This is the path-independent fix: any pinned
-- video window found off the secondary monitor is sent back to it.
local healing = false

local function heal()
	if healing then
		return
	end
	local mon = secondary()
	if mon == nil or mon.active_workspace == nil then
		return
	end
	local fixed = false
	for _, w in ipairs(hl.get_windows()) do
		if w.pinned and is_video_window(w) and w.monitor ~= nil and w.monitor.name ~= mon.name then
			-- Same order as place() in pip-orientation.lua: a pinned window keeps the monitor it was
			-- latched to however it is moved, so unpin, move to this monitor's workspace, set the exact
			-- geometry, and pin last (pinning latches ownership to wherever the window is then).
			healing = true
			local selector = "address:" .. w.address
			hl.dispatch(hl.dsp.window.pin({ window = selector, action = false }))
			hl.dispatch(hl.dsp.window.move({ window = selector, workspace = mon.active_workspace.id, silent = true }))
			reposition(w)
			hl.dispatch(hl.dsp.window.pin({ window = selector, action = true }))
			healing = false
			fixed = true
		end
	end
	return fixed
end

local last_offset = nil

-- Bar edge, height or floating gap changed (or first run): put every pinned video window back in the box
-- for the new layout.
local function refit()
	local mon = secondary()
	if mon == nil then
		return
	end
	local offset = bottom_offset(mon)
	if offset == last_offset then
		return
	end
	last_offset = offset
	for _, w in ipairs(pinned_video_windows()) do
		reposition(w)
	end
end

local function sync()
	if healing then
		return
	end
	heal()
	refit()
	local videos = pinned_video_windows()
	local want = #videos > 0 and BOX.w or 0
	local current = monitor2.reserved_area
	if current ~= nil and current.right == want then
		return
	end

	monitor2.reserved_area = { top = 0, right = want, bottom = 0, left = 0 }
	hl.monitor(monitor2)

	for _, w in ipairs(videos) do
		reposition(w)
	end
end

hl.on("window.open", function(w)
	-- the static window rules (rules.lua) assume a bottom bar; correct the box for the actual layout
	if w ~= nil and w.pinned and is_video_window(w) then
		reposition(w)
	end
	sync()
end)
-- window.close does not fire for every way a window can disappear (see pip-orientation.lua)
hl.on("window.close", sync)
hl.on("window.kill", sync)
hl.on("window.destroy", sync)
hl.on("window.pin", sync)
hl.on("window.move_to_workspace", sync)
hl.on("workspace.active", sync)

sync()

-- Called from Quickshell (config/quickshell/BarConfig.qml) right after the bar layout is saved, through
-- `hyprctl dispatch`, since Lua cannot watch the file: re-reads it and re-places the pinned windows.
-- layout_apply() (hyprland/managed.lua) calls it too after an Appearance change (floating bar / edge gap).
function pip_bar_changed()
	sync()
end
