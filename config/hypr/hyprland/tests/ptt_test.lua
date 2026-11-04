-- Run: lua5.5 config/hypr/hyprland/tests/ptt_test.lua
-- ptt.lua (push-to-talk binds from Quickshell's state file) against a fake `hl`: hl.bind returns a handle whose
-- remove() drops only that bind (as Hyprland 0.57's HL.Keybind), a bad key string raises. Never reads the user's files:
-- QS_PTT_BINDS_FILE points at a temp file.
local dir = arg[0]:match("^(.*)/hyprland/tests/[^/]*$") or "."
package.path = dir .. "/?.lua;" .. package.path

local TMP = os.tmpname()
local real_getenv = os.getenv
os.getenv = function(k)
	if k == "QS_PTT_BINDS_FILE" then
		return TMP
	end
	return real_getenv(k)
end
local function write(t)
	local f = assert(io.open(TMP, "w"))
	f:write(t)
	f:close()
end

local binds = {} -- list of { keys, id, desc, alive }
_G.hl = {
	dsp = { global = function(id) return { global = id } end },
	bind = function(keys, action, opts)
		if keys:match("BAD") then
			error("invalid key")
		end
		local b = { keys = keys, id = action.global, desc = opts and opts.description, nc = opts and opts.non_consuming, alive = true }
		binds[#binds + 1] = b
		return { remove = function() b.alive = false end }
	end,
}
local function live()
	local out = {}
	for _, b in ipairs(binds) do
		if b.alive then
			out[#out + 1] = b.keys .. "=" .. tostring(b.id)
		end
	end
	table.sort(out)
	return table.concat(out, ",")
end
local fails = 0
local function eq(got, want, what)
	if got ~= want then
		fails = fails + 1
		print("FAIL " .. what .. ": got " .. tostring(got) .. ", want " .. tostring(want))
	end
end

-- another bind on the same key as a push-to-talk key: must survive every re-apply
hl.bind("SUPER + D", { global = "launcher" }, {})

write("# generated\nSUPER + D|quickshell:ptt-cs|Push-to-talk: Czech\nF9|quickshell:ptt-en\n\nnot a line\n|quickshell:ptt-cs-en|empty keys\nF7|quickshell:launcher|not ours\n")
local ptt = dofile(dir .. "/hyprland/ptt.lua")
eq(live(), "F9=quickshell:ptt-en,SUPER + D=launcher,SUPER + D=quickshell:ptt-cs", "load binds the file")
eq(binds[2].desc, "Push-to-talk: Czech", "description")
eq(binds[3].desc, "Push-to-talk quickshell:ptt-en", "default description")
eq(type(rawget(_G, "ptt_apply")), "function", "ptt_apply global")

eq(binds[2].nc, false, "consuming by default")

write("SUPER + mouse:276|quickshell:ptt-en|Push-to-talk: English|non_consuming\n")
eq(ptt_apply(), 1, "mouse apply")
eq(live(), "SUPER + D=launcher,SUPER + mouse:276=quickshell:ptt-en", "mouse bind")
eq(binds[#binds].nc, true, "non_consuming flag")
eq(binds[#binds].desc, "Push-to-talk: English", "description before flags")

write("SUPER + SHIFT + F9|quickshell:ptt-cs|Push-to-talk: Czech\n")
eq(ptt_apply(), 1, "apply count")
eq(live(), "SUPER + D=launcher,SUPER + SHIFT + F9=quickshell:ptt-cs", "re-apply replaces only our binds")

write("BAD|quickshell:ptt-cs\nF8|quickshell:ptt-en\nF6|quickshell:ptt-cs-en\n")
eq(ptt_apply(), 2, "a bad key is skipped, the lines after it still bind")
eq(live(), "F6=quickshell:ptt-cs-en,F8=quickshell:ptt-en,SUPER + D=launcher", "after bad key")

-- a last line without its newline may be cut off: never bound
write("F1|quickshell:ptt-cs|Push-to-talk: Czech\nF2|quickshell:ptt-en|Push-to-talk: Engl")
eq(ptt_apply(), 1, "a final line without a newline is dropped")
eq(live(), "F1=quickshell:ptt-cs,SUPER + D=launcher", "unterminated line not bound")
-- the cap reads as much as PttPrefs.parse (16 KB); a line cut by it is dropped
local filler = "# " .. string.rep("x", 100) .. "\n"
local pad = string.rep(filler, math.floor((ptt.MAX_BYTES - 200) / #filler))
write(pad .. "F3|quickshell:ptt-cs|ok\n" .. string.rep("# y\n", 120) .. "F4|quickshell:ptt-en|late\n")
eq(ptt.MAX_BYTES, 16384, "cap")
eq(ptt_apply(), 1, "a bind before the cap is kept, the cut line is not bound")
eq(live(), "F3=quickshell:ptt-cs,SUPER + D=launcher", "cut line")
write(pad .. string.rep("# y\n", 60) .. "F5|quickshell:ptt-cs|cut here" .. string.rep("z", 400))
ptt_apply()
eq(live(), "SUPER + D=launcher", "line cut mid-way is dropped")

os.remove(TMP)
eq(ptt_apply(), 0, "no file = no keys")
eq(live(), "SUPER + D=launcher", "no file")

-- parser edge cases
local P = ptt.parse
eq(#P("F1|quickshell:ptt-cs\nF2|quickshell:ptt-en\nF3|quickshell:ptt-cs-en\nF4|quickshell:ptt-cs\n"), 3, "one bind per id")
eq(#P("F1|quickshell:launcher\nF2|obs:record\nF3|quickshell:ptt-cs:x\nF4|quickshell:ptt-csxx\nF5|quickshell:ptt-c\nF6|quickshell:ptt-CS\nF7|quickshell:ptt-en-en\nF8|quickshell:ptt-cs-de\nF9|other:ptt-cs\nF10|quickshell:ptt-\nF11|quickshell:ptt-cs-\nF12|quickshell:ptt-cs-en-en\nF13|quickshell:ptt-auto-\nF14|quickshell:ptt-auto-cs\nF15|quickshell:ptt-auto-en-en\n"), 0, "unknown ids refused")
eq(#P("F1|quickshell:ptt-auto\nF2|quickshell:ptt-ja\nF3|quickshell:ptt-ja-en\nF4|quickshell:ptt-yue-en\nF5|quickshell:ptt-haw\nF7|quickshell:ptt-auto-en\n"), 6, "selected languages' ids accepted")
eq(#P("F1 ; exec|quickshell:ptt-cs\nF1)|quickshell:ptt-en\n"), 0, "bad key characters refused")
eq(#P(" + |quickshell:ptt-cs\n|quickshell:ptt-en\nF1\n"), 0, "empty keys / no id refused")
local d = P("SUPER + F9|quickshell:ptt-cs\nsuper+f9|quickshell:ptt-en\n")
eq(#d, 1, "duplicate key combo: first wins")
local c = P("  SUPER + F9  |  quickshell:ptt-cs  |  Czech  |  non_consuming  \r\n")[1]
eq(c and c.keys, "SUPER + F9", "trimmed keys, CRLF")
eq(c and c.desc, "Czech", "trimmed description")
eq(c and c.non_consuming, true, "trimmed flag")
eq(P("F9|quickshell:ptt-cs|x|not_non_consuming\n")[1].non_consuming, false, "flag is an exact word")
eq(P("F9|quickshell:ptt-cs|x|bogus,non_consuming\n")[1].non_consuming, true, "unknown flags ignored")

-- state path: override, XDG_STATE_HOME, HOME fallback
local env = {}
os.getenv = function(k) return env[k] end
env.HOME = "/home/u"
eq(ptt.path(), "/home/u/.local/state/quickshell/ptt-binds.txt", "path without XDG_STATE_HOME")
env.XDG_STATE_HOME = ""
eq(ptt.path(), "/home/u/.local/state/quickshell/ptt-binds.txt", "path with empty XDG_STATE_HOME")
env.XDG_STATE_HOME = "/s"
eq(ptt.path(), "/s/quickshell/ptt-binds.txt", "path with XDG_STATE_HOME")
env.QS_PTT_BINDS_FILE = "/o/b.txt"
eq(ptt.path(), "/o/b.txt", "override")
env.QS_PTT_BINDS_FILE = "/nonexistent-dir/x/ptt-binds.txt"
eq(ptt_apply(), 0, "missing state dir = no keys")
os.getenv = real_getenv

os.remove(TMP)
if fails > 0 then
	print(fails .. " failed")
	os.exit(1)
end
print("ok")
