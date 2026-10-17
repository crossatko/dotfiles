local function shell_quote(value)
	return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function build_menu_command()
	return [=[
current=$(pactl get-default-sink 2>/dev/null)
map_file=$(mktemp)
trap 'rm -f "$map_file"' EXIT

pactl list sinks 2>/dev/null |
awk -v current="$current" '
	BEGIN { RS=""; FS="\n" }
	function short_name(value) {
		if (value == "") return value
		sub(/ \(.*/, "", value)
		sub(/ Analog Stereo.*/, "", value)
		sub(/ Digital Stereo.*/, "", value)
		sub(/ Headphones \/.*/, "", value)
		return value
	}
	{
		name=""; desc=""
		for (i=1; i<=NF; i++) {
			if ($i ~ /^[[:space:]]*Name: /) {
				line=$i
				sub(/^[[:space:]]*Name: /, "", line)
				name=line
			}
			if ($i ~ /^[[:space:]]*Description: /) {
				line=$i
				sub(/^[[:space:]]*Description: /, "", line)
				desc=line
			}
		}
		if (name != "") {
			marker=(name == current ? "✓ " : "  ")
			if (desc == "") desc=name
			entry=marker short_name(desc) "\t" name
			if (name == current) {
				current_entry=entry
			} else {
				entries[++entry_count]=entry
			}
		}
	}
	END {
		if (current_entry != "") print current_entry
		for (i=1; i<=entry_count; i++) print entries[i]
	}
' > "$map_file"

choice=$(cut -f1 "$map_file" | ~/.config/quickshell/bin/qmenu --prompt-text 'Output: ')
[ -n "$choice" ] || exit 0

sink=$(awk -F '\t' -v choice="$choice" '$1 == choice { print $2; exit }' "$map_file")
[ -n "$sink" ] || exit 0

pactl set-default-sink "$sink"
pactl list short sink-inputs | cut -f1 | while read -r input; do
	[ -n "$input" ] && pactl move-sink-input "$input" "$sink"
done
]=]
end

local function show_sound_output_menu()
	-- Run asynchronously. Do not use io.popen here, it can block Hyprland.
	hl.exec_cmd("sh -c " .. shell_quote(build_menu_command()))
end

return {
	show_sound_output_menu = show_sound_output_menu,
}
