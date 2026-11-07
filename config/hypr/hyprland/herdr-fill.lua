-- Herdr (workspace 4): alone, the window fills the whole monitor and the bar (top layer) draws over it. With a second tiled
-- window next to it, it is an ordinary tiled window again (gaps, rounding, border, below the bar).
-- A tiled window cannot do the first part: a negative gaps_out on the bar side is clamped to 0, so it never starts inside
-- the reserved strip. So a lone herdr floats at the monitor size; the "herdr-app-lone" rule in rules.lua squares it.
-- Other floating windows do not count. The state is read from the windows each time, so a reload loses nothing.
--
-- Rules of the script:
--  * Only a window this script floated carries the tag TAG (it survives a reload). Only tagged windows are ever un-floated or
--    resized; a Herdr the user floated is left alone.
--  * Floating and tiling go through a oneshot timer, never straight from an event: window.update_rules fires in the middle of
--    the layout's own setFloating, and a dispatch there adds the window to the layout twice. Events only queue work.
--  * Going to the lone, full-monitor state happens only on window.open / close / kill / destroy and moves between workspaces or
--    monitors, never on window.update_rules (that one can only send Herdr back to tiled). Dragging or floating a neighbour by
--    hand therefore leaves Herdr tiled until the next open or close. Limit: dragging a neighbour to the other monitor ends the
--    drag at the monitor edge (that move is a workspace change, so Herdr floats, and floating anything ends a drag).
local WS = 4
local CLASS = "herdr-app"
local TAG = "herdr-fill"

local function tagged(w)
	local ok, tags = pcall(function()
		return w.tags
	end)
	if ok and type(tags) == "table" then
		for _, t in ipairs(tags) do
			if t == TAG or t == TAG .. "*" then
				return true
			end
		end
	end
	return false
end

local function tag(sel, on)
	hl.dispatch(hl.dsp.window.tag({ tag = (on and "+" or "-") .. TAG, window = sel }))
end

-- Fit a floating Herdr to its monitor (logical size: the monitor's pixels divided by its scale).
local function fit(w)
	local mon = w.monitor
	if mon == nil then
		return
	end
	local scale = mon.scale
	if not scale or scale <= 0 then
		scale = 1
	end
	local width, height = mon.width / scale, mon.height / scale
	local sel = "address:" .. w.address
	if w.size.x ~= width or w.size.y ~= height then
		hl.dispatch(hl.dsp.window.resize({ x = width, y = height, window = sel }))
	end
	if w.at.x ~= mon.x or w.at.y ~= mon.y then
		hl.dispatch(hl.dsp.window.move({ x = mon.x, y = mon.y, window = sel }))
	end
end

-- full: may float a lone Herdr (open / close / workspace or monitor change). Always: tagged windows are un-floated when they
-- must be, and re-fitted. gone: addresses of windows that are closing.
local function settle(full, gone)
	local counted, herdrs = 0, {}
	local function here(w)
		return not gone[w.address] and w.workspace ~= nil and w.workspace.id == WS and w.mapped ~= false and w.hidden ~= true
	end
	for _, w in ipairs(hl.get_windows()) do
		if not gone[w.address] then
			if w.class == CLASS then
				herdrs[#herdrs + 1] = w
			end
			if here(w) and (w.class == CLASS or w.floating ~= true) then
				counted = counted + 1
			end
		end
	end
	for _, w in ipairs(herdrs) do
		local sel = "address:" .. w.address
		if w.fullscreen == 0 then
			if tagged(w) then
				if w.floating ~= true then
					tag(sel, false) -- tiled again by hand: let go of it
				elseif not here(w) or counted ~= 1 or w.group ~= nil then
					hl.dispatch(hl.dsp.window.float({ action = false, window = sel }))
					tag(sel, false)
					-- Herdr tiles after the window that joined it, so force_split = 2 put it on the right / bottom: swap
					-- them. The layout call acts on the focused window, so only when that is the newcomer, next to Herdr.
					local active = hl.get_active_window()
					if
						full
						and counted == 2
						and here(w)
						and active ~= nil
						and active.address ~= w.address
						and active.workspace ~= nil
						and active.workspace.id == WS
						and active.monitor ~= nil
						and w.monitor ~= nil
						and active.monitor.name == w.monitor.name
					then
						hl.dispatch(hl.dsp.layout("swapsplit"))
					end
				else
					fit(w)
				end
			elseif full and here(w) and counted == 1 and w.floating ~= true and w.group == nil then
				hl.dispatch(hl.dsp.window.float({ action = true, window = sel }))
				tag(sel, true)
				fit(w)
			end
		end
	end
end

local want_full, closing, queued = false, {}, false
local function queue(full, addr)
	want_full = want_full or full
	if addr ~= nil then
		closing[addr] = true
	end
	if queued then
		return
	end
	queued = true
	hl.timer(function()
		local full_now, gone = want_full, closing
		want_full, closing, queued = false, {}, false
		local ok, err = pcall(settle, full_now, gone)
		if not ok then
			error(err, 0)
		end
	end, { timeout = 1, type = "oneshot" })
end

for _, ev in ipairs({ "window.close", "window.kill", "window.destroy" }) do
	hl.on(ev, function(w)
		local ok, addr = pcall(function()
			return w.address
		end)
		queue(true, ok and addr or nil)
	end)
end
for _, ev in ipairs({
	"window.open",
	"window.move_to_workspace",
	"workspace.move_to_monitor",
	"monitor.added",
	"monitor.removed",
}) do
	hl.on(ev, function()
		queue(true)
	end)
end
for _, ev in ipairs({ "window.update_rules", "monitor.layout_changed" }) do
	hl.on(ev, function()
		queue(false)
	end)
end
