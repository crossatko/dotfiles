-- Run: lua5.5 config/hypr/hyprland/tests/managed_blur_test.lua
-- managed.lua's blur layers (saved glass.json blur, weather blur, theme colours) against a fake `hl` that behaves like
-- Hyprland 0.57's Lua API where it matters: hl.get_config returns colours as "0xAARRGGBB" strings, hl.config records a
-- config error for an unknown key or a bad value (it never raises), hl.timer returns an object with set_enabled, and a
-- reload resets every option to its default and starts a fresh Lua state (simulated by `boot`). Never reads the user's
-- files: os.getenv is redirected to temp files.
local dir = arg[0]:match("^(.*)/hyprland/tests/[^/]*$") or "."
package.path = dir .. "/?.lua;" .. package.path

local TMP = os.tmpname()
os.remove(TMP)
local GF, WF = TMP .. "-glass.json", TMP .. "-weather-blur.json"
local real_getenv = os.getenv
os.getenv = function(k)
	if k == "GLASS_FILE" then return GF end
	if k == "QS_WEATHER_BLUR_FILE" then return WF end
	if k == "APPEARANCE_FILE" then return TMP .. "-appearance.json" end
	if k == "ANIM_FILE" then return TMP .. "-anim.json" end
	if k == "HOME" or k == "XDG_STATE_HOME" then return TMP .. "-home" end
	return real_getenv(k)
end
local function write(p, t)
	if t == nil then
		os.remove(p)
		return
	end
	local f = assert(io.open(p, "w"))
	f:write(t)
	f:close()
end

local fails, n = 0, 0
local function check(name, cond, extra)
	n = n + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. name .. (extra ~= nil and (" [" .. tostring(extra) .. "]") or ""))
	end
end

-- fake theme: palette + the group bar colour function (records the glass flag it was asked for)
local PAL = { accent = "#a650e3", accent2 = "#809cc6", bg = "#101010" }
local groupbar_calls = {}
local function fake_theme()
	package.loaded["hyprland.theme"] = {
		colors = PAL,
		groupbar_colors = function(glass)
			groupbar_calls[#groupbar_calls + 1] = glass
			return { active = "0xff000000", inactive = "0xff000000", locked_active = "0xff000000", locked_inactive = "0xff000000" }
		end,
	}
end

local VARIANT_IDS = { kawase = 0, frost = 1, drops = 3, heat_shimmer = 7, acrylic = 8, aurora = 9, haze = 10, solid_glass = 11 }
local COLOUR_KEYS = {
	["decoration.blur.aurora.color1"] = true, ["decoration.blur.aurora.color2"] = true,
	["decoration.blur.acrylic.tint"] = true, ["decoration.blur.fluid_jar.color"] = true,
}
-- what settings.lua + Hyprland's defaults leave (a reload resets to this)
local SETTINGS = {
	["decoration.blur.enabled"] = true, ["decoration.blur.variant"] = 0, ["decoration.blur.size"] = 8,
	["decoration.blur.drops.speed"] = 3, ["decoration.blur.heat_shimmer.speed"] = 1, ["decoration.blur.aurora.speed"] = 1,
	["decoration.blur.aurora.color1"] = 0x29F0A0FF, ["decoration.blur.aurora.color2"] = 0x7A4DFFFF,
	["decoration.blur.acrylic.tint"] = 0x14EEF5FF, ["decoration.blur.acrylic.refraction"] = 24,
	["decoration.blur.fluid_jar.color"] = 0xCC3399FF, ["decoration.blur.glass.refraction"] = 20,
	["decoration.blur.haze.intensity"] = 0.35, ["decoration.blur.solid_glass.refraction"] = 1,
	["group.groupbar.col.active"] = "", ["group.groupbar.col.inactive"] = "", ["group.groupbar.col.locked_active"] = "",
	["group.groupbar.col.locked_inactive"] = "",
}

local H -- the fake compositor of the current boot
local function colour_parse(v)
	if math.type(v) == "integer" and v >= 0 and v <= 0xFFFFFFFF then return v end
	if type(v) == "string" then
		local hex = v:match("^0x(%x+)$")
		if hex and #hex <= 8 then return tonumber(hex, 16) end
		if v:match("^%d+$") then
			local x = math.tointeger(tonumber(v))
			if x and x <= 0xFFFFFFFF then return x end
		end
	end
	return nil
end
local function new_hl(opts)
	opts = opts or {}
	local h = { store = {}, errors = {}, calls = 0, timers = {}, getter = opts.getter, raise_on = nil }
	for k, v in pairs(SETTINGS) do
		h.store[k] = v
	end
	for k, v in pairs(opts.set or {}) do
		h.store[k] = v
	end
	for _, k in ipairs(opts.drop or {}) do
		h.store[k] = nil
	end
	h.api = {
		get_config = function(k)
			if h.getter then
				local over = h.getter(k)
				if over ~= nil then return over end
			end
			local v = h.store[k]
			if v ~= nil and COLOUR_KEYS[k] then return ("0x%08X"):format(v) end
			return v
		end,
		config = function(t)
			h.calls = h.calls + 1
			local function walk(pre, tb)
				for k, v in pairs(tb) do
					local p = pre == "" and k or pre .. "." .. k
					if h.raise_on and p == h.raise_on then error("raised on " .. p) end
					if type(v) == "table" then
						walk(p, v)
					elseif h.store[p] == nil then
						h.errors[#h.errors + 1] = "unknown " .. p
					elseif p == "decoration.blur.variant" then
						if VARIANT_IDS[v] then h.store[p] = VARIANT_IDS[v] else h.errors[#h.errors + 1] = "bad variant " .. tostring(v) end
					elseif COLOUR_KEYS[p] then
						local c = colour_parse(v)
						if c then h.store[p] = c else h.errors[#h.errors + 1] = "bad colour " .. p .. "=" .. tostring(v) end
					else
						h.store[p] = v
					end
				end
			end
			walk("", t)
		end,
		timer = function(fn, o)
			local tm = { fn = fn, timeout = o.timeout, type = o.type, enabled = true }
			function tm:set_enabled(b) self.enabled = b end
			h.timers[#h.timers + 1] = tm
			return tm
		end,
		on = function() return nil end, animation = function() end, curve = function() end,
		layer_rule = function() return {} end, window_rule = function() return {} end, workspace_rule = function() end,
		get_monitors = function() return {} end,
	}
	return h
end

-- a Hyprland start or `hyprctl reload`: options back to SETTINGS, fresh Lua state, managed.lua loads again
local function boot(opts)
	H = new_hl(opts)
	_G.hl = H.api
	_G.weather_blur_apply, _G.blur_variant_changed = nil, nil
	for k in pairs(package.loaded) do
		if k:match("^hyprland%.") then package.loaded[k] = nil end
	end
	fake_theme()
	local M = dofile(dir .. "/hyprland/managed.lua")
	return M
end
local function variant_name()
	for name, id in pairs(VARIANT_IDS) do
		if H.store["decoration.blur.variant"] == id then return name end
	end
	return tostring(H.store["decoration.blur.variant"])
end
local function weather(kind, o)
	o = o or {}
	write(WF, ('{"version":1,"enabled":%s,"at":%d,"kind":"%s","tempC":%s,"isDay":%s,"aurora":false,"coldC":0,"hotC":28}')
		:format(o.enabled or "true", o.at or os.time(), kind, o.temp or "15", o.day or "true"))
end
local function live_timers()
	local c = 0
	for _, t in ipairs(H.timers) do
		if t.enabled then c = c + 1 end
	end
	return c
end

-- ---------------------------------------------------------------- base, saved, rules, default
write(GF, '{"version":1,"blur":{"variant":"acrylic","size":6}}')
write(WF, nil)
local M = boot()
check("base variant from settings", M.blur_base.variant == "kawase", M.blur_base.variant)
check("base colour captured from the 0x string", M.blur_base.opts["aurora:color1"] == 0x29F0A0FF, M.blur_base.opts["aurora:color1"])
check("base speed captured", M.blur_base.opts["drops:speed"] == 3)
check("saved variant at load", variant_name() == "acrylic")
check("saved size at load", H.store["decoration.blur.size"] == 6)
check("acrylic tint from the palette", H.store["decoration.blur.acrylic.tint"] == 0x14A650E3, H.store["decoration.blur.acrylic.tint"])

weather("rain")
check("weather_blur_apply ok", weather_blur_apply() == true)
check("rain -> drops", variant_name() == "drops")
check("rain speed", H.store["decoration.blur.drops.speed"] == 2)
check("saved size kept under the weather", H.store["decoration.blur.size"] == 6)

weather("clear")
weather_blur_apply()
check("no rule -> solid glass default (has it)", variant_name() == "solid_glass", variant_name())
check("default is not the saved variant", variant_name() ~= "acrylic")
check("drops speed back to base after the rule ended", H.store["decoration.blur.drops.speed"] == 3)

weather("clear", { enabled = "false" })
weather_blur_apply()
check("switch off -> saved variant", variant_name() == "acrylic")
check("glass.json never written", io.open(GF):read("a") == '{"version":1,"blur":{"variant":"acrylic","size":6}}')
check("no config errors so far", #H.errors == 0, table.concat(H.errors, "; "))

-- stock (no solid_glass): the default is kawase
write(GF, '{"version":1,"blur":{"variant":"haze"}}')
M = boot({ drop = { "decoration.blur.solid_glass.refraction" } })
weather("clear")
weather_blur_apply()
check("no rule -> kawase default (stock)", variant_name() == "kawase", variant_name())
write(WF, nil)
weather_blur_apply()
check("no file -> saved haze", variant_name() == "haze")

-- ---------------------------------------------------------------- colour capture: string / negative / garbage
for _, case in ipairs({
	{ "garbage string", "nonsense", nil },
	{ "negative integer", -1, 0xFFFFFFFF },
	{ "rgba() string", "rgba(F0A0FF29)", 0x29F0A0FF },
	{ "fraction", 1.5, nil },
	{ "table", {}, nil },
}) do
	write(GF, '{"version":1,"blur":{"variant":"kawase"}}')
	write(WF, nil)
	M = boot({ getter = function(k) if k == "decoration.blur.aurora.color1" then return case[2] end end })
	H.getter = nil -- only the capture at load sees the odd value
	check("capture " .. case[1], M.blur_base.opts["aurora:color1"] == case[3], M.blur_base.opts["aurora:color1"])
	weather("clear", { day = "false" })
	weather_blur_apply()
	check("capture " .. case[1] .. ": aurora", variant_name() == "aurora")
	weather("clear", { enabled = "false" })
	weather_blur_apply()
	check("capture " .. case[1] .. ": variant reverted", variant_name() == "kawase", variant_name())
	check("capture " .. case[1] .. ": no config error", #H.errors == 0, table.concat(H.errors, "; "))
	if case[3] == nil then
		check("capture " .. case[1] .. ": colour not restored from a bad value", H.store["decoration.blur.aurora.color1"] == 0x29A650E3)
	else
		check("capture " .. case[1] .. ": colour restored", H.store["decoration.blur.aurora.color1"] == case[3])
	end
	check("capture " .. case[1] .. ": other colour restored", H.store["decoration.blur.aurora.color2"] == 0x7A4DFFFF)
end

-- one key that makes hl.config raise cannot block the variant revert
write(GF, '{"version":1,"blur":{"variant":"kawase"}}')
M = boot()
weather("clear", { day = "false" })
weather_blur_apply()
H.raise_on = "decoration.blur.aurora.color2"
weather("clear", { enabled = "false" })
check("raising key contained", pcall(weather_blur_apply))
check("variant reverted despite the raising key", variant_name() == "kawase", variant_name())
check("other key still restored", H.store["decoration.blur.aurora.color1"] == 0x29F0A0FF)
H.raise_on = nil
-- an invalid saved value is skipped, the rest applies
check("blur_value rejects garbage colour", M.blur_value("aurora:color1", "nope") == nil)
check("blur_value clamps", M.blur_value("drops:speed", 99) == 10)
check("blur_value bool", M.blur_value("xray", 1) == true and M.blur_value("xray", 0) == false)
check("blur_value unknown key", M.blur_value("nope", 1) == nil)
H.errors = {}
check("apply_blur skips a bad value", M.apply_blur({ variant = "frost", opts = { ["aurora:color1"] = "bad", size = 5 } }))
check("apply_blur: rest applied", variant_name() == "frost" and H.store["decoration.blur.size"] == 5)
check("apply_blur: no config error from the bad value", #H.errors == 0, table.concat(H.errors, "; "))

-- ---------------------------------------------------------------- runtime expiry (shell gone)
write(GF, '{"version":1,"blur":{"variant":"kawase"}}')
M = boot()
weather("rain")
weather_blur_apply()
check("expiry timer armed", live_timers() == 1, live_timers())
local tm = H.timers[#H.timers]
check("expiry timer oneshot", tm.type == "oneshot")
check("expiry timeout ~ MAX_AGE", math.abs(tm.timeout - (3 * 3600 + 5) * 1000) <= 2000, tm.timeout)
weather("rain")
weather_blur_apply()
check("a newer apply replaces the timer", live_timers() == 1 and not tm.enabled)
local tm2 = H.timers[#H.timers]
weather("rain", { at = os.time() - 3 * 3600 - 10 }) -- what the file looks like when the timer fires
tm.fn() -- a late, disabled one: no-op
check("stale timer is a no-op", variant_name() == "drops")
tm2.fn()
check("expiry restores the saved blur", variant_name() == "kawase", variant_name())
check("no timer while nothing is applied", live_timers() == 0, live_timers())
check("no hl.timer: no error", (function()
	H.api.timer = nil
	weather("rain")
	return pcall(weather_blur_apply)
end)())

-- ---------------------------------------------------------------- reload while the weather is applied
write(GF, '{"version":1,"blur":{"variant":"kawase"}}')
M = boot()
weather("storm")
weather_blur_apply()
check("storm before reload", variant_name() == "drops" and H.store["decoration.blur.drops.speed"] == 4)
M = boot() -- the reload: values reset, fresh Lua state, the file still says storm
check("base after reload = settings, not the weather", M.blur_base.variant == "kawase" and M.blur_base.opts["drops:speed"] == 3,
	tostring(M.blur_base.variant) .. " " .. tostring(M.blur_base.opts["drops:speed"]))
check("weather re-applied at load", variant_name() == "drops" and H.store["decoration.blur.drops.speed"] == 4)
weather("storm", { enabled = "false" })
weather_blur_apply()
check("off after reload -> saved + base speed", variant_name() == "kawase" and H.store["decoration.blur.drops.speed"] == 3)
check("capture refuses after the weather applied", (function()
	local b = M.blur_base
	M.blur_base = nil
	M.capture_blur_base()
	local refused = M.blur_base == nil
	M.blur_base = b
	return refused
end)())

-- ---------------------------------------------------------------- live changes from Settings > Blur
write(GF, '{"version":1,"blur":{"variant":"aurora","aurora:color1":123}}')
write(WF, nil)
M = boot()
check("explicit colour applied", H.store["decoration.blur.aurora.color1"] == 123)
groupbar_calls = {}
H.store["decoration.blur.enabled"] = false
blur_variant_changed({})
check("blur toggle recolours the group bar", #groupbar_calls == 1 and groupbar_calls[1] == false)
check("no colour fill without a variant change", H.store["decoration.blur.aurora.color1"] == 123)
write(GF, '{"version":1,"blur":{"variant":"aurora"}}') -- Settings reset removed the key
blur_variant_changed({ unset = { "aurora:color1" } })
check("reset colour back to the theme", H.store["decoration.blur.aurora.color1"] == 0x29A650E3, H.store["decoration.blur.aurora.color1"])
H.store["decoration.blur.variant"] = 8
blur_variant_changed()
check("variant change (no argument) fills theme colours", H.store["decoration.blur.acrylic.tint"] == 0x14A650E3)
check("no config errors in the live path", #H.errors == 0, table.concat(H.errors, "; "))

os.remove(GF)
os.remove(WF)
print(("%d checks, %d failed"):format(n, fails))
os.exit(fails == 0 and 0 or 1)
