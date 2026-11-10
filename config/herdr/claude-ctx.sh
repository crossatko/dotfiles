#!/bin/bash
# Claude Code statusLine command: publish the context-window usage to the herdr sidebar row of this pane
# as the $ctx token. Prints nothing, so the status line stays empty.
# In the desktop app (HC_TERMINAL_ID) it also sets the terminal label ctx=NN for the agent card.
# Silent no-op outside herdr; herdr is called in the background and only when the value changed.
[ -n "${HERDR_PANE_ID:-}${HC_TERMINAL_ID:-}" ] || { cat >/dev/null; exit 0; }
# "<percent> <tokens>": tokens in the context now (input + cache), else derived from the percent and window size.
IFS='|' read -r pct tok < <(jq -r '.context_window as $c | ($c.current_usage // {}) as $u
  | (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0)) as $sum
  | "\($c.used_percentage // "")|\(if $sum > 0 then $sum elif ($c.used_percentage and $c.context_window_size) then ($c.used_percentage * $c.context_window_size / 100 | floor) else "" end)"' 2>/dev/null) || exit 0
[ -n "$pct" ] || exit 0
num=$(printf '%.0f' "$pct")
val="✻ $num%"

state=${XDG_RUNTIME_DIR:-/tmp}/herdr-claude-ctx
mkdir -p "$state" 2>/dev/null
# Skip when unchanged and refreshed within the last 5 minutes.
fresh() { [ "$(cat "$1" 2>/dev/null)" = "$2" ] && [ -n "$(find "$1" -mmin -5 2>/dev/null)" ]; }

if [ -n "${HERDR_PANE_ID:-}" ]; then
  f=$state/${HERDR_PANE_ID//[^A-Za-z0-9_.-]/_}
  if ! fresh "$f" "$val"; then
    printf '%s' "$val" >"$f"
    herd=${HERDR_BIN_PATH:-herdr}
    "$herd" pane report-metadata "$HERDR_PANE_ID" --source claude-ctx --token "ctx=$val" >/dev/null 2>&1 &
  fi
fi

if [ -n "${HC_TERMINAL_ID:-}" ]; then
  f=$state/hc-${HC_TERMINAL_ID//[^A-Za-z0-9_.-]/_}
  # ctxtok (tokens, rounded to 1k so the label changes less often) lets the card measure against a fixed budget.
  labels=("ctx=$num")
  # No token count: an empty value removes an old ctxtok, so the card falls back to the percent.
  if [[ "$tok" =~ ^[0-9]+$ ]]; then labels+=("ctxtok=$(( (tok + 500) / 1000 * 1000 ))"); else labels+=("ctxtok="); fi
  if ! fresh "$f" "${labels[*]}"; then
    printf '%s' "${labels[*]}" >"$f"
    # A failed label drops the cache so the next update retries.
    { "${HC_BIN:-$HOME/.local/bin/hc}" label "$HC_TERMINAL_ID" "${labels[@]}" || rm -f "$f"; } >/dev/null 2>&1 &
  fi
fi
exit 0
