local M = {}

-- Colors come from ~/.config/theme (edit theme.toml there, run theme.py apply).
local P = dofile(os.getenv("HOME") .. "/.config/theme/out/palette.lua")

-- which palette key tints the border glow; any key of out/palette.lua works
M.selected = "accent"

M.glass = {
	border_size = 2,
	window_rounding = 0, -- Hyprland windows are square (the quickshell bar elements still use theme.toml `rounding`)
	window_rounding_power = 2,
	group_rounding = 0,
	group_rounding_power = 2,
	gradient_rounding = 0,
	gradient_rounding_power = 2,
}

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

-- original grayscale glass profile (reference)
local gray_stops = {
	"#050505",
	"#222222",
	"#888888",
	"#bbbbbb",
	"#888888",
	"#222222",
	"#050505",
}

local alphas = { "aa", "66", "ff", "88", "44", "66", "aa" }

-- low tint on dark edges, higher tint on bright highlight band
local tint_amount = { 0.06, 0.12, 0.28, 0.36, 0.28, 0.12, 0.06 }

local accent = M.colors[M.selected] or M.colors.accent
local gradient = {}
for i = 1, #gray_stops do
	local tinted = mix(gray_stops[i], accent, tint_amount[i])
	gradient[i] = rgba(alphas[i], tinted)
end

M.active = {
	border_gradient = gradient,
	inactive_border = "0x22000000",
	locked_active = gradient[1],
	locked_inactive = "0x22111111",
	shadow = "0x66000000",
}

return M
