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
--   barFloating only matters for scripts/pip-reserve.lua (the bar reserve, see M.get())
--   scripts/pip-reserve.lua also keeps the pinned video box gaps_out away from the screen edges and the
--   bar (M.edge_margins()); layout_apply() re-fits it through pip_bar_changed()
-- A missing key leaves the hand-written value alone. Values are clamped and rounded; anything odd
-- (garbage, > 4 KiB, directory, FIFO, NaN, strings) counts as "not set".
--
-- Baseline: at load, before applying anything, the hand-written values of the four options are read
-- back with hl.get_config (M.baseline). layout_apply() writes them back for keys that this file had
-- overridden and that are no longer set (Settings > Appearance "Reset" writes {}).
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

-- settings -> applies them: the four options (M.apply_options) and the smart rules (M.apply_smart).
-- -> true, or false plus the first error.
function M.apply(s)
	local ok_all, first_err = M.apply_options(s)
	local ok, err = pcall(M.apply_smart, s)
	if not ok and ok_all then
		ok_all, first_err = false, err
	end
	return ok_all, first_err
end

-- ---------------------------------------------------------------- load

local initial = M.read()

pcall(M.capture_baseline)
pcall(M.apply_options, initial)

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

-- Monitor hot-plug: register rules for new monitors (re-reads the file). The subscriptions of an
-- earlier load are removed first, in case a reload keeps the Lua state (no double handlers).
function M.on_monitors_changed()
	return pcall(function()
		M.apply_smart((M.read()))
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

return M
