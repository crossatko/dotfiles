local host = require("hyprland.host")

if not host.is_workstation then
	return
end

local monitors = require("hyprland.monitors")
local monitor1 = monitors.primary
local monitor2 = monitors.secondary

-- Vertical videos: flush against the right edge of the main monitor, full height.
-- Also the width reserved for it there (see sync_reserved_areas below).
local VERTICAL_WIDTH = 866

-- Horizontal videos: the previous cw-pip/cw-mpv placement, bottom of the
-- secondary monitor. Also the height reserved for it there.
local HORIZONTAL_OFFSET = { x = 0, y = 1245 }
local HORIZONTAL_SIZE = { w = 1200, h = 675 }

-- The Twitch player (twitch-qs-mpv, a Quickshell FloatingWindow, class org.quickshell) has no title when it
-- opens, only the later window.title event carries "Twitch - <channel>"; it is treated like PiP/mpv then.
local function is_twitch(window)
	return window.class == "org.quickshell" and type(window.title) == "string" and window.title:find("^Twitch %- ") ~= nil
end

-- tuifin's mpv (--wayland-app-id=tuifin-mpv, so initial_class is NOT "mpv"). rules.lua sends it fullscreen to the
-- media workspace 11 (the TV's); that is right while the TV is connected. Without the TV it is handled like any mpv:
-- unfullscreen, float, placed + pinned by place().
local function is_tuifin(window)
	return window.initial_class == "tuifin-mpv" or window.class == "tuifin-mpv"
end

local function tv_connected()
	return hl.get_monitor(monitors.tv.output) ~= nil
end

local function is_pip_or_mpv(window)
	return window.title == "Picture in picture"
		or window.initial_class == "mpv"
		or is_twitch(window)
		or (is_tuifin(window) and not tv_connected())
end

-- Same rule as side-pin.lua (shared smart_applies: "No gaps for a single window" applies on the monitor, i.e. at most
-- one visible tiled window there): flush against the edges of the reserved area with rounding 0; otherwise the box
-- keeps the usual margins (12 top/bottom, 14 right for the vertical strip; 12 left/bottom for the bottom box) and
-- default rounding. `closing` = address of a window that is going away (not counted).
local side_pin = require("scripts.side-pin")
local MARGIN = 12
local MARGIN_RIGHT = 14
local closing_addr = nil

local function compute_target(window)
	local size = window.size
	if type(size) ~= "table" or not size.x or not size.y then
		return nil
	end

	if size.y > size.x then
		local mon = hl.get_monitor(monitor1.output)
		if mon == nil then
			return nil
		end
		local w, h = VERTICAL_WIDTH, mon.height
		if side_pin.smart_applies(mon, closing_addr) then
			return { output = monitor1.output, x = mon.x + mon.width - w, y = mon.y, w = w, h = h, flush = true }
		end
		return {
			output = monitor1.output,
			x = mon.x + mon.width - w - MARGIN_RIGHT,
			y = mon.y + MARGIN,
			w = w,
			h = h - 2 * MARGIN,
			flush = false,
		}
	end

	local mon = hl.get_monitor(monitor2.output)
	if mon == nil then
		return nil
	end
	local flush = side_pin.smart_applies(mon, closing_addr)
	local m = flush and 0 or MARGIN
	return {
		output = monitor2.output,
		x = mon.x + HORIZONTAL_OFFSET.x + m,
		y = mon.y + HORIZONTAL_OFFSET.y,
		w = HORIZONTAL_SIZE.w,
		h = HORIZONTAL_SIZE.h - m,
		flush = flush,
	}
end

-- Resize + move only, no workspace reassignment or pinning. Used to correct
-- the position after Hyprland clamps a pinned window inward due to a
-- reserved_area change (see replace_pip_or_mpv_on below) - redoing the pin
-- there would fight an in-progress unpin.
local function reposition(window, target)
	local selector = "address:" .. window.address
	hl.dispatch(hl.dsp.window.resize({ x = target.w, y = target.h, window = selector }))
	hl.dispatch(hl.dsp.window.move({ x = target.x, y = target.y, window = selector }))
	hl.dispatch(hl.dsp.window.set_prop({ prop = "rounding", value = target.flush and "0" or "unset", window = selector }))
end

local function place(window)
	local target = compute_target(window)
	if target == nil then
		return
	end

	local selector = "address:" .. window.address

	-- tuifin-mpv arrives fullscreen + tiled from its static rule: drop that first (state-aware, both dispatchers toggle)
	if is_tuifin(window) then
		for _, w in ipairs(hl.get_windows()) do
			if w.address == window.address then
				if w.fullscreen ~= nil and w.fullscreen ~= 0 and w.fullscreen ~= false then
					hl.dispatch(hl.dsp.window.fullscreen({ action = "toggle", window = selector }))
				end
				if not w.floating then
					hl.dispatch(hl.dsp.window.float({ action = "toggle", window = selector }))
				end
				break
			end
		end
	end

	-- Moving pixels alone (movewindowpixel across monitor bounds) does NOT
	-- reassign which monitor/workspace Hyprland thinks owns the window - it
	-- keeps rendering fine, but stays "attached" to wherever it spawned
	-- (visible in reserved-area/focus logic, and confirmed live: `monitor`
	-- stayed 0 indefinitely until manually dragged). Reassigning it to the
	-- target monitor's own workspace first fixes ownership; only then apply
	-- the exact pixel geometry, since the workspace move itself repositions
	-- the window too.
	local target_mon = hl.get_monitor(target.output)
	if target_mon ~= nil and target_mon.active_workspace ~= nil then
		hl.dispatch(hl.dsp.window.move({ window = selector, workspace = target_mon.active_workspace.id, silent = true }))
	end

	reposition(window, target)

	-- Pin last: pinning latches the window's monitor/workspace ownership to
	-- wherever it is at that moment. `pin` with action = true TOGGLES (verified live on 0.56.2: a second
	-- pin(true) on a pinned window unpins it), so only pin a window that is not pinned yet. A Twitch window
	-- whose title is already set at open is placed by window.open AND by its first window.title; the second
	-- call used to unpin it.
	local pinned = false
	for _, w in ipairs(hl.get_windows()) do
		if w.address == window.address then
			pinned = w.pinned
			break
		end
	end
	if not pinned then
		hl.dispatch(hl.dsp.window.pin({ window = selector, action = true }))
	end
end

-- Reserve screen space on each monitor so tiled windows never spawn/stretch
-- underneath a pinned window sitting there.
local function has_pinned_on_monitor(output)
	for _, w in ipairs(hl.get_windows()) do
		if w.pinned and w.monitor ~= nil and w.monitor.name == output then
			return true
		end
	end
	return false
end

local function count_tiled_on_visible_workspace(output)
	local mon = hl.get_monitor(output)
	if mon == nil or mon.active_workspace == nil then
		return 0
	end

	-- A group is ONE tiled node: count only its current (visible) member, like side-pin's smart_applies.
	-- Counting every member made a lone 2-tab group read as 2 windows and dropped the right strip.
	local workspace_id = mon.active_workspace.id
	local count = 0
	for _, w in ipairs(hl.get_windows()) do
		if not w.floating and w.workspace ~= nil and w.workspace.id == workspace_id then
			local g = w.group
			if g == nil or g.current == nil or g.current.address == w.address then
				count = count + 1
			end
		end
	end
	return count
end

-- Hyprland clamps floating windows to stay inside a monitor's working area:
-- when reserved_area grows, any window overlapping the newly-reserved zone
-- gets pushed inward - but it's never pushed back out when the area shrinks
-- again. Since the PiP/mpv box is deliberately placed flush against that
-- boundary, any reserved-area change corrupts its position. Repositioning it
-- right after undoes that clamp. Only touches windows still pinned - if the
-- user just unpinned it, leave it alone.
local function replace_pip_or_mpv_on(output)
	for _, w in ipairs(hl.get_windows()) do
		if is_pip_or_mpv(w) and w.pinned and w.monitor ~= nil and w.monitor.name == output then
			local target = compute_target(w)
			if target ~= nil then
				reposition(w, target)
			end
		end
	end
end

local function set_reserved(monitor_spec, edge, amount)
	local current = monitor_spec.reserved_area
	if current ~= nil and current[edge] == amount then
		return
	end

	local reserved_area = { top = 0, right = 0, bottom = 0, left = 0 }
	reserved_area[edge] = amount
	monitor_spec.reserved_area = reserved_area
	hl.monitor(monitor_spec)

	replace_pip_or_mpv_on(monitor_spec.output)
end

-- Main monitor: reserve a right-edge strip (matching the vertical PiP box
-- width) whenever a pinned window sits there, or whenever there's exactly 1
-- tiled window on the visible workspace (so a lone window doesn't stretch
-- full ultrawide width). 2+ tiled windows with no pinned window -> full width.
local function sync_monitor1_reserved_area()
	local reserve = has_pinned_on_monitor(monitor1.output) or count_tiled_on_visible_workspace(monitor1.output) <= 1
	set_reserved(monitor1, "right", reserve and VERTICAL_WIDTH or 0)
end

-- Secondary monitor: reserve a bottom strip (matching the horizontal PiP box
-- height) only while a pinned window actually sits there. Any number of
-- ordinary tiled windows with no pinned window -> no reservation.
local function sync_monitor2_reserved_area()
	local reserve = has_pinned_on_monitor(monitor2.output)
	set_reserved(monitor2, "bottom", reserve and HORIZONTAL_SIZE.h or 0)
end

local function sync_reserved_areas()
	sync_monitor1_reserved_area()
	sync_monitor2_reserved_area()
end

-- Hyprland drags a pinned window's workspace (and then monitor) ownership along when a workspace
-- on the OTHER monitor is activated (see switch-workspace.lua, which only guards the focused case):
-- the box then jumps to the primary monitor on a later switch. Heal like pip-reserve.lua does:
-- unpin, move to the target monitor's active workspace, exact geometry, pin last.
local healing = false
local function heal_pinned()
	if healing then
		return
	end
	for _, w in ipairs(hl.get_windows()) do
		if is_pip_or_mpv(w) and w.pinned and w.monitor ~= nil then
			local target = compute_target(w)
			local mon = target and hl.get_monitor(target.output)
			if mon ~= nil and mon.active_workspace ~= nil then
				local ws_mon = w.workspace ~= nil and w.workspace.monitor ~= nil and w.workspace.monitor.name or nil
				if w.monitor.name ~= mon.name or (ws_mon ~= nil and ws_mon ~= mon.name) then
					healing = true
					local selector = "address:" .. w.address
					hl.dispatch(hl.dsp.window.pin({ window = selector, action = false }))
					hl.dispatch(hl.dsp.window.move({ window = selector, workspace = mon.active_workspace.id, silent = true }))
					reposition(w, target)
					hl.dispatch(hl.dsp.window.pin({ window = selector, action = true }))
					healing = false
				end
			end
		end
	end
end

-- Re-fit pinned boxes whenever the tiled-window count (flush vs margins) can have changed. Only moves a box
-- whose geometry differs, so it does not feed back into its own events. Skips side-pin windows (own fit).
local refitting = false
local function refit_boxes(exclude)
	if refitting or healing then
		return
	end
	refitting = true
	closing_addr = exclude
	pcall(function()
		for _, w in ipairs(hl.get_windows()) do
			if is_pip_or_mpv(w) and w.pinned and w.address ~= exclude and not side_pin.tagged(w) then
				local t = compute_target(w)
				if t ~= nil and w.size ~= nil and w.at ~= nil then
					local cur = w.monitor ~= nil and w.monitor.name or nil
					local mon = hl.get_monitor(t.output)
					if mon ~= nil and cur == mon.name and (w.size.x ~= t.w or w.size.y ~= t.h or w.at.x ~= t.x or w.at.y ~= t.y) then
						reposition(w, t)
					end
				end
			end
		end
	end)
	closing_addr = nil
	refitting = false
end

local function sync_and_fit(exclude)
	sync_reserved_areas()
	refit_boxes(exclude)
end

hl.on("window.open", function(window)
	if is_pip_or_mpv(window) then
		place(window)
	end
	sync_and_fit()
end)

-- Twitch player: place it once, when its title first shows up (see is_twitch). Later title changes
-- (the user may have moved/unpinned it) are left alone.
local twitch_placed = {}
hl.on("window.title", function(window)
	if window == nil or not is_twitch(window) or twitch_placed[window.address] then
		return
	end
	twitch_placed[window.address] = true
	place(window)
	sync_and_fit()
end)

-- window.close doesn't fire for every way a window can disappear - confirmed
-- live: killing a pinned window left its monitor's reservation stuck on
-- until a manual reload. Cover the other teardown events too.
hl.on("window.close", function(window)
	if window ~= nil then
		twitch_placed[window.address] = nil
	end
	sync_and_fit(window ~= nil and window.address or nil)
end)
hl.on("window.kill", function(window)
	sync_and_fit(window ~= nil and window.address or nil)
end)
hl.on("window.destroy", function(window)
	sync_and_fit(window ~= nil and window.address or nil)
end)
hl.on("window.pin", function() sync_and_fit() end)
hl.on("window.move_to_workspace", function() sync_and_fit() end)
hl.on("window.fullscreen", function() sync_and_fit() end)
-- Grouping has no event of its own (group.toggle, group:add, move into / out of a group); Hyprland
-- re-evaluates the window rules on each such change, so window.update_rules is the hook. It also fires on
-- focus and other changes: set_reserved and refit_boxes are no-ops when nothing changed.
hl.on("window.update_rules", function() sync_and_fit() end)
hl.on("workspace.active", function()
	heal_pinned()
	sync_and_fit()
end)

sync_and_fit()
