-- MANAGED FILE: Quickshell Settings > Appearance (config/quickshell/Appearance.qml) controls what this
-- file does. Do not put hand-written settings here; set your own values in settings.lua / theme.lua /
-- workspaces.lua / rules.lua as usual. This file never edits them.
--
-- The data is NOT in the repo: ${XDG_STATE_HOME:-~/.local/state}/quickshell/appearance.json
-- (env override APPEARANCE_FILE), written only by Quickshell:
--   {"version":1,"radius":12,"gap":10,"edgeGap":10,"border":2,"barFloating":true,"smartGaps":true,
--    "smartMonitors":{"Dell Inc. DELL U2515H 9X2VY5AK1D5L":false}}
--
-- Override semantics: only keys PRESENT (and valid) in that file are applied, on top of the hand-written
-- config (hyprland.lua loads this file after settings/workspaces/rules, so it wins):
--   radius  -> decoration.rounding        (0-32)
--   gap     -> general.gaps_in = round(gap/2), and general.gaps_out = gap unless edgeGap is set   (0-32)
--   edgeGap -> general.gaps_out           (0-40)
--   border  -> general.border_size        (0-6)
--   smartGaps (default true) -> the "lone window fills the screen" rules below are enabled/disabled;
--     it is the default for every monitor without its own entry in smartMonitors
--   smartMonitors -> per-monitor smartGaps: {"<monitor key>": bool}. Key = the monitor description as
--     Hyprland reports it (hl.get_monitors()[i].description = hyprctl monitors "description" =
--     Quickshell Hyprland.monitorFor(screen).description), or the connector name when the description
--     is not a valid key. Valid key: 1-96 printable ASCII characters without '"' and '\'. At most 16
--     entries, values true/false only; anything else makes the whole map "not set".
--   barFloating is only the DEFAULT for bars without their own bars.json `floating` (docked / floating is per bar now,
--     Settings > Bar); see M.bar_floating / M.bar_reserve, used by apply_bar_gaps and scripts/pip-reserve.lua
--   scripts/pip-reserve.lua also keeps the pinned video box gaps_out away from the screen edges and the
--   bar (M.edge_margins()); layout_apply() re-fits it through pip_bar_changed()
-- A missing key leaves the hand-written value alone. Values are clamped and rounded; anything odd
-- (garbage, > 4 KiB, directory, FIFO, NaN, strings) counts as "not set".
--
-- Baseline: at load, before applying anything, the hand-written values of the four options are read
-- back with hl.get_config (M.baseline). layout_apply() writes them back for keys that this file had
-- overridden and that are no longer set (Settings > Appearance "Reset" writes {}).
--
-- Glass (Settings > Glass, only on the Hyprland fork with decoration:blur:variant = "solid_glass"): a SECOND
-- state file next to appearance.json, ${XDG_STATE_HOME:-~/.local/state}/quickshell/glass.json (env override
-- GLASS_FILE), a flat object of numbers written only by Quickshell (GlassTuneCtl.qml):
--   {"version":1,"refraction":48,"bulb":57,"clarity":0.4,"aberration":0,"tint":0,"depth":2,"edge_curve":1.3,
--    "light_angle":0,"specular_intensity":0,"specular_power":1,"sheen":0,"saturation":1.35,"frost":0,"darkening":0.8}
-- Per colour mode: those top-level keys are the dark set, a "light" object the light set (see M.split_glass).
-- Every PRESENT, valid key is applied to decoration.blur.solid_glass.<key> at load, after settings.lua, so
-- it wins; the solid_glass block in settings.lua is therefore the default for keys Settings never touched.
-- Values are clamped to the option ranges (tint: AARRGGBB integer). On a Hyprland without the solid_glass
-- options (stock) nothing is applied and no option is ever touched (M.glass_supported()).
--
-- Animations (Settings > Animations): a THIRD state file next to appearance.json,
-- ${XDG_STATE_HOME:-~/.local/state}/quickshell/animations.json (env override ANIM_FILE), flat, written only by
-- Quickshell (Motion.qml). The popup* keys are Quickshell's own; the Hyprland ones:
--   {"version":1,"hyprEnabled":true,"hyprSpeed":1.5,"hyprCurve":"snappy",
--    "windowsSpeed":0.8,"windowsCurve":"overshoot","fadeEnabled":false, ...}
--   hyprEnabled -> animations.enabled; hyprSpeed (0.25-10, higher = faster) divides every leaf's speed
--   (= duration) of animations.lua; hyprCurve = "config" (each leaf keeps its own curve) or a preset of
--   M.ANIM_CURVES (all leaves). Per group (M.ANIM_GROUPS: windows, layers, fade, workspaces, border,
--   specialWorkspace): <group>Enabled, <group>Speed (multiplies hyprSpeed), <group>Curve (overrides hyprCurve).
-- The base values are the hand-written leaves in animations.lua (styles are always kept). With no Hyprland key
-- set, nothing is touched at load. anim_apply() (Quickshell: hyprctl eval "if anim_apply then anim_apply() end")
-- re-reads the file and rewrites every leaf from the base, so removing a key restores the hand-written value.
--
-- Runtime: Quickshell runs `hyprctl eval "if layout_apply then layout_apply() end"` after saving (and
-- `hyprctl reload config-only` when smartGaps or smartMonitors changed). A config reload re-runs
-- everything, so it gives the same result.
--
-- Nothing in here may raise at config load: a Lua error there disables the rest of the config,
-- keybinds included. hyprland.lua and scripts/pip-reserve.lua also load it under pcall.
local M = {}
-- A failed load must not register the rules twice when pip-reserve.lua requires it again.
package.loaded[(...) or "hyprland.managed"] = M

M.BAR_HEIGHT = 40 -- the Quickshell bar (Theme.qml barHeight); scripts/pip-reserve.lua uses it
M.BAR_GAP_DEFAULT = 0 -- floating bar margin when neither gap nor edgeGap is set (theme.toml [settings] gap)
M.MAX_BYTES = 4096
M.SMART_KEY_MAX = 96 -- longest smartMonitors key (bytes); same in Appearance.qml
M.SMART_MAP_MAX = 16 -- most smartMonitors entries; same in Appearance.qml
M.SMART_SETS_MAX = 32 -- most per-monitor rule sets registered in one config generation (hot-plug bound)

local LIMITS = { radius = { 0, 32 }, gap = { 0, 32 }, edgeGap = { 0, 40 }, border = { 0, 6 } }
local BOOLS = { barFloating = true, smartGaps = true }

-- Hyprland option per key of M.targets()
M.OPTIONS = {
	gaps_in = "general.gaps_in",
	gaps_out = "general.gaps_out",
	border_size = "general.border_size",
	rounding = "decoration.rounding",
}
local OPTION_ORDER = { "gaps_in", "gaps_out", "border_size", "rounding" }

-- number -> clamped integer, or nil for non-numbers, NaN and +-inf
local function clean_number(key, v)
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	local lim = LIMITS[key]
	if v < lim[1] then
		v = lim[1]
	elseif v > lim[2] then
		v = lim[2]
	end
	return math.tointeger(math.floor(v + 0.5)) or lim[1]
end

-- Raw token of the LAST `"key": <token>` followed by `,` or `}` (JSON.parse keeps the last duplicate).
local function last_token(text, key)
	local found
	for tok, after in text:gmatch('"' .. key .. '"%s*:%s*([^%s,}%]]+)%s*(.?)') do
		if after == "," or after == "}" then
			found = tok
		else
			found = nil -- malformed occurrence: it would win in JSON too, so it voids earlier ones
		end
	end
	return found
end

-- smartMonitors key check (also used for the keys this file derives from monitors):
-- 1..SMART_KEY_MAX bytes of printable ASCII, no '"' and no '\' (so no JSON escapes are ever needed).
function M.valid_key(k)
	return type(k) == "string" and #k >= 1 and #k <= M.SMART_KEY_MAX and k:find('[^ -~]') == nil and k:find('["\\]') == nil
end

-- '{"<key>":true|false, ...}' -> table, or nil when it is empty or anything in it is not valid
-- (bad key, non-boolean value, nesting, escapes, more than SMART_MAP_MAX distinct keys). A duplicate
-- key: the last one wins, as in JSON.parse.
local function parse_map(obj)
	local inner = type(obj) == "string" and obj:match("^{(.*)}$")
	if inner == nil or inner:match("^%s*$") then
		return nil
	end
	local out, n, pos = {}, 0, 1
	while true do
		local k, v, p = inner:match('^%s*"([^"]*)"%s*:%s*(%a+)%s*()', pos)
		if k == nil or not M.valid_key(k) or (v ~= "true" and v ~= "false") then
			return nil
		end
		if out[k] == nil then
			n = n + 1
			if n > M.SMART_MAP_MAX then
				return nil
			end
		end
		out[k] = v == "true"
		local c = inner:sub(p, p)
		if c == "" then
			return out
		end
		if c ~= "," then
			return nil
		end
		pos = p + 1
	end
end

-- Pure: text of appearance.json -> table with ONLY the keys that are set and valid
-- (radius, gap, edgeGap, border: integers; barFloating, smartGaps: booleans; smartMonitors: map of
-- booleans, see parse_map). Never raises.
-- No JSON library: the file is tiny and nearly flat, so values are picked with patterns. Nested objects
-- are cut out first (replaced by "@<n>"), so a key inside the map never counts as a top-level key.
-- Text that does not look like one JSON object, or is larger than MAX_BYTES, yields {}.
function M.parse(text)
	local s = {}
	if type(text) ~= "string" or #text > M.MAX_BYTES then
		return s
	end
	local body = text:match("^%s*(%b{})%s*$")
	if body == nil then
		return s
	end
	local nested = {}
	body = "{" .. (body:sub(2, -2):gsub("%b{}", function(obj)
		nested[#nested + 1] = obj
		return "@" .. #nested
	end)) .. "}"
	local map_tok = last_token(body, "smartMonitors")
	local map_idx = map_tok and tonumber(map_tok:match("^@(%d+)$"))
	if map_idx ~= nil then
		s.smartMonitors = parse_map(nested[map_idx])
	end
	for key in pairs(LIMITS) do
		local tok = last_token(body, key)
		local v = clean_number(key, tok and tok:match("^%-?%d[%d%.eE+%-]*$") and tonumber(tok))
		if v ~= nil then
			s[key] = v -- anything else (null, strings, NaN, ...) is "not set"
		end
	end
	for key in pairs(BOOLS) do
		local tok = last_token(body, key)
		if tok == "true" then
			s[key] = true
		elseif tok == "false" then
			s[key] = false
		end
	end
	return s
end

-- Reads a small regular file (at most `max` bytes, default MAX_BYTES) without ever blocking.
-- "r+" (O_RDWR) is used on purpose: opening a FIFO read-only blocks until a writer appears, which
-- would hang the compositor, while O_RDWR returns at once; directories fail to open with it.
-- Non-seekable files (FIFOs, ttys) are then rejected by the seek. Nothing is ever written.
-- A file without write permission therefore reads as missing (Quickshell always creates it writable).
-- -> text, or nil plus a reason ("missing", "not-regular", "too-large").
function M.read_small_file(path, max)
	max = type(max) == "number" and max > 0 and max or M.MAX_BYTES
	if type(path) ~= "string" or path == "" then
		return nil, "missing"
	end
	local f = io.open(path, "r+")
	if f == nil then
		return nil, "missing"
	end
	local ok, text, why = pcall(function()
		local size = f:seek("end")
		if size == nil then
			return nil, "not-regular"
		end
		if size > max then
			return nil, "too-large"
		end
		if f:seek("set") == nil then
			return nil, "not-regular"
		end
		local t = f:read(max + 1) or ""
		if #t > max then -- size lied (/dev/zero and friends)
			return nil, "too-large"
		end
		return t
	end)
	pcall(f.close, f)
	if not ok then
		return nil, "not-regular"
	end
	return text, why
end

-- Glass options (decoration.blur.solid_glass.*): key -> {min, max}; same ranges as GlassTuneCtl.qml
M.GLASS_LIMITS = {
	refraction = { 0, 48 }, bulb = { 4, 256 }, clarity = { 0, 1 }, aberration = { 0, 0.25 },
	tint = { 0, 0xFFFFFFFF }, depth = { 0, 3 }, edge_curve = { 0.2, 5 }, light_angle = { 0, 360 },
	specular_intensity = { 0, 3 }, specular_power = { 1, 200 }, sheen = { 0, 1 }, saturation = { 0, 3 },
	frost = { 0, 16 }, darkening = { 0, 1 },
}

function M.state_path()
	local p = os.getenv("APPEARANCE_FILE")
	if p ~= nil and p ~= "" then
		return p
	end
	local state = os.getenv("XDG_STATE_HOME")
	if state == nil or state == "" then
		state = (os.getenv("HOME") or "") .. "/.local/state"
	end
	return state .. "/quickshell/appearance.json"
end

-- -> settings table (see parse; {} when the file is missing or unusable), plus a status string.
function M.read()
	local ok, s, why = pcall(function()
		local text, why = M.read_small_file(M.state_path())
		if text == nil then
			return {}, why
		end
		return M.parse(text), "ok"
	end)
	if not ok or type(s) ~= "table" then
		return {}, "error"
	end
	return s, why
end

-- settings -> the Hyprland values to override, only for keys that are set:
-- {gaps_in?, gaps_out?, border_size?, rounding?}
function M.targets(s)
	s = type(s) == "table" and s or {}
	local t = {}
	local gap = clean_number("gap", s.gap)
	local edge = clean_number("edgeGap", s.edgeGap)
	if gap ~= nil then
		t.gaps_in = math.tointeger(math.floor(gap / 2 + 0.5)) or 0
	end
	if edge ~= nil then
		t.gaps_out = edge
	elseif gap ~= nil then
		t.gaps_out = gap
	end
	t.border_size = clean_number("border", s.border)
	t.rounding = clean_number("radius", s.radius)
	return t
end

-- settings -> what other Lua code needs (scripts/pip-reserve.lua, M.edge_margins): the set values plus
-- barFloating, smartGaps, barGap (floating bar margin, = Quickshell Theme.barGap) and barReserve.
function M.effective(s)
	s = type(s) == "table" and s or {}
	local t = M.targets(s)
	local e = {
		radius = t.rounding,
		gap = clean_number("gap", s.gap),
		edgeGap = clean_number("edgeGap", s.edgeGap),
		border = t.border_size,
		gapsIn = t.gaps_in,
		gapsOut = t.gaps_out,
		barFloating = s.barFloating == true,
		smartGaps = s.smartGaps ~= false,
	}
	e.barGap = e.barFloating and (t.gaps_out or M.BAR_GAP_DEFAULT) or 0
	e.barReserve = M.BAR_HEIGHT + e.barGap
	return e
end

-- Never raises; on any failure returns the "nothing set" values.
function M.get()
	local ok, e = pcall(function()
		return M.effective((M.read()))
	end)
	if ok and type(e) == "table" then
		return e
	end
	return M.effective({})
end

-- The distance a window placed against the screen edges keeps from them, the same as a tiled window's
-- general.gaps_out: the override (edgeGap, else gap) when set, else the hand-written value read at load
-- (M.baseline, below; plain integer or {top,right,bottom,left}), else 0. Used by scripts/pip-reserve.lua
-- for the pinned video box. `e` = M.get() result (read when nil).
-- -> {top, right, bottom, left} integers in 0..M.EDGE_MARGIN_MAX. Never raises.
M.EDGE_MARGIN_MAX = 200
function M.edge_margins(e)
	local zero = { top = 0, right = 0, bottom = 0, left = 0 }
	local ok, m = pcall(function()
		e = type(e) == "table" and e or M.get()
		local v = e.gapsOut
		if type(v) ~= "number" then
			v = M.baseline.gaps_out
		end
		local function side(x)
			if type(x) ~= "number" or x ~= x then
				return 0
			end
			x = math.max(0, math.min(M.EDGE_MARGIN_MAX, x))
			return math.tointeger(math.floor(x + 0.5)) or 0
		end
		if type(v) == "table" then
			return { top = side(v.top), right = side(v.right), bottom = side(v.bottom), left = side(v.left) }
		end
		local s = side(v)
		return { top = s, right = s, bottom = s, left = s }
	end)
	return ok and m or zero
end

-- ---------------------------------------------------------------- baseline (hand-written values)

-- hl.get_config value -> something hl.config accepts back. Gaps come back as {top,right,bottom,left};
-- equal sides become the plain integer the hand-written config used.
local function normalize(v)
	if type(v) == "number" then
		return math.tointeger(v) or v
	end
	if type(v) == "table" then
		local t, r, b, l = v.top, v.right, v.bottom, v.left
		if type(t) ~= "number" or type(r) ~= "number" or type(b) ~= "number" or type(l) ~= "number" then
			return nil
		end
		if t == r and t == b and t == l then
			return math.tointeger(t) or t
		end
		return { top = t, right = r, bottom = b, left = l }
	end
	return nil
end

-- {gaps_in, gaps_out, border_size, rounding} as the hand-written config set them; a key whose value
-- could not be read is missing (it is then never written back).
M.baseline = {}

function M.capture_baseline()
	local base = {}
	for _, key in ipairs(OPTION_ORDER) do
		local ok, v = pcall(hl.get_config, M.OPTIONS[key])
		if ok then
			base[key] = normalize(v)
		end
	end
	M.baseline = base
	return base
end

-- ---------------------------------------------------------------- glass (solid_glass options)

function M.glass_path()
	local p = os.getenv("GLASS_FILE")
	if p ~= nil and p ~= "" then
		return p
	end
	return (M.state_path():match("^(.*)/[^/]*$") or ".") .. "/glass.json"
end

-- Per colour mode (theme.py mode): glass.json's top-level keys are the DARK values; a "light" object holds the light
-- ones, {"version":1, <dark keys>, "light": {<light keys>}}. Each mode only ever reads its own keys, so tuning one
-- never changes the other. A key a mode does not set is the hand-written settings.lua value (M.glass_base), except in
-- light mode for tint / darkening, which then default to the dark settings.lua glass mirrored (M.light_default):
-- darkening off, tint of the palette bg with the combined absorption 1 - (1 - tint alpha) * (1 - darkening).
-- tint_from_bg (true / false, per mode; light default true): the tint keeps its alpha but takes its colour from the
-- palette bg, so it follows the wallpaper. Which mode is active is read from the palette itself (bg luminance, like
-- nvim), so it can never disagree with the colours Hyprland / Quickshell show.

-- Pure: glass.json text -> dark text, light object text (nil when there is none)
function M.split_glass(text)
	if type(text) ~= "string" then
		return text, nil
	end
	local s, e = text:find('"light"%s*:%s*{')
	if s == nil then
		return text, nil
	end
	local obj = text:match("^%b{}", e)
	if obj == nil then
		return text:sub(1, s - 1) .. "}", nil
	end
	return text:sub(1, s - 1) .. text:sub(e + #obj), obj
end

-- Pure: text of ONE mode's glass object -> {key = number} with ONLY the keys that are set and valid (clamped; tint
-- is rounded to an integer), plus tint_from_bg (boolean) when set. Never raises; anything odd (garbage, > 4 KiB,
-- null, strings, NaN) is "not set". Nested objects (the "light" one) must be split off first (M.split_glass).
function M.parse_glass(text)
	local g = {}
	if type(text) ~= "string" or #text > M.MAX_BYTES then
		return g
	end
	local body = text:match("^%s*(%b{})%s*$")
	if body == nil then
		return g
	end
	for key, lim in pairs(M.GLASS_LIMITS) do
		local tok = last_token(body, key)
		local v = tok and tok:match("^%-?%d[%d%.eE+%-]*$") and tonumber(tok)
		if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
			v = math.max(lim[1], math.min(lim[2], v))
			if key == "tint" then
				v = math.tointeger(math.floor(v + 0.5)) or lim[1]
			end
			g[key] = v
		end
	end
	local fb = last_token(body, "tint_from_bg")
	if fb == "true" or fb == "false" then
		g.tint_from_bg = fb == "true"
	end
	return g
end

local function srgb_lin(c)
	c = c / 255
	return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end

-- palette bg "#rrggbb" -> r, g, b (0-255) and whether it is a light palette (luminance > 0.4)
function M.parse_bg(hex)
	if type(hex) ~= "string" then
		return nil
	end
	local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
	if r == nil then
		return nil
	end
	r, g, b = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
	return r, g, b, 0.2126 * srgb_lin(r) + 0.7152 * srgb_lin(g) + 0.0722 * srgb_lin(b) > 0.4
end

-- Pure: light mode's tint / darkening when glass.json's light object does not set them: the dark hand-written
-- values (`base`) mirrored (see above); the tint colour is replaced later when tint_from_bg is on
function M.light_default(base)
	local tint = math.tointeger(tonumber(base.tint) or 0) or 0
	local dark = math.max(0, math.min(1, tonumber(base.darkening) or 0))
	local a = ((tint >> 24) & 0xFF) / 255
	local alpha = math.max(0, math.min(255, math.floor((1 - (1 - a) * (1 - dark)) * 255 + 0.5)))
	return (alpha << 24) | 0xFFFFFF, 0
end

-- Pure: one mode's parsed glass object -> the option table to apply. light: palette is light; r, g, b: palette bg.
function M.glass_options(g, base, light, r, gr, b)
	local t = {}
	for key in pairs(M.GLASS_LIMITS) do
		if type(g[key]) == "number" then
			t[key] = g[key]
		end
	end
	local from_bg = g.tint_from_bg
	if light then
		local dt, dd = M.light_default(base or {})
		t.tint = t.tint or dt
		t.darkening = t.darkening or dd
		if from_bg == nil then
			from_bg = true
		end
	end
	if from_bg and r ~= nil then
		local tint = t.tint or math.tointeger(tonumber((base or {}).tint) or 0) or 0
		t.tint = (tint & 0xFF000000) | (r << 16) | (gr << 8) | b
	end
	return t
end

-- M.glass_base: every solid_glass option as settings.lua left it, read at load before glass.json is applied (the
-- per-mode fallback for keys a mode does not set; a runtime M.apply() must not read back its own output).
function M.capture_glass_base()
	if M.glass_base ~= nil or not M.glass_supported() then
		return
	end
	local base = {}
	for key in pairs(M.GLASS_LIMITS) do
		local ok, v = pcall(hl.get_config, "decoration.blur.solid_glass." .. key)
		if ok and tonumber(v) ~= nil then
			base[key] = tonumber(v)
		end
	end
	M.glass_base = base
end

local function palette_bg()
	local ok, theme = pcall(require, "hyprland.theme")
	return ok and type(theme) == "table" and type(theme.colors) == "table" and theme.colors.bg or nil
end

-- -> the active mode's glass object (parsed), plus whether the palette is light and its bg r, g, b
function M.read_glass()
	local r, gr, b, light = M.parse_bg(palette_bg())
	local ok, g = pcall(function()
		local text = M.read_small_file(M.glass_path())
		if not text then
			return {}
		end
		local dark_text, light_text = M.split_glass(text)
		return M.parse_glass((light and light_text or (not light and dark_text)) or "{}")
	end)
	return ok and type(g) == "table" and g or {}, light == true, r, gr, b
end

-- Does this Hyprland have decoration:blur:solid_glass:*? (stock builds do not)
function M.glass_supported()
	local ok, v = pcall(hl.get_config, "decoration.blur.solid_glass.refraction")
	return ok and v ~= nil
end

-- (glass object, light, r, g, b) as M.read_glass returns them -> writes the options; nothing at all when the option
-- does not exist. Every key a mode does not set is written back to its settings.lua value, so a runtime re-apply
-- after a mode switch cannot keep the other mode's value. -> true, or false plus a reason.
function M.apply_glass(g, light, r, gr, b)
	g = type(g) == "table" and g or {}
	if next(g) == nil and not light then
		return true
	end
	if not M.glass_supported() then
		return false, "no solid_glass options"
	end
	local t = M.glass_options(g, M.glass_base or {}, light, r, gr, b)
	for key, v in pairs(M.glass_base or {}) do
		if t[key] == nil then
			t[key] = v
		end
	end
	return pcall(hl.config, { decoration = { blur = { solid_glass = t } } })
end

-- Glass fade (fork option decoration:blur:solid_glass:layer_alpha_ref, branch more-blur-rebased-20261021): the
-- glass of a LAYER surface follows the surface's own alpha at each pixel, full strength at this alpha. Quickshell's
-- glass cards fill with Theme.bg at 0.3 (Theme.cardFill / glassFill with glass on), so a card fading from 0 to 1
-- fades its glass from 0 to full (PopupHost / ModalMenu animations). On a build without the option nothing is set
-- (no config error); the glass then stays at full strength during fades, as before.
M.GLASS_LAYER_ALPHA_REF = 0.3
function M.apply_glass_layer_alpha()
	local ok, v = pcall(hl.get_config, "decoration.blur.solid_glass.layer_alpha_ref")
	if not ok or v == nil then
		return false, "no layer_alpha_ref option"
	end
	return pcall(hl.config, { decoration = { blur = { solid_glass = { layer_alpha_ref = M.GLASS_LAYER_ALPHA_REF } } } })
end

-- ---------------------------------------------------------------- animations (animations.json)

-- preset curves, registered as qs_<id>; "config" = the leaf's own curve from animations.lua
M.ANIM_CURVES = {
	smooth = { type = "bezier", points = { { 0.25, 0.1 }, { 0.25, 1 } } },
	snappy = { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } },
	overshoot = { type = "bezier", points = { { 0.34, 1.56 }, { 0.64, 1 } } },
	linear = { type = "bezier", points = { { 0, 0 }, { 1, 1 } } },
	-- settle_ms: measured time to settle within 2 % of the target UNSCALED (window move, 2026-10-20); the curve is
	-- time-scaled so it settles in BASE_MS / factor, like the bezier leaves (damping ratio kept, ~0.5 % overshoot)
	spring = { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644, settle_ms = 575 },
}
M.ANIM_GROUPS = {
	windows = { "windows", "windowsMove", "windowsIn", "windowsOut" },
	layers = { "layers", "layersIn", "layersOut" },
	fade = { "fade", "fadeIn", "fadeOut", "fadeLayersIn", "fadeLayersOut" },
	workspaces = { "workspaces", "workspacesIn", "workspacesOut" },
	border = { "border" },
	specialWorkspace = { "specialWorkspace" },
}
M.ANIM_SPEED = { 0.25, 10 } -- every speed key; same as Motion.qml speedRange
-- effective factor = hyprSpeed x group speed (0.0625-100); leaf speed (ds) = base / factor, floored at 0.01 (1 ms;
-- the fork accepts it), so at most 32 ds for the 2.0 (BASE_MS 200) base. Springs get "qs_spring_<round(f*100)>" (6-10000,
-- integers, e.g. 2.5x -> qs_spring_250); measured stable (no ringing) up to f = 100.
local LEAF_GROUP = {}
for g, leaves in pairs(M.ANIM_GROUPS) do
	for _, l in ipairs(leaves) do
		LEAF_GROUP[l] = g
	end
end

function M.anim_path()
	local p = os.getenv("ANIM_FILE")
	if p ~= nil and p ~= "" then
		return p
	end
	return (M.state_path():match("^(.*)/[^/]*$") or ".") .. "/animations.json"
end

local function anim_curve_ok(id)
	return id == "config" or M.ANIM_CURVES[id] ~= nil
end

-- Pure: text -> {hyprEnabled=bool, hyprSpeed=n, hyprCurve=id, <group>Enabled/Speed/Curve} with only the
-- valid Hyprland keys that are set. Never raises.
function M.parse_anim(text)
	local a = {}
	if type(text) ~= "string" or #text > M.MAX_BYTES then
		return a
	end
	local body = text:match("^%s*(%b{})%s*$")
	if body == nil then
		return a
	end
	local function num(key)
		local tok = last_token(body, key)
		local v = tok and tok:match("^%-?%d[%d%.eE+%-]*$") and tonumber(tok)
		if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
			a[key] = math.max(M.ANIM_SPEED[1], math.min(M.ANIM_SPEED[2], v))
		end
	end
	local function bool(key)
		local tok = last_token(body, key)
		if tok == "true" then
			a[key] = true
		elseif tok == "false" then
			a[key] = false
		end
	end
	local function curve(key)
		local tok = last_token(body, key)
		local id = tok and tok:match('^"([%w_]+)"$')
		if id and anim_curve_ok(id) then
			a[key] = id
		end
	end
	bool("hyprEnabled")
	bool("launcherMotion")
	num("hyprSpeed")
	curve("hyprCurve")
	for g in pairs(M.ANIM_GROUPS) do
		bool(g .. "Enabled")
		num(g .. "Speed")
		curve(g .. "Curve")
	end
	return a
end

function M.read_anim()
	local ok, a = pcall(function()
		local text = M.read_small_file(M.anim_path())
		return text and M.parse_anim(text) or {}
	end)
	return ok and type(a) == "table" and a or {}
end

-- Springs ignore an animation's `speed` (measured 2026-10-20: identical motion at speed 0.5 and 5), so the speed
-- factor f is applied to the spring itself: time-scaling x'' = -(k/m)x - (c/m)x' by f gives k*f^2 and c*f (same
-- shape, f times faster). One curve per factor, "qs_<id>_<f*100>", registered by M.apply_anim.
-- curve id, factor -> curve name (and remembers it in M.anim_springs). Pure apart from that table.
M.anim_springs = {}
function M.spring_curve(cid, factor)
	local pct = math.max(1, math.floor(factor * 100 + 0.5))
	local name = "qs_" .. cid .. "_" .. pct
	if M.anim_springs[name] == nil then
		local c, f = M.ANIM_CURVES[cid], pct / 100
		M.anim_springs[name] = {
			type = "spring",
			mass = c.mass,
			stiffness = c.stiffness * f * f,
			dampening = c.dampening * f,
		}
	end
	return name
end

-- settings + one base leaf (animations.lua) -> the leaf spec to apply. Pure.
function M.anim_leaf(a, base, base_ms)
	local g = LEAF_GROUP[base.leaf]
	local factor = (a.hyprSpeed or 1) * (g and a[g .. "Speed"] or 1)
	local cid = (g and a[g .. "Curve"]) or a.hyprCurve or "config"
	local spec = {
		leaf = base.leaf,
		enabled = base.enabled ~= false and not (g and a[g .. "Enabled"] == false),
		speed = math.max(0.01, math.floor(base.speed / factor * 1000 + 0.5) / 1000),
		style = base.style,
	}
	-- a spring curve is referenced with `spring = <name>`; `bezier = <spring name>` fails with "no such bezier"
	-- (reported, not raised, and the leaf keeps its old values)
	if cid == "config" then
		spec.bezier, spec.spring = base.bezier, base.spring
	elseif M.ANIM_CURVES[cid].type == "spring" then
		local c = M.ANIM_CURVES[cid]
		spec.spring = M.spring_curve(cid, factor * (c.settle_ms or 200) / (base_ms or 200))
	else
		spec.bezier = "qs_" .. cid
	end
	return spec
end

M.anim_base_enabled = nil -- animations.enabled as the hand-written config set it (read at load)

-- settings -> applies them. force = false (config load): nothing at all when no key is set.
-- -> true, or false plus the first error.
function M.apply_anim(a, force)
	a = type(a) == "table" and a or {}
	if not force and next(a) == nil then
		return true
	end
	local okb, base = pcall(require, "hyprland.animations")
	if not okb or type(base) ~= "table" or type(base.leaves) ~= "table" then
		return false, "animations.lua not loaded"
	end
	local ok_all, first_err = true, nil
	local function note(ok, err)
		if not ok and ok_all then
			ok_all, first_err = false, err
		end
	end
	for id, c in pairs(M.ANIM_CURVES) do
		local def = {}
		for k, v in pairs(c) do
			if k ~= "settle_ms" then
				def[k] = v
			end
		end
		note(pcall(hl.curve, "qs_" .. id, def))
	end
	M.anim_springs = {}
	local specs = {}
	for i, b in ipairs(base.leaves) do
		specs[i] = M.anim_leaf(a, b, base.BASE_MS)
	end
	for name, c in pairs(M.anim_springs) do -- the scaled springs the leaves refer to
		note(pcall(hl.curve, name, c))
	end
	for _, spec in ipairs(specs) do
		note(pcall(hl.animation, spec))
	end
	-- launcher "Like popups" (Motion.qml launcherMotion): the launcher animates itself, so Hyprland's layer fade
	-- for qs-launcher is switched off (the qs-popup one is off for good in rules.lua)
	if M.launcher_noanim ~= nil then
		pcall(function()
			M.launcher_noanim:set_enabled(a.launcherMotion == true)
		end)
	end
	local en = a.hyprEnabled
	if en == nil then
		en = M.anim_base_enabled
	end
	if type(en) == "boolean" then
		note(pcall(hl.config, { animations = { enabled = en } }))
	end
	return ok_all, first_err
end

-- ---------------------------------------------------------------- apply

-- Keys this file has overridden since the config was loaded.
local overridden = {}

local function set_option(key, value)
	local section, name = M.OPTIONS[key]:match("^(%w+)%.(.+)$")
	return pcall(hl.config, { [section] = { [name] = value } })
end

-- ---------------------------------------------------------------- smart gaps (per monitor)

-- settings, monitor key -> is "lone window fills the screen" on for that monitor
-- (its smartMonitors entry, else smartGaps, else true).
function M.smart_for(s, key)
	s = type(s) == "table" and s or {}
	local m = s.smartMonitors
	if type(m) == "table" and key ~= nil and type(m[key]) == "boolean" then
		return m[key]
	end
	return s.smartGaps ~= false
end

-- The catch-all rules (every monitor) are on only while no monitor is switched off explicitly, so
-- they cover monitors without their own rules (connected later, rules not registered yet).
function M.catch_all_on(s)
	s = type(s) == "table" and s or {}
	if s.smartGaps == false then
		return false
	end
	if type(s.smartMonitors) == "table" then
		for _, v in pairs(s.smartMonitors) do
			if v == false then
				return false
			end
		end
	end
	return true
end

-- HL.Monitor -> its smartMonitors key: the description, else the connector name; nil if neither is valid.
function M.monitor_key(mon)
	local ok, key = pcall(function()
		if M.valid_key(mon.description) then
			return mon.description
		end
		if M.valid_key(mon.name) then
			return mon.name
		end
		return nil
	end)
	return ok and key or nil
end

-- HL.Monitor (+ every connected monitor) -> the m[...] selector body for its rules:
-- "desc:<description>" when that selects exactly this monitor, else the connector name.
-- Hyprland's desc: selector is a PREFIX match that returns the first monitor found, so identical
-- monitors (same description, e.g. no serial) or a description that is a prefix of another one get
-- connector-name selectors, as does a description with brackets or edge spaces (selector syntax).
-- nil when there is no usable selector.
function M.monitor_selector(mon, monitors)
	local ok, sel = pcall(function()
		local desc, name = mon.description, mon.name
		local use_desc = M.valid_key(desc) and desc:find("[%[%]]") == nil and desc:match("^%S.*%S$") ~= nil
		if use_desc then
			for _, o in ipairs(type(monitors) == "table" and monitors or {}) do
				local od = o.description
				if o.name ~= name and type(od) == "string" and od:sub(1, #desc) == desc then
					use_desc = false
				end
			end
		end
		if use_desc then
			return "desc:" .. desc
		end
		if M.valid_key(name) and name:find("[%[%]%s]") == nil then
			return name
		end
		return nil
	end)
	return ok and sel or nil
end

local function set_handles(handles, on)
	for _, h in ipairs(handles) do
		pcall(function()
			if h:is_enabled() ~= on then
				h:set_enabled(on)
			end
		end)
	end
end

-- Catch-all rule handles (HL.WorkspaceRule / HL.WindowRule), toggled at runtime.
local smart_rules = {}
M.smart_rules = smart_rules
-- Per-monitor rule sets, in registration order: { id, selector, key, handles = {...} }.
-- id = selector .. "\n" .. key (a connector-name selector can later belong to another monitor).
local smart_sets = {}
M.smart_sets = smart_sets
local smart_set_by_id = {}

-- Old API: every smart rule (catch-all and per monitor) on or off.
function M.set_smart(on)
	on = on ~= false
	set_handles(smart_rules, on)
	for _, set in ipairs(smart_sets) do
		set_handles(set.handles, on)
	end
end

local function track(list, fn, spec)
	local ok, h = pcall(fn, spec)
	if ok and h ~= nil then
		list[#list + 1] = h
	end
end

local function slug(text)
	return (text:gsub("[^%w]+", "-"))
end

-- Registers the four lone-window rules for one monitor: workspace rules m[<sel>]w[tv1] and
-- m[<sel>]f[1] (gaps 0) and window rules on the same selectors (border 0, rounding 0).
local function register_set(sel, key, on)
	local set = { id = sel .. "\n" .. key, selector = sel, key = key, handles = {} }
	local n = #smart_sets + 1
	smart_sets[n] = set
	smart_set_by_id[set.id] = set
	local wtv1, f1 = "m[" .. sel .. "]w[tv1]", "m[" .. sel .. "]f[1]"
	track(set.handles, hl.workspace_rule, { workspace = wtv1, gaps_out = 0, gaps_in = 0, enabled = on })
	track(set.handles, hl.workspace_rule, { workspace = f1, gaps_out = 0, gaps_in = 0, enabled = on })
	track(set.handles, hl.window_rule, {
		name = ("no-border-single-wtv1-m%d-%s"):format(n, slug(sel)),
		enabled = on,
		match = { float = false, workspace = wtv1 },
		border_size = 0,
		rounding = 0,
	})
	track(set.handles, hl.window_rule, {
		name = ("no-border-single-f1-m%d-%s"):format(n, slug(sel)),
		enabled = on,
		match = { float = false, workspace = f1 },
		border_size = 0,
		rounding = 0,
	})
	return set
end

-- -> the connected monitors as { selector, key } (nil when hl.get_monitors fails)
local function connected()
	local ok, mons = pcall(hl.get_monitors)
	if not ok or type(mons) ~= "table" then
		return nil
	end
	local out = {}
	for _, mon in ipairs(mons) do
		local key = M.monitor_key(mon)
		local sel = key and M.monitor_selector(mon, mons)
		if sel ~= nil then
			out[#out + 1] = { selector = sel, key = key }
		end
	end
	return out
end

-- Registers rule sets for connected monitors that have none yet (enabled per `s`), then sets every
-- rule's state: catch-all = M.catch_all_on(s); a monitor's set = M.smart_for(s, key) while it is
-- connected, off once its selector/key pair is gone (a connector name may now be another monitor).
-- If the monitor list cannot be read, the sets keep their monitors and only follow the settings.
-- -> number of sets registered now
function M.apply_smart(s)
	local mons = connected()
	local live, added = {}, 0
	for _, m in ipairs(mons or {}) do
		local id = m.selector .. "\n" .. m.key
		live[id] = true
		if smart_set_by_id[id] == nil and #smart_sets < M.SMART_SETS_MAX then
			pcall(register_set, m.selector, m.key, M.smart_for(s, m.key))
			added = added + 1
		end
	end
	set_handles(smart_rules, M.catch_all_on(s))
	for _, set in ipairs(smart_sets) do
		set_handles(set.handles, (mons == nil or live[set.id] == true) and M.smart_for(s, set.key))
	end
	return added
end

-- Is "no gaps for a single window" in force for this monitor right now? `mon` = HL.Monitor (or a bare
-- smartMonitors key). The rule set registered for the monitor decides (its smartMonitors entry, else
-- smartGaps, else true = M.smart_for); a monitor without a set falls under the catch-all rules
-- (M.catch_all_on). Re-reads the file. Used by scripts/pip-reserve.lua to let the pinned video box follow a
-- lone tiled window's zero gaps. Never raises; false on any failure (= the box keeps its gaps).
function M.smart_enabled(mon, s)
	local ok, on = pcall(function()
		s = type(s) == "table" and s or M.read()
		local key = type(mon) == "string" and mon or M.monitor_key(mon)
		if key ~= nil then
			for _, set in ipairs(smart_sets) do
				if set.key == key then
					return M.smart_for(s, key)
				end
			end
		end
		return M.catch_all_on(s)
	end)
	return ok and on == true
end

-- ---------------------------------------------------------------- bar-side gap (per monitor)

-- Settings > Bar > Backdrop "transparent when flush" (bars.json `transparentFlush`, per monitor) with a DOCKED bar: the bar
-- draws no backdrop, so the outer gap on the bar's own side (top for a top bar, bottom for a bottom bar) is 0 on that
-- monitor and tiled windows start right at the bar's reserved edge. The other three sides keep gaps_out. Done with
-- workspace rules on the monitor's selector, replaced in place (hl.workspace_rule with the same workspace string replaces
-- the rule) at every layout_apply(); Quickshell calls that after bars.json / appearance.json writes.
local BAR_FALLBACK = { ["DP-5"] = "bottom", ["DP-3"] = "bottom", ["Virtual-1"] = "bottom", ["HDMI-A-1"] = "top" }

-- HL.Monitor -> the bar's edge ("top" | "bottom" | "none") and whether transparentFlush is on for it. Mirrors
-- Quickshell BarConfig (monitors are matched by model and serial inside the description; the file is tiny and flat).
-- Never raises.
function M.bar_state(mon)
	local ok, edge, flush, pad, floating, respect = pcall(function()
		local text = M.read_small_file((os.getenv("HOME") or "") .. "/.local/state/quickshell/bars.json", 65536)
		if text then
			local desc = mon.description or ""
			for key, body in text:gmatch('"([^"]+)"%s*:%s*(%b{})') do
				local model, serial = key:match("^(.-)|(.*)$")
				-- a monitor without a model is keyed by its connector name (BarConfig.keyOf)
				if
					key == mon.name
					or (model and model ~= "" and desc:find(model, 1, true) and (serial == "" or desc:find(serial, 1, true)))
				then
					if not body:find('"enabled"%s*:%s*true') then
						return "none", false
					end
					return body:match('"edge"%s*:%s*"(%a+)"') == "top" and "top" or "bottom",
						body:find('"transparentFlush"%s*:%s*true') ~= nil,
						tonumber(body:match('"flushPadding"%s*:%s*(%d+)')),
						({ ["true"] = true, ["false"] = false })[body:match('"floating"%s*:%s*(%a+)') or ""],
						body:find('"respectReserved"%s*:%s*true') ~= nil
				end
			end
		end
		return BAR_FALLBACK[mon.name] or "none", false
	end)
	if ok then
		return edge, flush == true, pad, floating, respect == true
	end
	return "none", false, nil, nil, false
end

-- Is the bar on this monitor floating? Per bar (bars.json `floating`, Settings > Bar), else the global appearance.json
-- barFloating (the default for bars without their own value, same as Quickshell BarConfig.floating). `s` = settings.
function M.bar_floating(mon, s)
	s = type(s) == "table" and s or M.read()
	local _, _, _, floating = M.bar_state(mon)
	if type(floating) == "boolean" then
		return floating
	end
	return s.barFloating == true
end

M.CHIP_HEIGHT = 28 -- Theme.qml chipHeight
M.FLUSH_PAD_MIN, M.FLUSH_PAD_MAX, M.FLUSH_PAD_MANUAL_MAX = 8, 32, 48 -- BarConfig.qml flushPadMin / flushPadMax / flushPadManualMax

-- The bar's height on `mon` (-> number). A docked bar with "transparent when flush" is the chip height plus a padding: the
-- bars.json `flushPadding` number (0..48 total), else 3 x the visible window gap (2 x gaps_in) clamped to 8..32; even.
-- Mirrors Quickshell BarConfig.heightOf. Otherwise M.BAR_HEIGHT.
-- The screen space the bar on `mon` takes from its edge: its height plus the floating gap (gaps_out) when that bar floats.
-- Per bar, so two monitors may differ. -> number. Never raises (falls back to the plain docked bar).
function M.bar_reserve(mon, s)
	local ok, r = pcall(function()
		s = type(s) == "table" and s or M.read()
		local gap = 0
		if M.bar_floating(mon, s) then
			gap = M.effective(s).gapsOut or M.BAR_GAP_DEFAULT
		end
		return M.bar_height(mon, s) + gap
	end)
	return ok and type(r) == "number" and r or M.BAR_HEIGHT
end

function M.bar_height(mon, s)
	local ok, h = pcall(function()
		s = type(s) == "table" and s or M.read()
		if M.bar_flush_edge(mon, s) == nil then
			return M.BAR_HEIGHT
		end
		local _, _, pad = M.bar_state(mon)
		if pad == nil then
			local gi = M.targets(s).gaps_in
			if type(gi) ~= "number" then
				gi = type(M.baseline) == "table" and M.baseline.gaps_in or 0
			end
			gi = type(gi) == "number" and gi or 0
			pad = math.max(M.FLUSH_PAD_MIN, math.min(M.FLUSH_PAD_MAX, 3 * 2 * gi))
		end
		pad = math.max(0, math.min(M.FLUSH_PAD_MANUAL_MAX, pad))
		return M.CHIP_HEIGHT + (pad - pad % 2)
	end)
	return ok and math.tointeger(h) or M.BAR_HEIGHT
end

-- Is the bar-side gap 0 on this monitor? -> edge ("top" | "bottom") or nil. `s` = settings (read when nil).
function M.bar_flush_edge(mon, s)
	s = type(s) == "table" and s or M.read()
	if M.bar_floating(mon, s) then
		return nil
	end
	local edge, flush = M.bar_state(mon)
	if flush and (edge == "top" or edge == "bottom") then
		return edge
	end
	return nil
end

local bar_gap_seen = {}
-- Rules per monitor: A (>= 2 tiled windows, none maximized: the lone / maximized cases belong to the smart-gaps rules) always,
-- B (every workspace of the monitor) only where smart gaps are off, so a lone window follows the rule too.
function M.apply_bar_gaps(s)
	s = type(s) == "table" and s or M.read()
	local ok, mons = pcall(hl.get_monitors)
	if not ok or type(mons) ~= "table" then
		return false
	end
	local m = M.edge_margins(M.effective(s))
	local count = 0
	for _, mon in ipairs(mons) do
		local key = M.monitor_key(mon)
		local sel = key and M.monitor_selector(mon, mons)
		if sel ~= nil then
			local edge = M.bar_flush_edge(mon, s)
			local active = edge ~= nil
			if active or bar_gap_seen[sel] then
				if not bar_gap_seen[sel] then
					count = 0
					for _ in pairs(bar_gap_seen) do
						count = count + 1
					end
					if count >= M.SMART_SETS_MAX then
						goto continue
					end
				end
				bar_gap_seen[sel] = true
				local g = { top = m.top, right = m.right, bottom = m.bottom, left = m.left }
				if edge ~= nil then
					g[edge] = 0
				end
				pcall(hl.workspace_rule, { workspace = "m[" .. sel .. "]w[tv2-99]f[-1]", gaps_out = g, enabled = active })
				pcall(hl.workspace_rule, {
					workspace = "m[" .. sel .. "]",
					gaps_out = g,
					enabled = active and not M.smart_for(s, key),
				})
			end
		end
		::continue::
	end
	return true
end

-- settings -> writes the four options: set keys are written, keys that were overridden before and are
-- no longer set get their baseline back, everything else is left alone. -> true, or false plus the first error.
function M.apply_options(s)
	local t = M.targets(s)
	local ok_all, first_err = true, nil
	for _, key in ipairs(OPTION_ORDER) do
		local value = t[key]
		if value == nil and overridden[key] then
			value = M.baseline[key] -- nil when it could not be read: then leave it as it is
		end
		if value ~= nil then
			local ok, err = set_option(key, value)
			if ok then
				overridden[key] = t[key] ~= nil or nil
			elseif ok_all then
				ok_all, first_err = false, err
			end
		end
	end
	return ok_all, first_err
end

-- settings -> applies them: the four options (M.apply_options), the smart rules (M.apply_smart) and the
-- glass options from glass.json (M.apply_glass). -> true, or false plus the first error.
function M.apply(s)
	local ok_all, first_err = M.apply_options(s)
	pcall(function()
		M.apply_glass(M.read_glass())
	end)
	local ok, err = pcall(M.apply_smart, s)
	if not ok and ok_all then
		ok_all, first_err = false, err
	end
	pcall(M.apply_bar_gaps, s)
	return ok_all, first_err
end

-- ---------------------------------------------------------------- load

local initial = M.read()

pcall(M.capture_baseline)
pcall(M.capture_glass_base)
pcall(M.apply_options, initial)
pcall(function()
	M.apply_glass(M.read_glass())
end)
pcall(M.apply_glass_layer_alpha)
pcall(function()
	M.anim_base_enabled = hl.get_config("animations.enabled")
end)
pcall(function()
	M.launcher_noanim = hl.layer_rule({ match = { namespace = "qs-launcher" }, no_anim = true, enabled = false })
end)
pcall(M.apply_anim, M.read_anim(), false)

-- Smart gaps ("lone window fills the screen"): a lone tiled window gets no gaps and no border/rounding.
-- w[tv1] = exactly one visible tiled window; f[1] = one fullscreen-capable window. The gaps rules only
-- matter while gaps are non-zero. All rules are always registered and switched with set_enabled, so
-- layout_apply() can flip them at runtime.
-- 1. Catch-all (every monitor, the rules from before per-monitor settings): on while M.catch_all_on().
--    It covers monitors that have no rules of their own yet.
-- 2. One set per connected monitor, m[desc:<description>] (see M.monitor_selector): on per
--    M.smart_for(). Monitors that appear later (hot-plug, or not yet there when the config loads at
--    Hyprland start) get theirs from the monitor.added / hyprland.start events and from layout_apply().
do
	local smart_on = M.catch_all_on(initial)
	track(smart_rules, hl.workspace_rule, { workspace = "w[tv1]", gaps_out = 0, gaps_in = 0, enabled = smart_on })
	track(smart_rules, hl.workspace_rule, { workspace = "f[1]", gaps_out = 0, gaps_in = 0, enabled = smart_on })
	track(smart_rules, hl.window_rule, {
		name = "no-border-single-wtv1",
		enabled = smart_on,
		match = { float = false, workspace = "w[tv1]" },
		border_size = 0,
		rounding = 0,
	})
	track(smart_rules, hl.window_rule, {
		name = "no-border-single-f1",
		enabled = smart_on,
		match = { float = false, workspace = "f[1]" },
		border_size = 0,
		rounding = 0,
	})
end
pcall(M.apply_smart, initial)
pcall(M.apply_bar_gaps, initial)

-- Monitor hot-plug: register rules for new monitors (re-reads the file). The subscriptions of an
-- earlier load are removed first, in case a reload keeps the Lua state (no double handlers).
function M.on_monitors_changed()
	return pcall(function()
		local s = M.read()
		M.apply_smart(s)
		M.apply_bar_gaps(s)
	end)
end
do
	local old = rawget(_G, "__managed_smart_subs")
	if type(old) == "table" then
		for _, sub in ipairs(old) do
			pcall(function()
				sub:remove()
			end)
		end
	end
	local subs = {}
	for _, ev in ipairs({ "monitor.added", "monitor.removed", "hyprland.start" }) do
		local ok, sub = pcall(hl.on, ev, function()
			M.on_monitors_changed()
		end)
		if ok and sub ~= nil then
			subs[#subs + 1] = sub
		end
	end
	rawset(_G, "__managed_smart_subs", subs)
end

-- Global entry point for Quickshell: hyprctl eval "if layout_apply then layout_apply() end"
-- -> true, or false plus the error message.
function layout_apply()
	local ok, ok2, err = pcall(function()
		return M.apply((M.read()))
	end)
	if type(pip_bar_changed) == "function" then
		pcall(pip_bar_changed)
	end
	if not ok then
		return false, ok2
	end
	return ok2, err
end

-- Global entry point for Settings > Animations: hyprctl eval "if anim_apply then anim_apply() end"
-- -> true, or false plus the error message.
function anim_apply()
	local ok, ok2, err = pcall(function()
		return M.apply_anim(M.read_anim(), true)
	end)
	if not ok then
		return false, ok2
	end
	return ok2, err
end

return M
