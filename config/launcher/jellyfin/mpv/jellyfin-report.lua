-- Reports playback to Jellyfin (Playing / Progress / Stopped). Session files are written by
-- jellyfin-qs play: <prefix>.server (URL) and <prefix>.curl (curl config holding the auth header).
local prefix = mp.get_opt("jellyfin-qs-session")
if not prefix or prefix == "" then return end
local f = io.open(prefix .. ".server")
local server = f and f:read("*l")
if f then f:close() end
if not server then return end
local start = tonumber(mp.get_opt("jellyfin-qs-start") or "")
local cur, last, paused = nil, 0, false

local function ticks(s) return string.format("%d", math.floor((s or 0) * 10000000)) end
local function post(path, ev, sync)
  local body = string.format(
    '{"ItemId":"%s","MediaSourceId":"%s","PlayMethod":"DirectPlay","CanSeek":true,"IsPaused":%s,"PositionTicks":%s}',
    cur, cur, tostring(paused), ticks(last))
  local cmd = {name = "subprocess", playback_only = false, capture_stdout = true, capture_stderr = true,
    args = {"curl", "-sS", "--max-time", "5", "-K", prefix .. ".curl", "-X", "POST",
            "-H", "Content-Type: application/json", "-d", body, server .. path}}
  if sync then mp.command_native(cmd) else mp.command_native_async(cmd, function() end) end
end
local function stop()
  if cur then post("/Sessions/Playing/Stopped", nil, true); cur = nil end
end

mp.register_event("file-loaded", function()
  local p = mp.get_property("path") or ""
  cur = p:match("/Videos/(%w+)/stream") or p:match("/Audio/(%w+)/stream")
  if not cur then return end
  last, paused = 0, false
  if start then mp.commandv("seek", start, "absolute"); last = start; start = nil end
  post("/Sessions/Playing")
end)
mp.register_event("end-file", stop)
mp.register_event("seek", function()
  if cur then last = mp.get_property_number("time-pos") or last; post("/Sessions/Playing/Progress") end
end)
mp.observe_property("time-pos", "number", function(_, v) if v then last = v end end)
mp.observe_property("pause", "bool", function(_, v)
  paused = v and true or false
  if cur then post("/Sessions/Playing/Progress") end
end)
mp.add_periodic_timer(10, function() if cur then post("/Sessions/Playing/Progress") end end)
mp.register_event("shutdown", function()
  stop()
  for _, e in ipairs({".conf", ".curl", ".server", ".m3u"}) do os.remove(prefix .. e) end
end)
