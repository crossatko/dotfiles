#!/usr/bin/env bash
# Screen recording toggle (wf-recorder + slurp). SHIFT+Print (hyprland/binds.lua -> screenrec-key.sh), the
# launcher record section and the bar's recording chip call it.
#
#   screenrec.sh region [opts]   pick a region with slurp and record it
#   screenrec.sh window [opts]   click a window (boxes of the windows on the visible workspaces)
#   screenrec.sh output [opts]   record the whole focused monitor, no selection
#   screenrec.sh stop            stop the running recording
#   screenrec.sh status          print the state file; exit 0 while recording, 1 otherwise
#
#   opts: --fps 30|60      constant frame rate (wf-recorder -r)
#         --format mp4|webm   mp4 = H.264 + AAC, webm = AV1 (GPU) or VP9 (CPU) + Opus
#         --audio | --no-audio   desktop audio (monitor of the default PipeWire/Pulse sink)
# Options not given come from the menu's saved choices, $XDG_STATE_HOME/quickshell/screenrec.conf
# (key=value lines fps=, format=, audio=; values are whitelisted, the file is never executed), else
# 60 fps, mp4, no audio. Invalid values are rejected (exit 2).
#
# Every start mode is a toggle: while a recording runs, any of them stops it instead. Stop = SIGINT to the
# recorder so it finalizes the file; this script waits for it and then sends a "Recording saved"
# notification. State: $XDG_RUNTIME_DIR/screenrec/state (key=value: pid, comm, wrapper, started, file,
# mode, audio, enc, codec, fps, format), written once the recorder runs and removed when it exits. A stale
# file (recorder gone) is cleaned up by the next call. Quickshell's bar chip reads the same file.
#
# Encoder: GPU by default. The render node of the GPU that drives the recorded monitor is used (sysfs
# connector -> card -> renderD*); NVIDIA -> *_nvenc, anything else -> *_vaapi (zero-copy dmabuf); the codec
# is h264 for mp4 and av1 for webm. CPU: libx264 (mp4) / libvpx-vp9 (webm). The capability probe (ffmpeg
# encoder list + vainfo / nvidia-smi) is cached per method, codec and node in the state dir. Small regions
# always use the CPU (tiny VCN encodes fail or even hang the encoder ring on RDNA4): h264 below GPU_MIN px
# per side, av1 below AV1_MIN_W x AV1_MIN_H. If the GPU recorder dies during startup, it is restarted on
# the CPU and a notification says so after the recording. Overrides: SCREENREC_ENCODER=auto|cpu|vaapi|nvenc
# (a forced GPU encoder skips the probe but still falls back), SCREENREC_DEVICE=/dev/dri/renderDxxx.
#
# Test overrides: REC_GEOM="x,y WxH" (skip slurp), REC_OUTPUT=<monitor>, SCREENREC_DIR (save dir),
# SCREENREC_RUNTIME_DIR (state dir), SCREENREC_PREFS (saved choices file), SCREENREC_RECORDER (recorder
# binary), SCREENREC_NOTIFY=0 (print to stderr instead of notifying).
set -uo pipefail

RUN_DIR=${SCREENREC_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/screenrec}
STATE=$RUN_DIR/state
LOCK=$RUN_DIR/lock
LOG=$RUN_DIR/last.log
PREFS=${SCREENREC_PREFS:-${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/screenrec.conf}
videos=$(xdg-user-dir VIDEOS 2>/dev/null)
[ -n "$videos" ] && [ "$videos" != "$HOME" ] || videos=$HOME/Videos
OUT_DIR=${SCREENREC_DIR:-$videos/Recordings}
RECORDER=${SCREENREC_RECORDER:-wf-recorder}
APP="Screen recording"

notify() { # notify <urgency> <summary> <body>
	if [ "${SCREENREC_NOTIFY:-1}" = 0 ] || ! command -v notify-send >/dev/null; then
		printf '%s: %s\n' "$2" "$3" >&2
	else
		notify-send -a "$APP" -i media-record -u "$1" "$2" "$3"
	fi
}

usage() {
	[ -n "${1:-}" ] && echo "${0##*/}: $1" >&2
	echo "usage: ${0##*/} region|window|output [--fps 30|60] [--format mp4|webm] [--audio|--no-audio] | stop | status" >&2
	exit 2
}

declare -A st=()
read_state() {
	st=()
	[ -f "$STATE" ] || return 1
	local k v
	while IFS='=' read -r k v; do [ -n "$k" ] && st[$k]=$v; done <"$STATE"
	[ -n "${st[pid]:-}" ]
}

# defaults from the recording menu's saved choices; unknown keys and values are ignored, nothing is executed
read_prefs() {
	local k v
	[ -f "$PREFS" ] && [ -r "$PREFS" ] || return 0
	while IFS='=' read -r k v || [ -n "$k" ]; do
		v=${v%$'\r'}
		case $k in
		fps) [ -z "$fps" ] && [[ $v =~ ^(30|60)$ ]] && fps=$v ;;
		format) [ -z "$format" ] && [[ $v =~ ^(mp4|webm)$ ]] && format=$v ;;
		audio) [ -z "$audio" ] && [[ $v =~ ^[01]$ ]] && audio=$v ;;
		esac
	done < <(head -c 4096 -- "$PREFS" 2>/dev/null)
}

# the recorder from the state file is still running (and the pid was not reused by something else)
alive() { # alive <pid> <comm>
	[ -n "$1" ] && [ -r "/proc/$1/comm" ] && [ "$(cat "/proc/$1/comm" 2>/dev/null)" = "$2" ]
}

fmt_dur() { local s=$1; printf '%d:%02d' $((s / 60)) $((s % 60)); }

saved_notice() { # saved_notice <file> <started epoch>
	local file=$1 dur size
	dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$file" 2>/dev/null)
	dur=${dur%.*}
	[[ $dur =~ ^[0-9]+$ ]] || dur=$(($(date +%s) - $2))
	size=$(du -h "$file" 2>/dev/null | cut -f1)
	if [ "${SCREENREC_NOTIFY:-1}" = 0 ] || ! command -v notify-send >/dev/null; then
		printf 'Recording saved: %s (%s, %s)\n' "$file" "$(fmt_dur "$dur")" "$size" >&2
		return
	fi
	# click or "Open folder" = show it in the file manager, "Play" = play it; notify-send waits for the
	# answer (max 1 h)
	local act
	act=$(timeout 3600 notify-send -a "$APP" -i video-x-generic -w \
		-A "default=Show in folder" -A "play=Play" -A "folder=Open folder" \
		"Recording saved" "${file/#$HOME/\~}  ·  $(fmt_dur "$dur")  ·  $size")
	case $act in
	default | folder) setsid -f nautilus --new-window --select "$file" >/dev/null 2>&1 ;;
	play) setsid -f mpv --force-window=yes "$file" >/dev/null 2>&1 ;;
	esac
}

stop_recording() {
	local pid=${st[pid]} comm=${st[comm]} wrapper=${st[wrapper]:-} i
	kill -INT "$pid" 2>/dev/null
	for i in $(seq 100); do alive "$pid" "$comm" || break; sleep 0.1; done      # finalizing can take a moment
	alive "$pid" "$comm" && { kill -TERM "$pid" 2>/dev/null; sleep 1; }
	# the wrapper that started it removes the state file and sends the notification; if it is gone, do it here
	for i in $(seq 30); do [ -f "$STATE" ] || return 0; sleep 0.1; done
	if [ -z "$wrapper" ] || ! [ -d "/proc/$wrapper" ]; then
		rm -f "$STATE"
		[ -s "${st[file]}" ] && saved_notice "${st[file]}" "${st[started]}"
	fi
}

geom_even() { # round W and H down to even numbers (yuv420p / libx264 need that)
	local g=$1 xy wh w h
	xy=${g%% *}; wh=${g##* }; w=${wh%x*}; h=${wh#*x}
	[[ $w =~ ^[0-9]+$ && $h =~ ^[0-9]+$ ]] || return 1
	w=$((w / 2 * 2)); h=$((h / 2 * 2))
	((w >= 16 && h >= 16)) || return 1
	printf '%s %dx%d' "$xy" "$w" "$h"
}

# --- encoder selection ---
GPU_MIN=128                    # h264: smallest side the GPU gets (RDNA4 VCN refuses 64 px, 200x32 hung the ring)
AV1_MIN_W=640 AV1_MIN_H=360    # av1: smallest tested size; anything smaller is recorded with VP9 on the CPU

# monitor whose area contains the top-left corner of the geometry (logical coordinates)
monitor_at() { # monitor_at <x,y WxH>
	local xy=${1%% *} x y
	x=${xy%%,*}; y=${xy#*,}
	[[ $x =~ ^-?[0-9]+$ && $y =~ ^-?[0-9]+$ ]] || return 1
	hyprctl monitors -j | jq -r --argjson x "$x" --argjson y "$y" '[.[]
		| (if .transform % 2 == 1 then [.height, .width] else [.width, .height] end) as $s
		| select($x >= .x and $y >= .y and $x < .x + $s[0] / .scale and $y < .y + $s[1] / .scale) | .name][0] // empty'
}

# render node of the GPU that drives a monitor (connector name, e.g. DP-1)
render_node_for() { # render_node_for <connector>
	local c card n
	for c in /sys/class/drm/card*-"$1"; do
		[ -e "$c" ] || continue
		card=${c##*/}; card=${card%%-*}
		for n in /sys/class/drm/"$card"/device/drm/renderD*; do
			[ -e "$n" ] && { echo "/dev/dri/${n##*/}"; return 0; }
		done
	done
	return 1
}

node_driver() { basename "$(readlink -f "/sys/class/drm/${1##*/}/device/driver" 2>/dev/null)" 2>/dev/null; }

# (output captured first: with pipefail, grep -q exiting early would SIGPIPE the producer and fail the test)
has_encoder() { local l; l=$(ffmpeg -hide_banner -encoders 2>/dev/null); [[ $l == *" $1 "* ]]; }

# can this node encode <codec> with the given method? cached per method, codec and node (state dir is
# tmpfs, so per boot)
probe() { # probe vaapi|nvenc h264|av1 <render node>
	local cache=$RUN_DIR/probe-$1-$2-${3##*/} r=no prof
	if [ -f "$cache" ]; then r=$(<"$cache"); else
		case $1 in
		vaapi)
			case $2 in av1) prof='VAProfileAV1Profile0' ;; *) prof='VAProfileH264(Main|High|ConstrainedBaseline)' ;; esac
			if [ -c "$3" ] && has_encoder "$2_vaapi"; then
				if ! command -v vainfo >/dev/null; then r=yes   # can't tell; the runtime fallback covers it
				elif grep -Eq "$prof"'[[:space:]]*:[[:space:]]*VAEntrypointEncSlice' \
					<<<"$(vainfo --display drm --device "$3" 2>/dev/null)"; then r=yes; fi
			fi
			;;
		nvenc) has_encoder "$2_nvenc" && grep -q '^GPU' <<<"$(nvidia-smi -L 2>/dev/null)" && r=yes ;;
		esac
		echo "$r" >"$cache"
	fi
	[ "$r" = yes ]
}

codec_of() { # codec_of cpu|vaapi|nvenc -> h264|av1|vp9 (for the current $format)
	case $format/$1 in
	mp4/*) echo h264 ;;
	webm/cpu) echo vp9 ;;
	*) echo av1 ;;
	esac
}

enc_args() { # enc_args cpu|vaapi|nvenc <render node> -> codec args, one per line (for the current $format)
	case $format/$1 in
	mp4/vaapi) printf '%s\n' -c h264_vaapi -d "$2" -p rc_mode=CQP -p qp=24 ;;   # wf-recorder adds scale_vaapi=format=nv12
	mp4/nvenc) printf '%s\n' -c h264_nvenc -p preset=p4 -p rc=vbr -p cq=24 -x yuv420p ;;
	mp4/*) printf '%s\n' -c libx264 -p preset=veryfast -p crf=23 -x yuv420p ;;
	webm/vaapi) printf '%s\n' -c av1_vaapi -d "$2" -p rc_mode=CQP -p global_quality=100 ;;   # AV1 q index 0-255
	webm/nvenc) printf '%s\n' -c av1_nvenc -p preset=p4 -p rc=vbr -p cq=32 -x yuv420p ;;
	webm/*) printf '%s\n' -c libvpx-vp9 -p deadline=realtime -p cpu-used=8 -p row-mt=1 -p crf=32 -p b=0 -x yuv420p ;;
	esac
}

# a pid that exists and is not a zombie (a dead child stays a zombie until we wait for it)
running() { local s; s=$(cat "/proc/$1/stat" 2>/dev/null) || return 1; s=${s##*) }; [ "${s%% *}" != Z ]; }

# start the recorder; returns 1 if it exited during startup (codec/device init failed)
start_recorder() { # start_recorder <args...>; sets pid
	"$RECORDER" "$@" </dev/null >"$LOG" 2>&1 9>&- &
	pid=$!
	local i
	# the encoder is opened on the first frame, then the output is announced ("Output #0, ...") and the
	# container header written (mp4 shows up in the file at once, webm stays in the write buffer); up to 2 s
	for i in $(seq 20); do
		running "$pid" || return 1
		[ -s "$file" ] && return 0
		grep -q '^Output #0' "$LOG" 2>/dev/null && { sleep 0.2; running "$pid"; return; }
		sleep 0.1
	done
	running "$pid"
}

need() { command -v "$1" >/dev/null || { notify critical "Can't record: $1 is missing" "Install it with: sudo pacman -S $2"; exit 1; }; }

cmd=${1:-region}
[ $# -gt 0 ] && shift
fps="" format="" audio=""
while [ $# -gt 0 ]; do
	case $1 in
	--audio) audio=1 ;;
	--no-audio) audio=0 ;;
	--fps=*) fps=${1#*=} ;;
	--fps) [ $# -ge 2 ] || usage "--fps needs a value"; fps=$2; shift ;;
	--format=*) format=${1#*=} ;;
	--format) [ $# -ge 2 ] || usage "--format needs a value"; format=$2; shift ;;
	*) usage "unknown option: $1" ;;
	esac
	shift
done
[ -z "$fps" ] || [[ $fps =~ ^(30|60)$ ]] || usage "--fps must be 30 or 60"
[ -z "$format" ] || [[ $format =~ ^(mp4|webm)$ ]] || usage "--format must be mp4 or webm"
mkdir -p "$RUN_DIR"

case $cmd in
status)
	if read_state && alive "${st[pid]}" "${st[comm]}"; then cat "$STATE"; exit 0; fi
	exit 1
	;;
stop)
	if read_state && alive "${st[pid]}" "${st[comm]}"; then stop_recording; else rm -f "$STATE"; fi
	exit 0
	;;
region | window | output) ;;
*) usage ;;
esac

# toggle: a running recording is stopped by any start key; a stale state file is dropped
if read_state; then
	if alive "${st[pid]}" "${st[comm]}"; then stop_recording; exit 0; fi
	rm -f "$STATE"
fi

# options not given: the menu's saved choices, then the built-in defaults
read_prefs
fps=${fps:-60} format=${format:-mp4} audio=${audio:-0}

# one selection at a time: a second press while slurp is up does nothing (Escape cancels slurp)
exec 9>"$LOCK"
flock -n 9 || exit 0

need "$RECORDER" wf-recorder
need hyprctl hyprland
need jq jq

geom="" output=""
case $cmd in
region)
	if [ -n "${REC_GEOM:-}" ]; then geom=$REC_GEOM; else
		need slurp slurp
		geom=$(slurp -d) || exit 0
	fi
	;;
window)
	if [ -n "${REC_GEOM:-}" ]; then geom=$REC_GEOM; else
		need slurp slurp
		# boxes of the windows on every monitor's visible workspace (+ pinned ones; grouped windows share
		# one box); slurp -r = click one of them
		geom=$(hyprctl clients -j | jq -r --argjson ws "$(hyprctl monitors -j | jq '[.[] | .activeWorkspace.id, .specialWorkspace.id] | map(select(. != 0))')" \
			'.[] | select(.mapped and (.hidden | not) and (.pinned or (.workspace.id as $w | $ws | index($w))))
			 | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' | awk '!seen[$0]++' | slurp -r) || exit 0
	fi
	;;
output)
	output=${REC_OUTPUT:-$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name' | head -n1)}
	[ -n "$output" ] || { notify critical "Can't record" "No focused monitor found"; exit 1; }
	;;
esac
if [ -n "$geom" ]; then
	geom=$(geom_even "$geom") || exit 0        # a click without a drag gives a tiny box: nothing to record
fi

mkdir -p "$OUT_DIR"
file=$OUT_DIR/rec-$(date +%Y-%m-%d_%H-%M-%S).$format

# pick the encoder: GPU of the recorded monitor unless forced / too small / not capable
want=${SCREENREC_ENCODER:-auto}
case $want in auto | cpu | vaapi | nvenc) ;; *) echo "SCREENREC_ENCODER=$want unknown, using auto" >&2; want=auto ;; esac
dev=${SCREENREC_DEVICE:-}
if [ "$want" != cpu ] && [ -z "$dev" ]; then
	mon=$output
	[ -n "$mon" ] || mon=$(monitor_at "$geom")
	[ -n "$mon" ] || mon=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name' | head -n1)
	dev=$(render_node_for "$mon") || dev=$(ls /dev/dri/renderD* 2>/dev/null | head -n1)
fi
gcodec=$(codec_of vaapi)        # what the GPU would encode: h264 (mp4) or av1 (webm)
enc=cpu
if [ "$want" != cpu ] && [ -n "$dev" ]; then
	if [ "$want" = auto ]; then
		gpu=vaapi
		[ "$(node_driver "$dev")" = nvidia ] && gpu=nvenc
		probe "$gpu" "$gcodec" "$dev" && enc=$gpu
	else
		enc=$want
	fi
fi
if [ "$enc" != cpu ] && [ -n "$geom" ]; then
	wh=${geom##* }; w=${wh%x*}; h=${wh#*x}
	if [ "$gcodec" = av1 ]; then ((w >= AV1_MIN_W && h >= AV1_MIN_H)) || enc=cpu
	else ((w >= GPU_MIN && h >= GPU_MIN)) || enc=cpu; fi
fi
# av1_vaapi (Mesa/VCN) pads the coded frame width up to a multiple of 8 and only sets the AV1 render size
# to the real width; decoders (dav1d, browsers, mpv) show the padding as a green stripe on the right. So
# give the GPU AV1 encoder a width that is a multiple of 8 (height is coded as is).
if [ "$enc" = vaapi ] && [ "$gcodec" = av1 ]; then
	if [ -z "$geom" ]; then        # whole monitor: only needs a geometry if its width is not aligned
		mg=$(hyprctl monitors -j | jq -r --arg o "$output" '.[] | select(.name == $o)
			| (if .transform % 2 == 1 then [.height, .width] else [.width, .height] end) as $s
			| "\(.x),\(.y) \($s[0] / .scale | floor)x\($s[1] / .scale | floor)"' | head -n1)
		wh=${mg##* }; w=${wh%x*}
		[[ $w =~ ^[0-9]+$ ]] && ((w % 8)) && geom=$(geom_even "$mg") && output=""
	fi
	if [ -n "$geom" ]; then
		wh=${geom##* }; w=${wh%x*}
		geom="${geom%% *} $((w / 8 * 8))x${wh#*x}"
	fi
fi

mapfile -t codec < <(enc_args "$enc" "$dev")
args=(-y -f "$file" -r "$fps")
if [ -n "$geom" ]; then args+=(-g "$geom"); else args+=(-o "$output"); fi
if [ "$audio" = 1 ]; then
	sink=$(pactl get-default-sink 2>/dev/null)
	if [ -n "$sink" ]; then
		args+=(--audio="$sink.monitor")
		if [ "$format" = webm ]; then args+=(-C libopus); else args+=(-C aac); fi
	else
		audio=0
		notify normal "Recording without audio" "No default audio output found"
	fi
fi

# the recorder must not inherit the lock fd (9) or the lock would be held for the whole recording
fallback=""
if ! start_recorder "${args[@]}" "${codec[@]}" && [ "$enc" != cpu ]; then
	wait "$pid"
	cp -f "$LOG" "$RUN_DIR/last-gpu.log"
	fallback="$enc $(codec_of "$enc") on ${dev:-?} failed: $(grep -v '^region capture' "$LOG" | tail -n 1)"
	rm -f "$file"
	enc=cpu
	mapfile -t codec < <(enc_args cpu)
	start_recorder "${args[@]}" "${codec[@]}"
fi
comm=$(cat "/proc/$pid/comm" 2>/dev/null)
if [ -z "$comm" ] || ! running "$pid"; then
	wait "$pid"
	rm -f "$file"
	notify critical "Recording failed" "$(tail -n 3 "$LOG")"
	exit 1
fi
started=$(date +%s)
printf 'pid=%s\ncomm=%s\nwrapper=%s\nstarted=%s\nfile=%s\nmode=%s\naudio=%s\nenc=%s\ncodec=%s\nfps=%s\nformat=%s\n' \
	"$pid" "$comm" "$$" "$started" "$file" "$cmd" "$audio" "$enc" "$(codec_of "$enc")" "$fps" "$format" \
	>"$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"
exec 9>&-

wait "$pid"
rc=$?
# only remove the state file if it is still ours (a new recording may have started meanwhile)
read_state && [ "${st[pid]}" = "$pid" ] && rm -f "$STATE"

# told only now so the notification isn't in the video
[ -n "$fallback" ] && notify normal "Recorded with the CPU encoder" "GPU encoding unavailable: $fallback"
if [ -s "$file" ]; then
	saved_notice "$file" "$started"
else
	rm -f "$file"
	notify critical "Recording failed (exit $rc)" "$(tail -n 3 "$LOG")"
fi
