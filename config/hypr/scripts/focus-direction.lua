-- hl.dsp.focus({ direction = ... }) (movefocus) only considers tiled windows
-- when the active window is tiled, and - confirmed live - two more failure
-- modes on top of that:
--   1. When there's no tiled window further in that direction, it doesn't
--      no-op, it cycles/wraps to another tiled window instead (repeatedly
--      dispatching direction="right" from the rightmost of 2 tiled windows
--      just bounces focus back and forth between them, forever).
--   2. When the ACTIVE window is floating/pinned, it seems to only consider
--      OTHER floating windows - it'll jump straight past a much closer tiled
--      window to reach a far, off-axis floating one, because that floating
--      window is technically (if not sensibly) "in that direction" too.
--
-- So neither "did focus change" nor "is native's target technically in the
-- right direction" is enough to detect native failure. Instead: compute our
-- own geometric candidate first (best-scored window - tiled, floating,
-- pinned - among all on any visible monitor/workspace), then after native
-- movefocus runs, score its result the same way and keep whichever is
-- actually closer. Revert to the original window if native lands somewhere
-- invalid and we have nothing better.
--
-- Hyprland reports window/monitor geometry in one global coordinate space
-- that already accounts for each monitor's position, scale and rotation, so
-- the same distance-based search works regardless of monitor count,
-- orientation, or layout - no per-monitor special-casing needed.

local DIRS = {
	left = { axis = "x", sign = -1 },
	right = { axis = "x", sign = 1 },
	up = { axis = "y", sign = -1 },
	down = { axis = "y", sign = 1 },
}

local function center(window)
	return window.at.x + window.size.x / 2, window.at.y + window.size.y / 2
end

-- A window is reachable if it's actually on screen right now: pinned windows
-- always are, others only if their workspace is the active one on their monitor.
local function is_visible(window)
	if window.pinned then
		return true
	end
	if window.monitor == nil or window.workspace == nil then
		return false
	end
	local active_workspace = window.monitor.active_workspace
	return active_workspace ~= nil and active_workspace.id == window.workspace.id
end

-- nil if `window` isn't actually in `spec`'s direction from (ax, ay);
-- otherwise a distance score where lower = closer/more directly aligned.
local function score_of(ax, ay, window, spec)
	local cx, cy = center(window)
	local dx, dy = cx - ax, cy - ay
	local primary = spec.axis == "x" and dx or dy
	if primary * spec.sign <= 1 then
		return nil
	end
	local perpendicular = spec.axis == "x" and dy or dx
	return math.abs(primary) + math.abs(perpendicular) * 2
end

local function find_candidate(active, ax, ay, spec)
	local best, best_score = nil, math.huge

	for _, w in ipairs(hl.get_windows()) do
		if w.address ~= active.address and w.mapped and w.visible and not w.hidden and is_visible(w) then
			local score = score_of(ax, ay, w, spec)
			if score ~= nil and score < best_score then
				best_score = score
				best = w
			end
		end
	end

	return best, best_score
end

return function(dir)
	local spec = DIRS[dir]
	if spec == nil then
		hl.dispatch(hl.dsp.focus({ direction = dir }))
		return
	end

	local active = hl.get_active_window()
	if active == nil then
		hl.dispatch(hl.dsp.focus({ direction = dir }))
		return
	end

	local ax, ay = center(active)
	local candidate, candidate_score = find_candidate(active, ax, ay, spec)

	hl.dispatch(hl.dsp.focus({ direction = dir }))
	local moved = hl.get_active_window()

	local moved_score = nil
	if moved ~= nil and moved.address ~= active.address then
		moved_score = score_of(ax, ay, moved, spec)
	end

	if candidate ~= nil and (moved_score == nil or candidate_score < moved_score) then
		hl.dispatch(hl.dsp.focus({ window = "address:" .. candidate.address }))
	elseif moved_score == nil and moved ~= nil and moved.address ~= active.address then
		-- Native moved somewhere invalid (wrapped, or off-axis with nothing
		-- better available) - revert rather than keep the bad move.
		hl.dispatch(hl.dsp.focus({ window = "address:" .. active.address }))
	end
end
