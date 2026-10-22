-- Wind-down for play-once video wallpapers, loaded by theme.py through mpvpaper's mpv options:
--   scripts=<this file> script-opts=winddown-timed=yes,winddown-play=S,winddown-wind=S,winddown-stop=S[,winddown-smooth=yes]
-- timed=yes (a play-once clip with a wind; play may be 0 = wind at once): the clip plays at full speed for `play`
-- seconds, then the speed eases from 1 to 0 over `wind` seconds (raised cosine, s(u) = (1 + cos(pi*u)) / 2,
-- u = elapsed / wind) and the video pauses, holding that frame. Media time advanced during the wind = integral of s
-- = wind * 0.5 (WIND_AVG in theme.py), so the stop point is play + wind / 2; theme.py computes it (winddown-stop, mpv
-- end=, and the still it puts under the player). This runtime ramp is the FALLBACK: once the per-monitor BAKED file
-- exists (theme.py bake_*: the wind retimed + interpolated into the file) it is swapped in and runs at speed 1.
-- timed=no: untimed play-once clips, baked files, loop players: only the replay / swap messages below.
-- `script-message winddown-restart` (sent by theme/mpv/replay.py = `theme.py video replay` over the input-ipc-server socket) replays
-- the clip from 0 with the same timing: speed 1, seek 0, unpause; end= and keep-open then hold it again. With a BAKED file
-- (winddown-bursts) a replay is the NEXT BURST: seek to its start, end= its end, unpause, advance (and persist) the station
-- index (see the block above `parse_bursts`); the bursts are short slow-motion pieces along the clip (ease-in, wind-down).
-- `script-message swap <file> [baked <bursts> <cyc> <tag> <station file>]` (theme.py, when the per-monitor optimized copy / baked
-- file has been encoded) switches to that file (same timeline) at a safe moment: loop = right after the wrap, once = at once
-- while the clip plays and is not winding down, else at the next replay (the held frame stays untouched; a swap that waited
-- for the replay starts in the burst). `baked` also turns the timer off and sets end= to where burst 0 starts (the first play
-- stops on H). winddown-loop=yes marks a looping player.
-- winddown-debug=yes logs every tick (wall s, speed, time-pos). winddown-smooth=yes + winddown-fps=<output Hz> turn on display-resample + frame interpolation for the wind only (see begin()).
local mp = require("mp")
local o = { timed = "no", play = 0, wind = 0, stop = 0, smooth = "no", debug = "no", fps = 0, loop = "no", bursts = "", cyc = 0, station = "", tag = "" }
require("mp.options").read_options(o, "winddown")

local play, wind = tonumber(o.play) or 0, tonumber(o.wind) or 0
local WIND_AVG = 0.5   -- mean speed of the curve; theme.py WIND_AVG
local stop_at = tonumber(o.stop) or 0
if stop_at <= 0 then stop_at = play + wind * WIND_AVG end
local timed = o.timed == "yes"   -- a timed play-once clip (play may be 0 = wind at once); baked files / untimed clips: no
local started, done, t0, timer = false, false, 0, nil
local function is_loop_player() return o.loop == "yes" end
local TICK = 1 / 60

local function finish()
    if done then return end
    done = true
    if timer then timer:kill() end
    mp.set_property_bool("pause", true)
    mp.set_property_number("speed", 1)
    if o.smooth == "yes" then mp.set_property("interpolation", "no") end
    local pos = mp.get_property_number("time-pos") or stop_at
    -- land on the exact frame theme.py took the still from (the timer is a few ms off)
    -- (end= is exclusive: the last frame shown is the one before stop_at, so one frame short is right)
    local frame = 1 / (mp.get_property_number("container-fps") or 30)
    if math.abs(pos - stop_at) > 1.5 * frame then
        mp.commandv("seek", string.format("%.3f", stop_at), "absolute+exact")
    end
    mp.msg.info(string.format("winddown: stopped at %.3f (planned %.3f)", pos, stop_at))
end

local function tick()
    local u = (mp.get_time() - t0) / wind
    if u >= 1 then return finish() end
    local s = math.max(0.01, 0.5 * (1 + math.cos(math.pi * u)))
    mp.set_property_number("speed", s)
    if o.debug == "yes" then
        mp.msg.info(string.format("wdtick %.3f %.3f %.3f", mp.get_time() - t0, s, mp.get_property_number("time-pos") or -1))
    end
end

local function begin()
    started = true
    mp.msg.info(string.format("winddown: wind starts at %.3f", mp.get_property_number("time-pos") or -1))
    if wind <= 0 then
        mp.set_property_bool("pause", true)
        return
    end
    -- smoothing only with the output's real refresh rate (winddown-fps, from theme.py): mpvpaper presents at the
    -- output's frame callbacks, but with display-resample mpv paces the video by display-fps-override. A wrong
    -- override plays the wind at (callback rate / override) x speed: 60 on a 360 Hz output = 6x FASTER (measured),
    -- instead of slowing down. No known rate = no smoothing (plain speed ramp, always correct).
    local fps = tonumber(o.fps) or 0
    if o.smooth == "yes" and fps >= 24 then
        mp.set_property("video-sync", "display-resample")
        -- libmpv gets no display timing from mpvpaper (display-fps unavailable): without this override
        -- interpolation has no effect (measured: 4K30, display frames changing 1.0 with it, ~0.1-0.5 without)
        mp.set_property_number("display-fps-override", fps)
        mp.set_property("interpolation", "yes")
        mp.set_property("tscale", "linear")
    end
    t0 = mp.get_time()
    timer = mp.add_periodic_timer(TICK, tick)
end

mp.observe_property("time-pos", "number", function(_, pos)
    if timed and pos and not started and pos >= play then begin() end
end)

local pending, pending_baked, pending_args = nil, false, nil
local last_pos = 0

-- Baked file = [first play ... H][burst 0][burst 1] ... (theme.py bake_bursts): winddown-bursts = "t0/t1/.../tK" (the start of
-- every burst, then the end of the file), winddown-cyc = the burst the cycle continues at after the last one, winddown-station
-- = the file keeping the index of the NEXT burst ("<tag>:<index>", surviving a player restart; the runtime dir is per login),
-- winddown-tag = the baked file's name (a new bake starts at 0).
local function parse_bursts(str)
    local t = {}
    for x in string.gmatch(str or "", "[^/]+") do t[#t + 1] = tonumber(x) end
    return t
end
local bursts, cyc, tag = parse_bursts(o.bursts), tonumber(o.cyc) or 0, o.tag
local K = math.max(0, #bursts - 1)
local idx = 0

local function station_read()
    if o.station == "" then return 0 end
    local f = io.open(o.station, "r")
    if not f then return 0 end
    local txt = f:read("*a") or ""
    f:close()
    local t, i = string.match(txt, "^(.-):(%d+)%s*$")
    return (t == tag and tonumber(i)) or 0
end

local function station_write()
    if o.station == "" then return end
    local f = io.open(o.station, "w")
    if f then f:write(tag .. ":" .. idx .. "\n") f:close() end
end
if K > 0 then idx = station_read() % K end

-- start burst `idx`: stop at its end (the next burst's start = the same frame, held by keep-open), advance the station
local function burst_play()
    local i = idx
    mp.set_property("end", (i + 1 < K) and string.format("%.4f", bursts[i + 2]) or "none")
    mp.commandv("seek", string.format("%.4f", bursts[i + 1]), "absolute+exact")
    idx = i + 1
    if idx >= K then idx = cyc end
    station_write()
    mp.msg.info(string.format("winddown: burst %d of %d (%.3f - %.3f), next %d", i, K, bursts[i + 1], bursts[i + 2], idx))
end

local function swap(start)
    local path = pending
    pending = nil
    local replay = false
    if pending_baked then
        local a = pending_args
        bursts, cyc, K = parse_bursts(a.bursts), tonumber(a.cyc) or 0, math.max(0, #parse_bursts(a.bursts) - 1)
        if a.tag ~= tag then tag = a.tag; idx = 0 end
        o.station = a.station ~= "" and a.station or o.station
        if start == 0 and K > 0 then   -- a replay that waited for the swap: play the burst now
            start = bursts[idx + 1]
            replay = true
        else                           -- mid first play: the position carries over, the first play stops on H where burst 0 starts
            idx = 0
            station_write()
            mp.set_property("end", K > 0 and string.format("%.4f", bursts[1]) or "none")
        end
        pending_baked, timed = false, false
    end
    if replay then
        local i = idx
        mp.set_property("end", (i + 1 < K) and string.format("%.4f", bursts[i + 2]) or "none")
        idx = i + 1
        if idx >= K then idx = cyc end
        station_write()
    end
    mp.msg.info(string.format("winddown: swap to %s at %.3f", path, start))
    mp.commandv("loadfile", path, "replace", "-1", string.format("start=%.3f", start))
end

mp.register_script_message("swap", function(path, kind, bursts_arg, cyc_arg, tag_arg, station_arg)
    if not path or path == "" or path == mp.get_property("path") then return end
    pending = path
    pending_baked = kind == "baked"
    pending_args = { bursts = bursts_arg or "", cyc = cyc_arg or "0", tag = tag_arg or "", station = station_arg or "" }
    if not is_loop_player() and not started and mp.get_property_native("pause") ~= true then
        swap(mp.get_property_number("time-pos") or 0)
    end
end)

mp.register_script_message("winddown-restart", function()
    if timer then timer:kill() end
    started, done = false, false
    if o.smooth == "yes" then mp.set_property("interpolation", "no") end
    mp.set_property_number("speed", 1)
    if pending then
        swap(0)
    elseif K > 0 then   -- baked file: the next burst
        burst_play()
    else
        mp.commandv("seek", "0", "absolute+exact")
    end
    mp.set_property_bool("pause", false)
    mp.msg.info("winddown: restarted")
end)

-- loop players: switch files right after the wrap (the position jumps back)
mp.observe_property("time-pos", "number", function(_, pos)
    if not pos then return end
    if pending and o.loop == "yes" and last_pos - pos > 1 then swap(pos) end
    last_pos = pos
end)
