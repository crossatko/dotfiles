-- MANAGED FILE: Quickshell Settings > Appearance (config/quickshell/Appearance.qml) controls what this
-- file does. Do not put hand-written settings here; set your own values in settings.lua / theme.lua /
-- workspaces.lua / rules.lua as usual. This file never edits them.
--
-- The data is NOT in the repo: ${XDG_STATE_HOME:-~/.local/state}/quickshell/appearance.json
-- (env override APPEARANCE_FILE), written only by Quickshell:
--   {"version":1,"radius":12,"gap":10,"edgeGap":10,"border":2,"barFloating":true,"smartGaps":true}
--
-- Override semantics: only keys PRESENT (and valid) in that file are applied, on top of the hand-written
-- config (hyprland.lua loads this file after settings/workspaces/rules, so it wins):
--   radius  -> decoration.rounding        (0-32)
--   gap     -> general.gaps_in = round(gap/2), and general.gaps_out = gap unless edgeGap is set   (0-32)
--   edgeGap -> general.gaps_out           (0-40)
--   border  -> general.border_size        (0-6)
--   smartGaps (default true) -> the "lone window fills the screen" rules below are enabled/disabled
--   barFloating only matters for scripts/pip-reserve.lua (the bar reserve, see M.get())
-- A missing key leaves the hand-written value alone. Values are clamped and rounded; anything odd
-- (garbage, > 4 KiB, directory, FIFO, NaN, strings) counts as "not set".
--
-- Baseline: at load, before applying anything, the hand-written values of the four options are read
-- back with hl.get_config (M.baseline). layout_apply() writes them back for keys that this file had
-- overridden and that are no longer set (Settings > Appearance "Reset" writes {}).
--
-- Runtime: Quickshell runs `hyprctl eval "if layout_apply then layout_apply() end"` after saving (and
-- `hyprctl reload config-only` when smartGaps changed). A config reload re-runs everything, so it
-- gives the same result.
--
-- Nothing in here may raise at config load: a Lua error there disables the rest of the config,
-- keybinds included. hyprland.lua and scripts/pip-reserve.lua also load it under pcall.
local M = {}
-- A failed load must not register the rules twice when pip-reserve.lua requires it again.
package.loaded[(...) or "hyprland.managed"] = M

M.BAR_HEIGHT = 40 -- the Quickshell bar (Theme.qml barHeight); scripts/pip-reserve.lua uses it
M.BAR_GAP_DEFAULT = 0 -- floating bar margin when neither gap nor edgeGap is set (theme.toml [settings] gap)
M.MAX_BYTES = 4096

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

-- Pure: text of appearance.json -> table with ONLY the keys that are set and valid
-- (radius, gap, edgeGap, border: integers; barFloating, smartGaps: booleans). Never raises.
-- No JSON library: the file is tiny and flat, so values are picked with patterns. Text that does not
-- look like one JSON object, or is larger than MAX_BYTES, yields {}.
function M.parse(text)
	local s = {}
	if type(text) ~= "string" or #text > M.MAX_BYTES then
		return s
	end
	local body = text:match("^%s*(%b{})%s*$")
	if body == nil then
		return s
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

-- settings -> what other Lua code needs (scripts/pip-reserve.lua): the set values plus
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

-- ---------------------------------------------------------------- apply

-- Keys this file has overridden since the config was loaded.
local overridden = {}

local function set_option(key, value)
	local section, name = M.OPTIONS[key]:match("^(%w+)%.(.+)$")
	return pcall(hl.config, { [section] = { [name] = value } })
end

-- Smart-gaps rule handles (HL.WorkspaceRule / HL.WindowRule), toggled at runtime.
local smart_rules = {}
M.smart_rules = smart_rules

function M.set_smart(on)
	on = on ~= false
	for _, h in ipairs(smart_rules) do
		pcall(function()
			if h:is_enabled() ~= on then
				h:set_enabled(on)
			end
		end)
	end
end

-- settings -> applies them: set keys are written, keys that were overridden before and are no longer
-- set get their baseline back, everything else is left alone. -> true, or false plus the first error.
function M.apply(s)
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
	M.set_smart(not (type(s) == "table" and s.smartGaps == false))
	return ok_all, first_err
end

-- ---------------------------------------------------------------- load

local initial = M.read()

pcall(M.capture_baseline)
pcall(M.apply, initial)

-- Smart gaps ("lone window fills the screen"), moved here from workspaces.lua / rules.lua: a lone
-- tiled window on ANY monitor gets no gaps and no border/rounding (the committed config limited the
-- gaps rule to the primary monitor). w[tv1] = exactly one visible tiled window; f[1] = one
-- fullscreen-capable window. The gaps rules only matter while gaps are non-zero. Always registered,
-- disabled when smartGaps is false, so layout_apply() can flip them at runtime with set_enabled.
do
	local smart_on = initial.smartGaps ~= false
	local function track(fn, spec)
		local ok, h = pcall(fn, spec)
		if ok and h ~= nil then
			smart_rules[#smart_rules + 1] = h
		end
	end
	track(hl.workspace_rule, { workspace = "w[tv1]", gaps_out = 0, gaps_in = 0, enabled = smart_on })
	track(hl.workspace_rule, { workspace = "f[1]", gaps_out = 0, gaps_in = 0, enabled = smart_on })
	track(hl.window_rule, {
		name = "no-border-single-wtv1",
		enabled = smart_on,
		match = { float = false, workspace = "w[tv1]" },
		border_size = 0,
		rounding = 0,
	})
	track(hl.window_rule, {
		name = "no-border-single-f1",
		enabled = smart_on,
		match = { float = false, workspace = "f[1]" },
		border_size = 0,
		rounding = 0,
	})
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

return M
