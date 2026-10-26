#!/usr/bin/env bash
# code-open tests: run `bash tests/code-open.test.sh` from launcher/bin. Title matching, plus the decisions and the zellij / terminal
# calls against stubs on PATH (fake zellij, terminal, hyprctl, pgrep, notify-send in a temp dir): no real session is touched.
cd "$(dirname "$0")/.." || exit 1
BIN=$PWD
fail=0
t() { ./code-open --match "$2" "$3"; r=$?; if [ "$r" = "$1" ]; then :; else echo "FAIL want=$1 got=$r session=$2 title=$3"; fail=1; fi; }
t 0 code "code | user@host:~/proj"
t 0 code "code"
t 1 code "codex | user@host:~"
t 1 code "my-code | user@host:~"
t 1 code "Visual Studio Code"
t 1 code "code review - Brave"
t 1 code "user@host:~/code/proj"
t 1 code "gracious-goose | user@host:~/code"
t 0 gracious-goose "gracious-goose | user@host:~/code"

# ---- stubs ----------------------------------------------------------------------------------------------------------
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/proj/sub"; echo x > "$T/proj/notes.md"
# zellij: list-sessions prints $T/sessions; new-tab saves its argv (NUL-separated)
cat > "$T/bin/zellij" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *" list-sessions "*) cat "$T/sessions" ;;
  *" new-tab "*) printf '%s\0' "$@" > "$T/newtab"; echo "new-tab" >> "$T/calls" ;;
esac
EOF
cat > "$T/bin/term" <<'EOF'
#!/usr/bin/env bash
echo "term $*" >> "$T/calls"
EOF
printf '#!/bin/sh\necho "[]"\n' > "$T/bin/hyprctl"
printf '#!/bin/sh\nexit 1\n' > "$T/bin/pgrep"
printf '#!/bin/sh\necho "notify $*" >> "$T/calls"\n' > "$T/bin/notify-send"
chmod +x "$T/bin/"*
export T PATH="$T/bin:$PATH" CODE_TERM=term QS_CODE_SESSION=testsess

# run code-open on $2 with the session state $1 (missing | running | exited); output and calls into $out / $calls
run() {
  rm -f "$T/calls" "$T/newtab"
  case $1 in missing) : > "$T/sessions" ;; running) echo "testsess [Created 1m ago]" > "$T/sessions" ;;
    exited) echo "testsess [Created 1m ago] (EXITED - attach to resurrect)" > "$T/sessions" ;; esac
  out=$(DRY=$DRY ./code-open "$2" 2>&1); code=$?
  calls=$(cat "$T/calls" 2>/dev/null)
}
want() { [[ $2 == $3 ]] || { echo "FAIL $1: got [$2] want [$3]"; fail=1; }; }
P=$T/proj F=$T/proj/notes.md

DRY=1
run missing "$P";  want "dry missing dir"  "$out" "create testsess in $P"
run missing "$F";  want "dry missing file" "$out" "create testsess in $P, then tab $P edit $F"
run exited "$P/";  want "dry exited dir"   "$out" "resurrect testsess, then tab $P"
run running "$F";  want "dry running file" "$(head -1 <<<"$out")" "tab $P edit $F"
run running "$T/nope"; want "not found" "$code:$calls" "1:notify -a Launcher Projects Not found: nope"
DRY=

# running session, folder with a trailing slash: a plain tab named after the folder, then (no window shows it) a terminal attaches
run running "$P/sub/"
mapfile -d '' -t a < "$T/newtab"
want "folder tab argv" "${a[*]}" "--session testsess action new-tab --cwd=$P/sub --name=sub"
want "folder attach" "$(tail -1 <<<"$calls")" "term -e zellij attach testsess"

# running session, file: tab in its folder named after the file, running the editor script on it
run running "$F"
mapfile -d '' -t a < "$T/newtab"
want "file tab argv" "${a[*]:0:9}" "--session testsess action new-tab --cwd=$P --name=notes.md --close-on-exit -- sh"
want "file tab script arg" "${a[*]: -2}" "sh $F"
script=${a[10]}
want "editor: VISUAL first" "$(VISUAL="printf V:%s" EDITOR="printf E:%s" SHELL=true sh -c "$script" sh "$F")" "V:$F"
want "editor: then EDITOR"  "$(env -u VISUAL EDITOR="printf E:%s" SHELL=true sh -c "$script" sh "$F")" "E:$F"
want "editor: none found"   "$(env -u VISUAL -u EDITOR PATH="$T/bin" SHELL=/bin/true /bin/sh -c "$script" sh "$F")" "No editor found*"

# a name starting with "-" (relative path): absolute cwd / name as --opt=value, so zellij and the editor never read them as options
mkdir -p "$T/proj/-d"; echo x > "$T/proj/-f.md"
run running "$T/proj/-d"; want "dash dir tab" "$(tr '\0' ' ' < "$T/newtab")" "--session testsess action new-tab --cwd=$P/-d --name=-d "
rm -f "$T/calls" "$T/newtab"; echo "testsess [Created 1m ago]" > "$T/sessions"
( cd "$P" && "$BIN/code-open" -f.md >/dev/null 2>&1 )
mapfile -d '' -t a < "$T/newtab"
want "dash file: absolute" "${a[*]: -2}" "sh $P/-f.md"
want "dash file: name" "${a[5]}" "--name=-f.md"

# missing session, file: a terminal in the folder creates the session, the editor tab follows once it runs
rm -f "$T/calls" "$T/newtab"; : > "$T/sessions"
( sleep 0.5; echo "testsess [Created 0s ago]" > "$T/sessions" ) &
out=$(./code-open "$F" 2>&1); code=$?; wait
want "missing file: terminal" "$(head -1 "$T/calls")" "term --working-directory=$P -e zellij attach --create testsess"
want "missing file: then tab" "$code:$(tail -1 "$T/calls")" "0:new-tab"

[ $fail = 0 ] && echo "ok"; exit $fail
