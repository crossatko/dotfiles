-- Placement of the shell's modal windows (Quickshell FloatingWindow, class org.quickshell, title "qs-<kind>":
-- qs-settings; the floating/rounding/shadow rule is "qs-modal" in hyprland/rules.lua).
-- They are ordinary floating windows, so SUPER+LMB (hyprland/binds.lua) drags them. This script adds:
--   * the position each kind was last left at, remembered when the window closes and re-applied when it opens
--     (also across Quickshell / Hyprland restarts: $XDG_STATE_HOME/quickshell/modal-windows, one "title<TAB>dx<TAB>dy"
--     line per kind, offsets from the top-left of the monitor it was on, in logical pixels, plus " w h" when the
--     user resized it, which only the resizable Settings window can be). A window left centred and at its opening
--     size is not remembered, so it keeps following the monitor it opens on. A remembered position is clamped to
--     the monitor the window opens on (the focused one). Only while floating: closed tiled (togglefloating), it
--     keeps what was saved from its last floating time and opens floating again.
--   * qs_modal_reset(title), called by a double-click on the window's header: back to the centre of its monitor at its
--     opening size, saved position forgotten.

local RESIZE_DELAY_MS = 220
local CENTER_TOLERANCE = 3 -- px: a window closed this close to the centre counts as centred

local state_home = os.getenv("XDG_STATE_HOME")
if not state_home or state_home == "" then
	state_home = (os.getenv("HOME") or "") .. "/.local/state"
end
local state_dir = state_home .. "/quickshell"
local state_file = state_dir .. "/modal-windows"

local saved = {} -- title -> { dx, dy, w?, h? }
local opened_size = {} -- window address -> { w, h } it opened with (what "default size" means)

do
	local f = io.open(state_file, "r")
	if f then
		for line in f:lines() do
			local title, dx, dy, w, h = line:match("^(qs%-[%w_%-]+)\t(%-?%d+)\t(%-?%d+)\t?(%d*)\t?(%d*)$")
			if title then
				saved[title] = { tonumber(dx), tonumber(dy), tonumber(w), tonumber(h) }
			end
		end
		f:close()
	end
end

local function persist()
	local f = io.open(state_file, "w")
	if not f then
		os.execute(("mkdir -p '%s'"):format(state_dir))
		f = io.open(state_file, "w")
	end
	if not f then
		return
	end
	local titles = {}
	for title in pairs(saved) do
		titles[#titles + 1] = title
	end
	table.sort(titles)
	for _, title in ipairs(titles) do
		local e = saved[title]
		f:write(("%s\t%d\t%d%s\n"):format(title, e[1], e[2], e[3] and ("\t%d\t%d"):format(e[3], e[4]) or ""))
	end
	f:close()
end

local function is_modal(w)
	return w.class == "org.quickshell" and (w.title or ""):find("^qs%-") ~= nil
end

-- monitor rectangle in layout (logical) pixels
local function monitor_rect(w)
	local m = w.monitor
	if not m then
		return nil
	end
	local scale = m.scale
	if not scale or scale <= 0 then
		scale = 1
	end
	return m.x, m.y, m.width / scale, m.height / scale
end

local function move_to(w, x, y)
	hl.dispatch(hl.dsp.window.move({ x = math.floor(x + 0.5), y = math.floor(y + 0.5), window = w }))
end

-- centre on its monitor, back at the size it opened with
local function center(w)
	local mx, my, mw, mh = monitor_rect(w)
	if not mx then
		return
	end
	local o = opened_size[w.address] or { w.size.x, w.size.y }
	if o[1] ~= w.size.x or o[2] ~= w.size.y then
		hl.dispatch(hl.dsp.window.resize({ x = o[1], y = o[2], window = w }))
	end
	move_to(w, mx + (mw - o[1]) / 2, my + (mh - o[2]) / 2)
end

local function place(w)
	local s = saved[w.title]
	local mx, my, mw, mh = monitor_rect(w)
	opened_size[w.address] = { w.size.x, w.size.y }
	if not s or not mx then
		return
	end
	local sw, sh = w.size.x, w.size.y
	if s[3] then
		sw, sh = math.min(s[3], mw), math.min(s[4], mh)
	end
	local x = math.max(mx, math.min(mx + s[1], mx + mw - sw))
	local y = math.max(my, math.min(my + s[2], my + mh - sh))
	move_to(w, x, y)
	if s[3] then
		-- Settings pins its window to the default size for its first 150 ms (Qt keeps the size of the last session,
		-- e.g. a tiled one), so the remembered size is applied after that
		local addr = w.address
		hl.timer(function()
			local win = hl.get_window("address:" .. addr)
			if win and win.mapped and win.floating then
				hl.dispatch(hl.dsp.window.resize({ x = sw, y = sh, window = win }))
				move_to(win, x, y)
			end
		end, { timeout = RESIZE_DELAY_MS, type = "oneshot" })
	end
end

local function remember(w)
	local mx, my, mw, mh = monitor_rect(w)
	if not w.floating or not mx or w.size.x <= 0 then
		return
	end
	local dx, dy = w.at.x - mx, w.at.y - my
	local o = opened_size[w.address]
	local resized = o and (w.size.x ~= o[1] or w.size.y ~= o[2])
	local centred = math.abs(dx - (mw - w.size.x) / 2) <= CENTER_TOLERANCE and math.abs(dy - (mh - w.size.y) / 2) <= CENTER_TOLERANCE
	local before = saved[w.title] and table.concat(saved[w.title], ",") or ""
	if centred and not resized then
		saved[w.title] = nil
	else
		saved[w.title] = { dx, dy, resized and w.size.x or nil, resized and w.size.y or nil }
	end
	if (saved[w.title] and table.concat(saved[w.title], ",") or "") ~= before then
		persist()
	end
end

hl.on("window.open", function(w)
	if is_modal(w) then
		place(w)
	end
end)

hl.on("window.close", function(w)
	if is_modal(w) then
		pcall(remember, w)
		opened_size[w.address] = nil
	end
end)

-- Double-click on a window's header (ModalReset.qml, no SUPER: the bindm drag consumes SUPER+LMB, so Lua never sees
-- a double-click with it) calls this through `hyprctl dispatch`: centre the floating window with that title on its
-- monitor at the size it opened with, and forget its saved position. A tiled window is left alone.
function qs_modal_reset(title)
	for _, w in ipairs(hl.get_windows()) do
		if w.mapped and w.floating and is_modal(w) and w.title == title then
			saved[title] = nil
			persist()
			center(w)
		end
	end
end
