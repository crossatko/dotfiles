-- Switching to a workspace via hl.dsp.focus({workspace=...}) only considers
-- that workspace's own tiled/floating members for the resulting focus. A
-- pinned window is visually present on every workspace of its monitor, but
-- isn't a "member" of any of them - so switching to a workspace that has
-- nothing but a pinned window on screen can leave focus stuck on whatever
-- was active before, on a completely different monitor.
--
-- Separately (confirmed live): switching to a workspace on a DIFFERENT
-- monitor than the currently-active PINNED window can silently drag that
-- window's monitor/workspace ownership along, and even reposition it -
-- confirmed via real keypress, not just a raw dispatch. This happens AFTER
-- the switch dispatch returns (checking synchronously right after misses
-- it - confirmed live, same class of timing issue as hl.timer's broken
-- one-shot mode here), so the check has to happen on a delay, via the shell.
--
-- Important: only cross-monitor switches are at risk. A pinned window is
-- visible on every workspace of its OWN monitor, so switching between that
-- monitor's own workspaces while it's focused is completely normal and must
-- NOT be touched - confirmed live, an earlier unconditional version of this
-- fix incorrectly snapped the view back to the old workspace after 0.3s in
-- exactly that case. The delayed check re-verifies the window's monitor
-- actually changed before restoring anything.
--
-- The restore's window.move dispatch is issued from an external hyprctl
-- process (via hl.exec_cmd), not from within this Lua runtime - confirmed
-- live it does NOT reliably re-trigger our own window.move_to_workspace
-- event hook, so scripts/pip-orientation.lua's reserved-area sync never
-- re-runs afterward, leaving the OTHER monitor's reservation stuck off.
-- Force a reload as part of the restore (same reload-staleness workaround
-- already used in scripts/pip-fix.lua) so it re-syncs.
return function(ws_num)
	local prev = hl.get_active_window()
	if prev ~= nil and prev.pinned and prev.monitor ~= nil and prev.workspace ~= nil then
		local target_ws = hl.get_workspace(ws_num)
		local same_monitor = target_ws ~= nil and target_ws.monitor ~= nil and target_ws.monitor.name == prev.monitor.name

		if not same_monitor then
			local selector = "address:" .. prev.address
			local cmd = string.format(
				"sleep 0.3; "
					.. "mon=$(hyprctl clients -j | python3 -c 'import json,sys;d=json.load(sys.stdin);m=[w[\"monitor\"] for w in d if w[\"address\"]==\"%s\"];print(m[0] if m else -1)'); "
					.. "if [ \"$mon\" != \"%d\" ]; then "
					.. "hyprctl dispatch \"hl.dsp.window.move({window='%s', workspace=%d, silent=true})\"; "
					.. "hyprctl dispatch \"hl.dsp.window.resize({window='%s', x=%d, y=%d})\"; "
					.. "hyprctl dispatch \"hl.dsp.window.move({window='%s', x=%d, y=%d})\"; "
					.. "hyprctl reload; "
					.. "fi",
				prev.address,
				prev.monitor.id,
				selector,
				prev.workspace.id,
				selector,
				prev.size.x,
				prev.size.y,
				selector,
				prev.at.x,
				prev.at.y
			)
			hl.exec_cmd(cmd)
		end
	end

	hl.dispatch(hl.dsp.focus({ workspace = ws_num }))

	local target_ws = hl.get_workspace(ws_num)
	if target_ws == nil or target_ws.monitor == nil then
		return
	end

	local active = hl.get_active_window()
	if active ~= nil and active.workspace ~= nil and active.workspace.id == ws_num then
		return
	end

	for _, w in ipairs(hl.get_windows()) do
		if w.pinned and w.monitor ~= nil and w.monitor.name == target_ws.monitor.name then
			hl.dispatch(hl.dsp.focus({ window = "address:" .. w.address }))
			return
		end
	end
end
