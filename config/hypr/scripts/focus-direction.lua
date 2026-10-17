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
-- otherwise a distance score where lower = closer/more directly aligned, plus
-- whether it's within a 45-degree cone of the direction (perpendicular
-- offset no bigger than the primary one). Without the cone check, a floating
-- window sitting mostly to the SIDE (e.g. a pinned PIP) can still out-score a
-- window that's genuinely further away but properly in-line - e.g. one on an
-- adjacent monitor - because the perpendicular penalty (2x) isn't enough to
-- offset a big primary-axis gap like a monitor boundary.
local function score_of(ax, ay, window, spec)
	local cx, cy = center(window)
	local dx, dy = cx - ax, cy - ay
	local primary = spec.axis == "x" and dx or dy
	if primary * spec.sign <= 1 then
		return nil
	end
	local perpendicular = spec.axis == "x" and dy or dx
	local score = math.abs(primary) + math.abs(perpendicular) * 2
	local in_cone = math.abs(perpendicular) <= math.abs(primary)
	return score, in_cone
end

-- Lower tier = preferred. Squarely in-line beats merely "technically in
-- that direction", and a regular window beats a pinned overlay (PIP, OSK,
-- docks, ...) - those persist across every workspace/monitor so they'd
-- otherwise constantly outrank the actual window you're navigating to, just
-- for happening to sit a bit closer. Either dimension is only a tie-breaker.
-- A pinned/off-axis window is still reachable when it's the only candidate.
local function tier_of(in_cone, pinned)
	return (in_cone and 0 or 2) + (pinned and 1 or 0)
end

-- nil tier/score if `window` isn't in `spec`'s direction at all.
local function rank_of(ax, ay, window, spec)
	local score, in_cone = score_of(ax, ay, window, spec)
	if score == nil then
		return nil, nil
	end
	return tier_of(in_cone, window.pinned), score
end

local function find_candidate(active, ax, ay, spec)
	local best, best_score, best_tier = nil, math.huge, math.huge

	for _, w in ipairs(hl.get_windows()) do
		if w.address ~= active.address and w.mapped and w.visible and not w.hidden and is_visible(w) then
			local tier, score = rank_of(ax, ay, w, spec)
			if tier ~= nil and (tier < best_tier or (tier == best_tier and score < best_score)) then
				best_tier = tier
				best_score = score
				best = w
			end
		end
	end

	return best, best_tier, best_score
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
	local candidate, candidate_tier, candidate_score = find_candidate(active, ax, ay, spec)

	hl.dispatch(hl.dsp.focus({ direction = dir }))
	local moved = hl.get_active_window()

	local moved_tier, moved_score = nil, nil
	if moved ~= nil and moved.address ~= active.address then
		moved_tier, moved_score = rank_of(ax, ay, moved, spec)
	end

	local candidate_is_better = candidate ~= nil
		and (moved_tier == nil or candidate_tier < moved_tier or (candidate_tier == moved_tier and candidate_score < moved_score))

	if candidate_is_better then
		hl.dispatch(hl.dsp.focus({ window = "address:" .. candidate.address }))
	elseif moved_tier == nil and moved ~= nil and moved.address ~= active.address then
		-- Native moved somewhere invalid (wrapped, or off-axis with nothing
		-- better available) - revert rather than keep the bad move.
		hl.dispatch(hl.dsp.focus({ window = "address:" .. active.address }))
	end
end
