-- Placement of the shell's modal windows (Quickshell FloatingWindow, class org.quickshell, title "qs-<kind>":
-- qs-settings; the floating/rounding/shadow rule is "qs-modal" in hyprland/rules.lua).
-- They are ordinary floating windows, so SUPER+LMB (hyprland/binds.lua) drags them. A modal window ALWAYS opens at the
-- default place and size (centred on the focused monitor by the "qs-modal" rule, at the size Settings.qml asks for): no position or size
-- is remembered between openings, so nothing moves after it appears. This script only provides:
--   * qs_modal_reset(title), called by a double-click on the window's header (ModalReset.qml): back to the centre of its
--     monitor at its opening size, if the user dragged or resized it while it was open.

local opened_size = {} -- window address -> { w, h } it opened with (what "default size" means)

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

hl.on("window.open", function(w)
	if is_modal(w) then
		opened_size[w.address] = { w.size.x, w.size.y }
	end
end)

hl.on("window.close", function(w)
	if is_modal(w) then
		opened_size[w.address] = nil
	end
end)

-- Double-click on a window's header (ModalReset.qml, no SUPER: the bindm drag consumes SUPER+LMB, so Lua never sees
-- a double-click with it) calls this through `hyprctl dispatch`: centre the floating window with that title on its
-- monitor at the size it opened with. A tiled window is left alone.
function qs_modal_reset(title)
	for _, w in ipairs(hl.get_windows()) do
		if w.mapped and w.floating and is_modal(w) and w.title == title then
			center(w)
		end
	end
end
