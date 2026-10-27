local M = {}

-- Colors come from ~/.config/theme (edit theme.toml there, run theme.py apply).
-- out/ is the per-machine render (git-ignored); default/ is the committed fallback, so a missing out/ never aborts the config.
local theme_dir = os.getenv("HOME") .. "/.config/theme/"
local ok, P = pcall(dofile, theme_dir .. "out/palette.lua")
if not ok then
	P = dofile(theme_dir .. "default/palette.lua")
end

-- which palette key tints the border glow; any key of out/palette.lua works
M.selected = "accent"

M.glass = {
	border_size = 2,
	window_rounding = 0, -- Hyprland windows are square (the quickshell bar elements still use theme.toml `rounding`)
	window_rounding_power = 3,
}

-- Group bar (tabs above grouped windows, settings.lua): one glass pill per window, no titles.
M.groupbar = {
	height = 12, -- pill height (px): the slimmest that still reads as a glass pill (8-10 = a line); 14-16 = safe
	gap = 6, -- between pills and between the bar and its window (= Theme.qml controlGap)
	rounding_power = 2,
}

-- Pill radius for a window radius R: a full pill (height / 2) like the shell's chips; square windows (R = 0) get
-- square tabs. managed.lua re-applies it when Settings > Appearance changes the radius.
function M.groupbar_rounding(R)
	if type(R) ~= "number" or R <= 0 then
		return 0
	end
	return math.tointeger(math.floor(math.min(R, M.groupbar.height / 2))) or 0
end

M.colors = P

local function clamp(v)
	if v < 0 then
		return 0
	end
	if v > 255 then
		return 255
	end
	return math.floor(v + 0.5)
end

local function hex_to_rgb(hex)
	hex = hex:gsub("^#", "")
	return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

local function rgb_to_hex(r, g, b)
	return string.format("#%02x%02x%02x", clamp(r), clamp(g), clamp(b))
end

local function mix(hex_a, hex_b, t)
	local ar, ag, ab = hex_to_rgb(hex_a)
	local br, bg, bb = hex_to_rgb(hex_b)
	return rgb_to_hex(ar * (1 - t) + br * t, ag * (1 - t) + bg * t, ab * (1 - t) + bb * t)
end

local function rgba(alpha_hex, rgb_hex)
	return string.format("0x%s%s", alpha_hex, rgb_hex:gsub("^#", ""))
end

-- Group bar colours: glass strips, not filled pills. Fill alphas per mode from palette.lua (theme.py): on solid_glass
-- the compositor glass under each pill (groupbar.blur) gives the frost and the lit rim, so the fills are only a light
-- wash (half the card fill); without glass a plain-blur wash (light mode more: a pale cover) plus a faint lit top
-- edge (Quickshell GlassEdge; the fill is a gradient texture spread over the pill, stops at 1 - i/(n+1), first =
-- bottom, so n equal stops and a different last one draw a ~1 px line). Focused tab = accent glass (low accent
-- tint), others neutral; locked groups use the warn hue. Fallbacks = theme.toml's dark defaults.
M.groupbar_edge_stops = 12 -- ~1 px top edge at the 12 px pill height
function M.groupbar_colors(glass)
	local c = M.colors
	local light = (c.plain_fill_min or 0) > 0.5 -- light palettes need a pale cover (theme.toml [settings_light])
	local fill = glass and (c.card_fill or 0.3) * 0.5 or math.max(0.3, (c.plain_fill_min or 0) * 0.75)
	local function a(x)
		return string.format("%02x", clamp(math.min(1, x) * 255))
	end
	local acc = c[M.selected] or c.accent
	local warn = c.warn or c.yellow or acc
	local rest = mix(c.bg, c.fg, glass and 0.08 or 0.16) -- no glass rim: a stronger lift keeps the pill visible on dark walls
	local edge = not glass and rgba(a(light and 0.7 or 0.3), light and "#ffffff" or c.fg) or nil
	local function pill(rgb, alpha)
		if not edge then
			return rgba(a(alpha), rgb)
		end
		local t = {}
		for i = 1, M.groupbar_edge_stops - 1 do
			t[i] = rgba(a(alpha), rgb)
		end
		t[M.groupbar_edge_stops] = edge
		return { colors = t }
	end
	local tint = light and 0.55 or 0.5 -- accent share of the focused pill
	return {
		active = pill(mix(c.bg, acc, tint), fill + 0.2),
		inactive = pill(rest, fill),
		locked_active = pill(mix(c.bg, warn, tint), fill + 0.2),
		locked_inactive = pill(mix(rest, warn, 0.25), fill),
	}
end

-- Active border = the Quickshell accent (palette.lua `accent`, or whichever key M.selected names), solid;
-- inactive borders are fully transparent.
local accent = M.colors[M.selected] or M.colors.accent
local active = rgba("ff", accent)

M.active = {
	border_gradient = { active }, -- single stop: solid colour
	inactive_border = "0x00000000",
	locked_active = active,
	locked_inactive = "0x22111111",
	shadow = "0x66000000",
}

return M
