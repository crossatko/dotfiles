-- Ubisoft Connect-fronted games (confirmed with AC Shadows) leave both a
-- blank-titled "steam_app_<id>" window (Wine's own explorer.exe /desktop
-- helper) AND the whole Ubisoft Game Launcher process tree (upc.exe +
-- UplayWebCore.exe) running after the real game window closes -- Steam
-- keeps showing the game as "running" the entire time, since that's tied to
-- the launch tree actually exiting, not just the game's own window closing.
--
-- Own copy of is_game_window rather than shared with scripts/steam-tv-dim.lua
-- (same pattern as scripts/tv-manual-connect.lua): this only ever needs to
-- notice a game window closing, nothing else about it.
local function is_game_window(win)
	return (win.class or ""):match("^steam_app_%d+$") ~= nil
end

-- A window.close event for a titled "steam_app_<id>" window does NOT
-- reliably mean the game has quit for good -- confirmed live: it fired
-- while AC Shadows was still actually running (its window got destroyed and
-- recreated internally, most likely from a fullscreen/HDR mode transition),
-- and killing the launcher on that false signal left the game running with
-- no Ubisoft Connect layer at all -- it booted but couldn't reach online
-- services. So this re-checks fresh, right before acting, whether any
-- window of that same class still has a real title -- if the game's window
-- came back (same or new instance) within the delay, that's proof it never
-- actually quit, and nothing gets killed. Can't distinguish the leftover
-- ghost window from the legitimate blank-titled placeholder Steam briefly
-- shows before the real game window maps (same class, same blank title) by
-- class/title alone either -- that's still only ever handled once a REAL
-- (non-blank-titled) window of that class closes AND stays gone.
-- explorer.exe isn't part of upc.exe's own process tree (it's a sibling
-- under the same Wine prefix, not a child), so killing upc.exe doesn't take
-- it down -- both are killed here explicitly.
local function close_leftover_launcher_windows(class)
	for _, win in ipairs(hl.get_windows()) do
		if win.class == class and (win.title or "") ~= "" then
			-- The game is still (or newly) here -- abort, don't touch anything.
			return
		end
	end
	for _, win in ipairs(hl.get_windows()) do
		if win.class == class and (win.title or "") == "" then
			hl.dispatch(hl.dsp.window.kill({ window = "address:" .. win.address }))
		end
	end
	hl.exec_cmd("pkill -9 -f 'Ubisoft Game Launcher' >/dev/null 2>&1 &")
end

hl.on("window.close", function(win)
	local class = win.initial_class or win.class or ""
	local title = win.initial_title or win.title or ""
	if is_game_window({ class = class }) and title ~= "" then
		-- 5s, not a short settle delay: Ubisoft Connect keeps running after
		-- the game window closes to do its own cloud save sync (confirmed
		-- live -- upc.exe/UplayWebCore.exe still active well after the game
		-- exits), and it still needs the shared Wine desktop window this
		-- whole time. Killing that window (and the launcher) too early risks
		-- cutting the sync off mid-flight instead of just tidying up
		-- something that's already done being useful. It's also the window
		-- during which the re-check above can catch a false close.
		hl.timer(function()
			close_leftover_launcher_windows(class)
		end, { timeout = 5000, type = "oneshot" })
	end
end)
