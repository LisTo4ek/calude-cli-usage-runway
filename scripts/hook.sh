#!/usr/bin/env bash
# usage-runway hook for SessionStart, UserPromptSubmit and PreToolUse.
# - SessionStart: records the installed plugin path for the status line launcher
#   and suggests /usage-runway:setup once if the status line is not configured.
# - UserPromptSubmit: records this session's usage total at message start (Cmd).
# - All events: shows each alert raised by the status line once per session.
# - PreToolUse with GUARD=on: denies tool calls once a limit reaches GUARD_PCT.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

command -v jq >/dev/null 2>&1 || exit 0
mkdir -p "$UR_STATE"

in=$(cat)
now=$(date +%s)
sid=$(jq -r '.session_id // "unknown"' <<<"$in")
event=$(jq -r '.hook_event_name // ""' <<<"$in")
seen="$UR_STATE/seen-$sid"
msgs=""

if [ "$event" = SessionStart ]; then
  echo "$UR_ROOT" > "$UR_HOME/plugin-root"
  if ! jq -e --arg l "$UR_HOME/statusline.sh" \
       '.statusLine.command // "" | (. == $l or test("usage-runway"))' "$UR_SETTINGS" >/dev/null 2>&1 \
     && [ ! -f "$UR_HOME/setup-hint-shown" ]; then
    touch "$UR_HOME/setup-hint-shown"
    msgs="usage-runway is installed. Run /usage-runway:setup to enable its status line."
  fi
fi

if [ "$event" = UserPromptSubmit ]; then
  total=0
  [ -f "$UR_STATE/acc-$sid" ] && read -r _ _ _ total < "$UR_STATE/acc-$sid"
  echo "${total:-0}" > "$UR_STATE/turn-$sid"
fi

if [ -f "$UR_STATE/alerts" ]; then
  while IFS=$'\t' read -r id reset text; do
    (( reset < now )) && continue
    grep -qxF "$id" "$seen" 2>/dev/null && continue
    echo "$id" >> "$seen"
    msgs+="${msgs:+ }${SYM_WARN} $text"
  done < "$UR_STATE/alerts"
fi

deny=""
if [ "$GUARD" = on ] && [ "$event" = PreToolUse ] && [ ! -f "$UR_STATE/bypass-$sid" ]; then
  for f in "$UR_STATE"/current-*; do
    [ -f "$f" ] || continue
    read -r name upct _ _ reset _ ts _ < "$f"
    (( reset < now || now - ts > 900 )) && continue
    if (( upct >= GUARD_PCT )); then
      label=5h; [ "$name" = seven_day ] && label=7d
      deny="usage-runway guard: the ${label} limit is at ${upct}% (threshold ${GUARD_PCT}%). Stop working, summarise progress and ask the user whether to continue. To continue in this session the user can run: ! touch \"$UR_STATE/bypass-$sid\""
      break
    fi
  done
fi

if [ -n "$deny" ]; then
  jq -n --arg r "$deny" --arg m "${msgs:-$deny}" '{
    systemMessage: $m,
    hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}
  }'
elif [ -n "$msgs" ]; then
  jq -n --arg m "$msgs" '{systemMessage: $m}'
fi
exit 0
