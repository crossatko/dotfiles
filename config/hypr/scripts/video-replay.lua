-- Play-once video wallpapers: EVERY workspace change on a monitor advances its clip by one burst (a short ease-in + wind-down
-- baked into the player's file; `theme.py video replay <connector>`, which ignores the event while the previous burst is
-- still playing: the debounce). See AGENTS.md "Video wallpapers".
--
-- Not a trigger: special workspaces (scratchpad toggles), loop mode / image wallpapers (the player has no socket: the command
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

local function on_active(ws)
	local ok, err = pcall(function()
		if ws == nil or ws.id == nil or ws.monitor == nil then
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
		hl.exec_cmd('sh -c \'python3 -I "$HOME/.config/theme/theme.py" video replay ' .. conn .. "'")
	end)
	if not ok then
		pcall(function() hl.log("video-replay: " .. tostring(err)) end)
	end
end

rawset(_G, "__video_replay_sub", hl.on("workspace.active", on_active))
