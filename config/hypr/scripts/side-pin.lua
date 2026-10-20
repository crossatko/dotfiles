-- Super+Shift+P (binds.lua): float + pin the focused window into the right-hand strip of its monitor (the
-- 866px strip scripts/pip-orientation.lua reserves while a pinned window sits there).
-- With gaps it keeps the old fixed box (12px from top and bottom, 14px short of the right edge). While
-- "No gaps for a single window" applies on the monitor (managed.smart_enabled and at most one visible tiled
-- window, what w[tv1] counts, so also a workspace holding only the pinned window; a maximized window counts
-- too) it is flush instead: full height, right edge on the screen edge, rounding 0, like the lone tiled
-- window beside it. The smart-gaps rules only match float = false, so floating/pinned windows get this here,
-- refitted on every event that can change the count.
local ok_managed, managed = pcall(require, "hyprland.managed")
if not ok_managed or type(managed) ~= "table" then
	managed = nil
end

local TAG = "side-pin" -- survives a config reload (a Lua table would not necessarily)
local STRIP_W = 866
local GAP_BOX = { right = 14, vgap = 12 } -- distance kept from the right edge / top and bottom with gaps

local M = {}

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

-- same rule as pip-reserve.lua's smart_gaps_apply (userdata objects: nil checks only)
local closing = nil
local function smart_applies(mon, exclude)
	local skip = exclude or closing
	if managed == nil or mon == nil then
		return false
	end
	local ok, res = pcall(function()
		local ws = mon.active_workspace
		if ws == nil or ws.id == nil or managed.smart_enabled(mon) ~= true then
			return false
		end
		local tiled = 0
		for _, w in ipairs(hl.get_windows()) do
			if
				w.address ~= skip
				and w.mapped ~= false
				and w.hidden ~= true
				and w.monitor ~= nil
				and w.monitor.name == mon.name
				and w.workspace ~= nil
				and w.workspace.id == ws.id
				and w.floating ~= true
				and not w.pinned
			then
				if w.fullscreen == 1 then
					return true
				end
				local g = w.group
				if g == nil or g.current == nil or g.current.address == w.address then
					tiled = tiled + 1
				end
			end
		end
		return tiled <= 1
	end)
	return ok and res == true
end

local function dispatch_prop(sel, prop, value)
	hl.dispatch(hl.dsp.window.set_prop({ prop = prop, value = value, window = sel }))
end

local fitting = false
local function fit(w)
	if fitting or w == nil or w.mapped == false or w.monitor == nil then
		return
	end
	local sel = "address:" .. w.address
	local mon = w.monitor
	if not w.pinned then
		-- unpinned again (Super+P): hand it back to the normal rules
		if tagged(w) then
			dispatch_prop(sel, "rounding", "unset")
			hl.dispatch(hl.dsp.window.tag({ tag = "-" .. TAG, window = sel }))
		end
		return
	end
	local flush = smart_applies(mon)
	local x, y, width, height
	if flush then
		x, y, width, height = mon.x + mon.width - STRIP_W, mon.y, STRIP_W, mon.height
	else
		width, height = STRIP_W, mon.height - 2 * GAP_BOX.vgap
		x, y = mon.x + mon.width - width - GAP_BOX.right, mon.y + GAP_BOX.vgap
	end
	fitting = true
	local ok, err = pcall(function()
		if w.size.x ~= width or w.size.y ~= height then
			hl.dispatch(hl.dsp.window.resize({ x = width, y = height, window = sel }))
		end
		if w.at.x ~= x or w.at.y ~= y then
			hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = sel }))
		end
		dispatch_prop(sel, "rounding", flush and "0" or "unset")
	end)
	fitting = false
	if not ok then
		error(err, 0)
	end
end

local function refit_all()
	for _, w in ipairs(hl.get_windows()) do
		if tagged(w) then
			fit(w)
		end
	end
end

-- the keybind
function M.pin()
	local w = hl.get_active_window()
	if w == nil then
		return
	end
	local sel = "address:" .. w.address
	hl.dispatch(hl.dsp.window.float({ action = true, window = sel }))
	hl.dispatch(hl.dsp.window.pin({ action = true, window = sel }))
	hl.dispatch(hl.dsp.window.tag({ tag = "+" .. TAG, window = sel }))
	fit(hl.get_active_window())
end

-- subscriptions are kept in a global and removed at the next load, so a reload does not double them
local subs = rawget(_G, "__side_pin_subs")
if type(subs) == "table" then
	for _, s in ipairs(subs) do
		pcall(function()
			s:remove()
		end)
	end
end
subs = {}
rawset(_G, "__side_pin_subs", subs)

local function on(ev, fn)
	local ok, sub = pcall(hl.on, ev, fn)
	if ok and sub ~= nil then
		subs[#subs + 1] = sub
	end
end

local function sync_closing(w)
	local okw, addr = pcall(function()
		return w ~= nil and w.address or nil
	end)
	closing = okw and type(addr) == "string" and addr or nil
	local ok, err = pcall(refit_all)
	closing = nil
	if not ok then
		error(err, 0)
	end
end
for _, ev in ipairs({ "window.close", "window.kill", "window.destroy" }) do
	on(ev, sync_closing)
end
for _, ev in ipairs({
	"window.open",
	"window.pin",
	"window.move_to_workspace",
	"window.fullscreen",
	"window.update_rules",
	"workspace.active",
	"workspace.move_to_monitor",
	"workspace.removed",
}) do
	on(ev, refit_all)
end

M.refit = refit_all
-- shared with pip-orientation.lua (pinned PiP/mpv/Twitch boxes follow the same flush/gaps rule)
M.smart_applies = smart_applies
M.tagged = tagged

return M
