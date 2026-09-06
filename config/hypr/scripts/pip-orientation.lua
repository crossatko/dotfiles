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

local function is_pip_or_mpv(window)
	return window.title == "Picture in picture" or window.initial_class == "mpv"
end

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
		return { output = monitor1.output, x = mon.x + mon.width - w, y = mon.y, w = w, h = h }
	end

	local mon = hl.get_monitor(monitor2.output)
	if mon == nil then
		return nil
	end
	return {
		output = monitor2.output,
		x = mon.x + HORIZONTAL_OFFSET.x,
		y = mon.y + HORIZONTAL_OFFSET.y,
		w = HORIZONTAL_SIZE.w,
		h = HORIZONTAL_SIZE.h,
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
end

local function place(window)
	local target = compute_target(window)
	if target == nil then
		return
	end

	local selector = "address:" .. window.address

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
	-- wherever it is at that moment.
	hl.dispatch(hl.dsp.window.pin({ window = selector, action = true }))
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

	local workspace_id = mon.active_workspace.id
	local count = 0
	for _, w in ipairs(hl.get_windows()) do
		if not w.floating and w.workspace ~= nil and w.workspace.id == workspace_id then
			count = count + 1
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

hl.on("window.open", function(window)
	if is_pip_or_mpv(window) then
		place(window)
	end
	sync_reserved_areas()
end)

-- window.close doesn't fire for every way a window can disappear - confirmed
-- live: killing a pinned window left its monitor's reservation stuck on
-- until a manual reload. Cover the other teardown events too.
hl.on("window.close", sync_reserved_areas)
hl.on("window.kill", sync_reserved_areas)
hl.on("window.destroy", sync_reserved_areas)
hl.on("window.pin", sync_reserved_areas)
hl.on("window.move_to_workspace", sync_reserved_areas)
hl.on("workspace.active", sync_reserved_areas)

sync_reserved_areas()
