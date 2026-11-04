-- Run: lua5.5 config/hypr/hyprland/tests/blurweather_test.lua   (pure module, no Hyprland needed)
local dir = arg[0]:match("^(.*)/tests/[^/]*$") or "."
local BW = dofile(dir .. "/blurweather.lua")

local fails, n = 0, 0
local function eq(got, want, name)
	n = n + 1
	if got ~= want then
		fails = fails + 1
		print(("FAIL %s: got %s, want %s"):format(name, tostring(got), tostring(want)))
	end
end
local function variant(s, t)
	local d = BW.decide(s, t)
	return d and d.variant or "none", d and d.rule or "-"   -- "kawase" + "default" = no rule matched (no solid glass)
end
local day = function(kind, temp) return { kind = kind, temp_c = temp or 15, is_day = true, aurora = false } end
local night = function(kind, temp, aurora) return { kind = kind, temp_c = temp or 15, is_day = false, aurora = aurora or false } end

-- every mapping branch
eq(variant(day("storm")), "drops", "storm variant")
eq(BW.decide(day("storm")).opts["drops:speed"], BW.SPEED.storm, "storm faster")
eq(BW.decide(day("rain")).opts["drops:speed"], BW.SPEED.rain, "rain speed")
eq(BW.SPEED.storm > BW.SPEED.rain, true, "storm > rain")
for _, k in ipairs({ "rain", "drizzle", "showers" }) do
	eq(variant(day(k)), "drops", k)
end
eq(variant(day("snow")), "frost", "snow")
eq(variant(day("clear", 0)), "frost", "cold at the threshold (<=)")
eq(variant(day("clear", 0.1)), "kawase", "just above cold")
eq(variant(day("clear", -12)), "frost", "very cold")
eq(variant(day("clear", 28)), "heat_shimmer", "hot at the threshold (>=)")
eq(variant(day("clear", 27.9)), "kawase", "just below hot")
eq(variant(day("partly", 35)), "heat_shimmer", "hot partly cloudy")
eq(variant(day("fog")), "haze", "fog")
eq(variant(day("cloudy")), "haze", "overcast")
eq(variant(night("clear")), "kawase", "clear night without geomagnetic activity = default")
eq(variant(night("clear", 15, true)), "aurora", "clear night + geomagnetic activity")
eq(variant(day("clear")), "kawase", "clear day = default")
eq(variant(night("partly")), "kawase", "partly night without geomagnetic activity")
eq(variant(night("partly", 15, true)), "aurora", "partly night + geomagnetic activity")
eq(variant(day("partly", 15, true)), "kawase", "geomagnetic activity by day does nothing")
eq(variant({ kind = "clear", temp_c = 15 }), "kawase", "unknown day/night = no aurora")
eq(variant({ kind = "unknown" }), "kawase", "unknown kind, no temperature")
eq(variant({}), "kawase", "empty state")
eq(BW.decide(nil), nil, "nil state")

-- no rule = the explicit default (solid glass where the running Hyprland has it, else kawase), never the saved variant
eq(select(2, variant(day("clear"))), "default", "default rule name")
eq(BW.decide(day("clear"), nil, true).variant, "solid_glass", "default with solid glass")
eq(BW.decide(day("clear"), nil, false).variant, "kawase", "default without solid glass")
eq(next(BW.decide(day("clear"), nil, true).opts), nil, "default sets no options")
eq(BW.decide(day("rain"), nil, true).variant, "drops", "a rule still beats the default")
local dflt = BW.compose({ variant = "acrylic", opts = { size = 6 } }, BW.decide(day("clear"), nil, true), "kawase", {})
eq(dflt.variant, "solid_glass", "default beats the saved variant while the weather is on")
eq(dflt.opts.size, 6, "default keeps saved options")

-- priority: first match wins
eq(variant(night("storm", -10, true)), "drops", "storm beats cold + aurora")
eq(select(2, variant(night("rain", 35))), "rain", "rain beats hot")
eq(select(2, variant(day("snow", 35))), "snow", "snow beats hot")
eq(select(2, variant(night("clear", -8, true))), "cold", "cold beats clear night")
eq(select(2, variant(night("clear", 30))), "hot", "hot beats clear night")
eq(select(2, variant(night("cloudy", 15, true))), "overcast", "overcast beats aurora night")
eq(select(2, variant(night("fog", 15, true))), "fog", "fog beats aurora night")
eq(select(2, variant(night("clear", 15, true))), "aurora night", "clear night + activity = aurora night")
eq(select(2, variant(night("clear"))), "default", "clear night alone = default")

-- custom thresholds
eq(variant(day("clear", 4), { cold_c = 5, hot_c = 28 }), "frost", "custom cold")
eq(variant(day("clear", 20), { cold_c = 0, hot_c = 18 }), "heat_shimmer", "custom hot")
eq(variant(day("clear", 4), { cold_c = -10, hot_c = 28 }), "kawase", "custom cold lower")
local t = BW.thresholds({ cold_c = 30, hot_c = 20 })
eq(t.cold_c < t.hot_c, true, "cold < hot after clamp")
eq(t.hot_c, 20, "hot wins")
eq(BW.thresholds({ cold_c = 10, hot_c = 10 }).cold_c, 9, "min gap")
eq(BW.thresholds({}).cold_c, BW.DEFAULTS.cold_c, "default cold")
eq(BW.thresholds({}).hot_c, BW.DEFAULTS.hot_c, "default hot")
eq(BW.thresholds(nil).hot_c, 28, "nil thresholds")
eq(BW.thresholds({ cold_c = "x", hot_c = 0 / 0 }).hot_c, 28, "garbage thresholds")
eq(BW.thresholds({ cold_c = -999, hot_c = 999 }).hot_c, BW.HOT_RANGE[2], "range clamp hot")
eq(BW.thresholds({ cold_c = -999 }).cold_c, BW.COLD_RANGE[1], "range clamp cold")
eq(BW.DEFAULTS.cold_c, 0, "default cold 0")
eq(BW.DEFAULTS.hot_c, 28, "default hot 28")

-- state file
local s = BW.parse_state('{"version":1,"enabled":true,"at":1000,"kind":"rain","tempC":-3.5,"isDay":false,"aurora":true,"coldC":2,"hotC":30}')
eq(s.enabled, true, "state enabled")
eq(s.kind, "rain", "state kind")
eq(s.temp_c, -3.5, "state temp")
eq(s.is_day, false, "state isDay")
eq(s.aurora, true, "state aurora")
eq(s.thresholds.cold_c, 2, "state cold")
eq(s.thresholds.hot_c, 30, "state hot")
eq(BW.parse_state("garbage").enabled, false, "garbage state")
eq(BW.parse_state(nil), nil, "nil state text")
eq(BW.parse_state('{"kind":"rain\\"x"}').kind, nil, "odd kind rejected")
eq(BW.parse_state('{"tempC":null,"isDay":null}').temp_c, nil, "null temp")
eq(BW.usable(s, 1100), true, "usable")
eq(BW.usable(s, 1000 + BW.MAX_AGE_S + 1), false, "too old")
eq(BW.usable(s, 0), false, "from the future")
eq(BW.usable({ enabled = false, kind = "rain", at = 1000 }, 1000), false, "switch off")
eq(BW.usable({ enabled = true, at = 1000 }, 1000), false, "no kind")
eq(BW.usable(nil, 0), false, "nil")

-- colours
eq(BW.argb("#102030", 0x29), 0x29102030, "argb")
eq(BW.argb("nope", 1), nil, "argb bad")
local pal = { accent = "#a650e3", accent2 = "#809cc6" }
local c = BW.theme_colours("aurora", {}, pal)
eq(c["aurora:color1"], 0x29A650E3, "aurora c1 = accent")
eq(c["aurora:color2"], 0x7A809CC6, "aurora c2 = accent2")
eq(BW.theme_colours("acrylic", {}, pal)["acrylic:tint"], 0x14A650E3, "acrylic tint")
eq(BW.theme_colours("fluid_jar", {}, pal)["fluid_jar:color"], 0xCCA650E3, "fluid colour")
eq(next(BW.theme_colours("solid_glass", {}, pal)), nil, "solid_glass untouched")
eq(next(BW.theme_colours("drops", {}, pal)), nil, "no colour on drops")
eq(next(BW.theme_colours("aurora", {}, {})), nil, "no palette = nothing")
local keep = BW.theme_colours("aurora", { ["aurora:color1"] = 123 }, pal)
eq(keep["aurora:color1"], nil, "explicit colour kept")
eq(keep["aurora:color2"], 0x7A809CC6, "other colour still filled")

-- colour values as hl.get_config / glass.json give them
eq(BW.colour_value("0x29F0A0FF"), 0x29F0A0FF, "colour 0x string (hl.get_config)")
eq(BW.colour_value("0X29f0a0ff"), 0x29F0A0FF, "colour 0X lower-case hex")
eq(BW.colour_value(689107199), 689107199, "colour integer")
eq(BW.colour_value(-1), 0xFFFFFFFF, "negative int32 = two's complement")
eq(BW.colour_value(-0x80000001), nil, "below int32")
eq(BW.colour_value(0x100000000), nil, "above 32 bits")
eq(BW.colour_value("rgba(F0A0FF29)"), 0x29F0A0FF, "rgba() string")
eq(BW.colour_value("rgb(F0A0FF)"), 0xFFF0A0FF, "rgb() string")
eq(BW.colour_value("689107199"), 689107199, "decimal string")
eq(BW.colour_value("-1"), 0xFFFFFFFF, "negative decimal string")
eq(BW.colour_value(1.5), nil, "fraction")
eq(BW.colour_value("0x123456789"), nil, "too many hex digits")
eq(BW.colour_value("garbage"), nil, "garbage string")
eq(BW.colour_value(""), nil, "empty string")
eq(BW.colour_value(true), nil, "boolean")
eq(BW.colour_value(nil), nil, "nil")
eq(BW.colour_value(0 / 0), nil, "NaN")
eq(BW.theme_colour("aurora:color2", pal), 0x7A809CC6, "theme colour of one key")
eq(BW.theme_colour("size", pal), nil, "no theme colour for a non-colour key")

-- compose: layers and the fallback
local base = BW.compose({ opts = {} }, nil, "solid_glass", pal)
eq(base.variant, "solid_glass", "fallback = base variant")
eq(next(base.opts), nil, "fallback has no options")
eq(BW.compose({ variant = "kawase", opts = {} }, nil, "solid_glass", pal).variant, "kawase", "fallback = saved variant")
local w = BW.compose({ variant = "kawase", opts = { size = 6 } }, BW.decide(night("clear", 15, true)), "solid_glass", pal)
eq(w.variant, "aurora", "weather variant wins over saved")
eq(w.weather, "aurora night", "rule reported")
eq(w.opts.size, 6, "saved option kept")
eq(w.opts["aurora:color1"], 0x29A650E3, "weather aurora gets theme colour")
eq(w.opts["aurora:speed"], BW.SPEED.aurora, "weather speed")
local sv = BW.compose({ opts = { ["drops:speed"] = 9 } }, BW.decide(day("rain")), "solid_glass", pal)
eq(sv.opts["drops:speed"], 9, "explicit saved speed beats weather")
local man = BW.compose({ variant = "acrylic", opts = { ["acrylic:tint"] = 5 } }, nil, nil, pal)
eq(man.opts["acrylic:tint"], 5, "manual explicit tint kept")
eq(BW.compose({ variant = "fluid_jar", opts = {} }, nil, nil, pal).opts["fluid_jar:color"], 0xCCA650E3, "manual pick gets theme colour")
eq(BW.compose(nil, nil, nil, pal).variant, nil, "nothing at all")

-- Weather.qml keeps the slider defaults / ranges / gap in its own prefs store: they must equal the ones here
do
	local f = io.open(dir .. "/../../quickshell/Weather.qml")
	local qml = f and f:read("a") or ""
	if f then
		f:close()
	end
	local dc, dh = qml:match("defaults: %(%{[^}]-coldC: (%-?%d+), hotC: (%-?%d+)")
	local c1, c2, h1, h2 = qml:match("spec: %(%{ coldC: %[(%-?%d+), (%-?%d+), %d+%], hotC: %[(%-?%d+), (%-?%d+), %d+%]")
	local gap = qml:match("minGapC: (%d+)")
	eq(tonumber(dc), BW.DEFAULTS.cold_c, "Weather.qml default cold")
	eq(tonumber(dh), BW.DEFAULTS.hot_c, "Weather.qml default hot")
	eq(tonumber(c1), BW.COLD_RANGE[1], "Weather.qml cold min")
	eq(tonumber(c2), BW.COLD_RANGE[2], "Weather.qml cold max")
	eq(tonumber(h1), BW.HOT_RANGE[1], "Weather.qml hot min")
	eq(tonumber(h2), BW.HOT_RANGE[2], "Weather.qml hot max")
	eq(tonumber(gap), BW.MIN_GAP_C, "Weather.qml gap")
end

print(("%d checks, %d failed"):format(n, fails))
os.exit(fails == 0 and 0 or 1)
