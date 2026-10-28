-- Play-once video wallpapers: EVERY workspace change on a monitor advances its clip by one burst (a short ease-in + wind-down
-- baked into the player's file; theme/mpv/replay.py <connector> = `theme.py video replay`, which ignores the event while the
-- previous burst is still playing: the debounce). See AGENTS.md "Wallpapers (per monitor, videos, links)".
-- Timing: Hyprland emits workspace.active synchronously in CMonitor::changeWorkspace right AFTER startAnimation() of the
-- old/new workspace, in the same main-loop iteration (before the first animated frame is rendered): the earliest hook.
--
-- Not a trigger: special workspaces (scratchpad toggles), loop mode / image wallpapers (no held play-once player: the command
-- does nothing). A workspace moved to another monitor fires `workspace.active` for the monitors whose active workspace
-- changed, which is exactly the rule: only a changed active workspace counts.
-- NB: hl.* monitors, workspaces and windows are USERDATA (type() is "userdata", not "table"): nil checks and pcall only.

-- A reload that keeps the Lua state must not leave the previous load's handler running next to this one
do
	local old = rawget(_G, "__video_replay_sub")
	if old ~= nil then
		pcall(function()
			old:remove()
		end)
	end
	rawset(_G, "__video_replay_sub", nil)
end

-- wallpaper_backend "engine" (theme.toml): the wallpaper engine replays its clips itself (config/quickshell/engine.qml);
-- out/wallpaper.json says which backend is active (a few hundred bytes, read per event: a backend switch needs no reload)
local function engine_backend()
	local ok, yes = pcall(function()
		local f = io.open((os.getenv("HOME") or "") .. "/.config/theme/out/wallpaper.json", "r")
		if not f then
			return false
		end
		local head = f:read(256) or ""
		f:close()
		return head:find('"backend": "engine"', 1, true) ~= nil
	end)
	return ok and yes
end

local function on_active(ws)
	local ok, err = pcall(function()
		if ws == nil or ws.id == nil or ws.monitor == nil or engine_backend() then
			return
		end
		local name = ws.name
		if type(name) == "string" and name:find("^special") then
			return
		end
		local conn = ws.monitor.name
		-- connector names only: the name goes into a shell command line
		if type(conn) ~= "string" or not conn:match("^[%w_.-]+$") or #conn > 40 then
			return
		end
		-- mpv/replay.py, not `theme.py video replay` (same code): ~5 ms to the unpause instead of ~50 (theme.py compiles 4k lines).
		-- exec_cmd already runs `/bin/sh -c`; `exec` drops the shell.
		hl.exec_cmd('exec python3 -I -S "$HOME/.config/theme/mpv/replay.py" ' .. conn)
	end)
	if not ok then
		pcall(function() hl.log("video-replay: " .. tostring(err)) end)
	end
end

rawset(_G, "__video_replay_sub", hl.on("workspace.active", on_active))
