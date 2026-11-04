-- Push-to-talk keys (Settings > Voice, Quickshell PttPrefs.qml). Quickshell registers the global shortcuts
-- (quickshell:ptt-cs, quickshell:ptt-en, quickshell:ptt-cs-en; PttShortcuts.qml) and writes the keys the user chose to a
-- generated state file OUTSIDE the repo, one bind per line, '#' lines are comments:
--   <keys>|<appid:name>|<description>[|<flags>]   e.g.  SUPER + F9|quickshell:ptt-cs|Push-to-talk: Czech
--                                                       mouse:276|quickshell:ptt-en|Push-to-talk: English|non_consuming
-- appid:name must be one of M.IDS (other lines are ignored); keys may be a mouse button (mouse:<evdev code>); flags:
-- "non_consuming" = the key / click also reaches the window (a mouse side button keeps working as back / forward).
-- ${XDG_STATE_HOME:-~/.local/state}/quickshell/ptt-binds.txt (QS_PTT_BINDS_FILE overrides; Hyprland must have the same
-- environment as the shell for that, tests only). No file / no line = no key
-- (there are no default keys). Read at every config load (so a reload or restart keeps the keys) and again by
-- `hyprctl eval 'ptt_apply()'`, which Quickshell runs after it rewrote the file: the binds made here are removed by
-- their own handle (Keybind:remove), never by hl.unbind(keys), which would also drop any other bind on that key.
-- Required with pcall from binds.lua: an error here must not cost the other binds.
local M = {}

M.MAX_BYTES = 4096
-- the only global shortcuts a line may bind (PttPrefs.qml entries, PttShortcuts.qml): a hand-edited or crafted file
-- cannot bind another app's shortcut
M.IDS = { ["quickshell:ptt-cs"] = true, ["quickshell:ptt-en"] = true, ["quickshell:ptt-cs-en"] = true }

function M.path()
	local p = os.getenv("QS_PTT_BINDS_FILE")
	if p ~= nil and p ~= "" then
		return p
	end
	local state = os.getenv("XDG_STATE_HOME")
	if state == nil or state == "" then
		state = (os.getenv("HOME") or "") .. "/.local/state"
	end
	return state .. "/quickshell/ptt-binds.txt"
end

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Pure: file text -> { {keys, id, desc, non_consuming}, ... }: only well-formed lines with a known id; the first line
-- wins for an id and for a key combo (compared without spaces and case)
function M.parse(text)
	local out, seen_id, seen_keys = {}, {}, {}
	for line in (text or ""):gmatch("[^\r\n]+") do
		if not line:match("^%s*#") then
			local f = {}
			for field in (line .. "|"):gmatch("([^|]*)|") do
				f[#f + 1] = trim(field)
			end
			local keys, id, desc, flags = f[1], f[2] or "", f[3] or "", f[4] or ""
			local norm = keys:upper():gsub("%s", "")
			if keys:match("^[%w_ +:]+$") and keys:match("%w") and M.IDS[id] and not seen_id[id] and not seen_keys[norm] then
				seen_id[id], seen_keys[norm] = true, true
				local nc = false
				for flag in flags:gmatch("[^%s,]+") do
					nc = nc or flag == "non_consuming"
				end
				out[#out + 1] = {
					keys = keys,
					id = id,
					desc = desc ~= "" and desc or ("Push-to-talk " .. id),
					non_consuming = nc,
				}
			end
		end
	end
	return out
end

function M.read()
	local f = io.open(M.path(), "r")
	if not f then
		return ""
	end
	local text = f:read(M.MAX_BYTES) or ""
	f:close()
	return text
end

-- handles of the binds made by the last apply (this Lua state only: a reload starts empty and binds from the file)
M.handles = {}

-- drop our binds, bind the file's lines; -> number of binds made
function M.apply()
	for _, h in ipairs(M.handles) do
		pcall(function()
			h:remove()
		end)
	end
	M.handles = {}
	for _, b in ipairs(M.parse(M.read())) do
		local ok, h = pcall(function()
			return hl.bind(b.keys, hl.dsp.global(b.id), { description = b.desc, non_consuming = b.non_consuming })
		end)
		if ok and h ~= nil then
			M.handles[#M.handles + 1] = h
		end
	end
	return #M.handles
end

rawset(_G, "ptt_apply", function()
	return M.apply()
end)

M.apply()

return M
