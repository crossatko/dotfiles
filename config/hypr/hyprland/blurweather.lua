-- Weather blur: which decoration:blur variant the weather asks for, and the theme colours of the colour variants.
-- PURE (no `hl`, no file access): managed.lua feeds it the state file Quickshell writes (WeatherBlur.qml) and applies
-- the result on top of the user's saved choice (glass.json "blur"), which this never changes. Tests: tests/blurweather_test.lua.
-- Every tunable number lives in this one file.
local M = {}

-- ---------------------------------------------------------------- tunables
-- Thresholds in degrees Celsius (Settings > Weather > Customise... edits them in the user's units, weather.json).
-- Weather.qml keeps the same defaults / ranges / gap for its sliders: tests/blurweather_test.lua asserts they match.
M.DEFAULTS = { cold_c = 0, hot_c = 28 }
M.MIN_GAP_C = 1 -- cold is always at least this far below hot
M.COLD_RANGE = { -40, 25 } -- sane limits of the two thresholds (same as the settings sliders)
M.HOT_RANGE = { 0, 50 }
M.MAX_AGE_S = 3 * 3600 -- a state older than this counts as "weather unavailable" (managed.lua also re-checks it by timer)
-- Moderate speeds: drops / heat shimmer / aurora cost GPU while animated (Hyprland's own defaults are 3 / 1 / 1).
M.SPEED = { rain = 2, storm = 4, heat = 0.8, aurora = 0.7 }

-- Weather kinds (bin/weather `kind`) per condition class.
M.KINDS = {
	storm = { storm = true },
	rain = { rain = true, drizzle = true, showers = true },
	snow = { snow = true },
	fog = { fog = true },
	overcast = { cloudy = true },
	clear = { clear = true },
}

-- Palette role and alpha (AARRGGBB, alpha = the option's upstream default) of every colour option of a variant.
-- solid_glass is left out: its tint is already theme-driven (glass.json tint_from_bg).
M.COLOURS = {
	aurora = { ["aurora:color1"] = { "accent", 0x29 }, ["aurora:color2"] = { "accent2", 0x7A } },
	acrylic = { ["acrylic:tint"] = { "accent", 0x14 } },
	fluid_jar = { ["fluid_jar:color"] = { "accent", 0xCC } },
}

-- ---------------------------------------------------------------- thresholds
local function clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

-- Pure: {cold_c, hot_c} (any may be missing / garbage) -> sane thresholds with cold < hot - MIN_GAP_C. When the pair
-- is out of order the hot one wins (cold is pushed down), so a hot-only edit never silently moves the other.
function M.thresholds(t)
	t = type(t) == "table" and t or {}
	local cold = tonumber(t.cold_c)
	local hot = tonumber(t.hot_c)
	cold = clamp(cold ~= nil and cold == cold and cold or M.DEFAULTS.cold_c, M.COLD_RANGE[1], M.COLD_RANGE[2])
	hot = clamp(hot ~= nil and hot == hot and hot or M.DEFAULTS.hot_c, M.HOT_RANGE[1], M.HOT_RANGE[2])
	if cold > hot - M.MIN_GAP_C then
		cold = hot - M.MIN_GAP_C
	end
	return { cold_c = cold, hot_c = hot }
end

-- ---------------------------------------------------------------- decision
-- Priority order, first match wins. `s` = {kind, temp_c (number|nil), is_day (boolean|nil), aurora (boolean)},
-- `t` = thresholds. A rule gives the variant and the options the weather sets (an option the user saved explicitly wins).
-- No rule matching = the DEFAULT: solid glass where the running Hyprland has it, else kawase (never the saved variant;
-- that one returns when the weather blur is off).
M.RULES = {
	{ name = "thunderstorm", variant = "drops", opts = { ["drops:speed"] = M.SPEED.storm },
		when = function(s) return M.KINDS.storm[s.kind] == true end },
	{ name = "rain", variant = "drops", opts = { ["drops:speed"] = M.SPEED.rain },
		when = function(s) return M.KINDS.rain[s.kind] == true end },
	{ name = "snow", variant = "frost", opts = {},
		when = function(s) return M.KINDS.snow[s.kind] == true end },
	{ name = "cold", variant = "frost", opts = {},
		when = function(s, t) return s.temp_c ~= nil and s.temp_c <= t.cold_c end },
	{ name = "hot", variant = "heat_shimmer", opts = { ["heat_shimmer:speed"] = M.SPEED.heat },
		when = function(s, t) return s.temp_c ~= nil and s.temp_c >= t.hot_c end },
	{ name = "fog", variant = "haze", opts = {},
		when = function(s) return M.KINDS.fog[s.kind] == true end },
	{ name = "overcast", variant = "haze", opts = {},
		when = function(s) return M.KINDS.overcast[s.kind] == true end },
	{ name = "clear night", variant = "aurora", opts = { ["aurora:speed"] = M.SPEED.aurora },
		when = function(s) return s.is_day == false and M.KINDS.clear[s.kind] == true end },
	-- a night that is not rainy / foggy / overcast (those matched above) with a geomagnetic storm strong enough for the latitude
	{ name = "aurora night", variant = "aurora", opts = { ["aurora:speed"] = M.SPEED.aurora },
		when = function(s) return s.is_day == false and s.aurora == true end },
}

M.DEFAULT = { rule = "default", glass = "solid_glass", plain = "kawase" }

-- Pure: weather state, thresholds, has_solid_glass (the running Hyprland has the solid_glass variant) -> {rule, variant,
-- opts}; nil only for a missing state (no weather effect: the saved blur stays).
function M.decide(s, t, has_solid_glass)
	if type(s) ~= "table" then
		return nil
	end
	t = M.thresholds(t)
	for _, r in ipairs(M.RULES) do
		if r.when(s, t) then
			local opts = {}
			for k, v in pairs(r.opts) do
				opts[k] = v
			end
			return { rule = r.name, variant = r.variant, opts = opts }
		end
	end
	return { rule = M.DEFAULT.rule, variant = has_solid_glass == true and M.DEFAULT.glass or M.DEFAULT.plain, opts = {} }
end

-- ---------------------------------------------------------------- state file
-- Pure: the state file text (flat JSON written by WeatherBlur.qml) -> state or nil.
--   {"version":1,"enabled":true,"at":<epoch>,"kind":"rain","tempC":12.5,"isDay":false,"aurora":true,"coldC":0,"hotC":28}
function M.parse_state(text)
	if type(text) ~= "string" or #text > 2048 then
		return nil
	end
	local function tok(key)
		local last
		for v in text:gmatch('"' .. key .. '"%s*:%s*("?[^,}%s"]*"?)') do
			last = v
		end
		return last
	end
	local s = { enabled = tok("enabled") == "true", at = tonumber(tok("at")) }
	local kind = tok("kind")
	s.kind = kind and kind:match('^"([a-z]+)"$') or nil
	s.temp_c = tonumber(tok("tempC"))
	local day = tok("isDay")
	if day == "true" or day == "false" then
		s.is_day = day == "true"
	end
	s.aurora = tok("aurora") == "true"
	s.thresholds = { cold_c = tonumber(tok("coldC")), hot_c = tonumber(tok("hotC")) }
	return s
end

-- Pure: is the state something to act on? (switch on, a recent answer, a known condition)
function M.usable(s, now)
	return type(s) == "table" and s.enabled == true and s.kind ~= nil and type(s.at) == "number"
		and now - s.at >= -60 and now - s.at <= M.MAX_AGE_S
end

-- ---------------------------------------------------------------- colours
-- Pure: "#rrggbb" -> AARRGGBB integer with `alpha`, nil when malformed
function M.argb(hex, alpha)
	local r, g, b = tostring(hex or ""):match("^#(%x%x)(%x%x)(%x%x)$")
	if not r then
		return nil
	end
	return (alpha << 24) | (tonumber(r, 16) << 16) | (tonumber(g, 16) << 8) | tonumber(b, 16)
end

-- Pure: a colour option value as hl.get_config / glass.json may give it -> AARRGGBB integer (0 .. 0xFFFFFFFF), nil when
-- it is not a colour. hl.get_config returns colours as the string "0xAARRGGBB"; also taken: an integer (a negative
-- one = its 32-bit two's complement), decimal digits, "0x"/"0X" hex, "rgba(RRGGBBAA)", "rgb(RRGGBB)".
function M.colour_value(v)
	local n
	if type(v) == "number" then
		n = math.tointeger(v)
	elseif type(v) == "string" then
		local t = v:match("^%s*(.-)%s*$")
		local hex = t:match("^0[xX](%x+)$")
		local rgba = t:match("^rgba%((%x%x%x%x%x%x%x%x)%)$")
		local rgb = t:match("^rgb%((%x%x%x%x%x%x)%)$")
		if hex and #hex <= 8 then
			n = tonumber(hex, 16)
		elseif rgba then
			n = (tonumber(rgba:sub(7, 8), 16) << 24) | tonumber(rgba:sub(1, 6), 16)
		elseif rgb then
			n = 0xFF000000 | tonumber(rgb, 16)
		elseif t:match("^%-?%d+$") and #t <= 11 then
			n = math.tointeger(tonumber(t))
		end
	end
	if n == nil then
		return nil
	end
	if n < 0 and n >= -0x80000000 then
		n = n + 0x100000000
	end
	return (n >= 0 and n <= 0xFFFFFFFF) and n or nil
end

-- Pure: the palette colour of one colour option (any variant's), nil when it has none or the palette lacks it
function M.theme_colour(key, palette)
	for _, cols in pairs(M.COLOURS) do
		local spec = cols[key]
		if spec then
			return M.argb((palette or {})[spec[1]], spec[2])
		end
	end
	return nil
end

-- Pure: the colour options of `variant` the saved blur does not set, taken from the palette ({accent = "#rrggbb", ...}).
-- Rule: a colour the user explicitly chose (present in saved_opts) is never replaced.
function M.theme_colours(variant, saved_opts, palette)
	local out = {}
	for key, spec in pairs(M.COLOURS[variant] or {}) do
		if (saved_opts or {})[key] == nil then
			local c = M.argb((palette or {})[spec[1]], spec[2])
			if c then
				out[key] = c
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------- compose
-- Pure: saved = {variant = name|nil, opts}, decision (M.decide or nil), base_variant (what settings.lua set, a name or
-- nil), palette -> {variant, opts, weather = rule name|nil}. Layers, later ones only fill what earlier ones leave open:
-- saved glass.json > weather options > theme colours; the variant is the weather's, else the saved, else the base.
function M.compose(saved, decision, base_variant, palette)
	saved = type(saved) == "table" and saved or {}
	local saved_opts = type(saved.opts) == "table" and saved.opts or {}
	local out = { opts = {} }
	for k, v in pairs(saved_opts) do
		out.opts[k] = v
	end
	out.variant = (decision and decision.variant) or saved.variant or base_variant
	if decision then
		out.weather = decision.rule
		for k, v in pairs(decision.opts) do
			if out.opts[k] == nil then
				out.opts[k] = v
			end
		end
	end
	for k, v in pairs(M.theme_colours(out.variant, out.opts, palette)) do
		out.opts[k] = v
	end
	return out
end

return M
