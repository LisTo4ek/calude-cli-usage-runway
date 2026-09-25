#!/usr/bin/env bash
# usage-runway tests: feed simulated statusLine / hook JSON to the scripts in an
# isolated home directory and check the output. Run: bash tests/run.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SL="$ROOT/scripts/statusline.sh" HOOK="$ROOT/scripts/hook.sh" SETUP="$ROOT/scripts/setup.sh"
pass=0 fail=0

fresh() {  # new isolated environment
  T=$(mktemp -d)
  export USAGE_RUNWAY_HOME="$T/ur" CLAUDE_CONFIG_DIR="$T/claude"
  mkdir -p "$USAGE_RUNWAY_HOME/state" "$CLAUDE_CONFIG_DIR"
  printf 'NOTIFY=off\nBELL=off\n' > "$USAGE_RUNWAY_HOME/config"
  NOW=$(date +%s)
}
conf() { echo "$1" >> "$USAGE_RUNWAY_HOME/config"; }

# input <sid> <cost> <5h used|-> <5h resets in s> [7d used] [7d resets in s]
input() {
  jq -n --arg s "$1" --argjson c "$2" --arg u5 "$3" --argjson r5 "$((NOW + $4))" \
        --arg u7 "${5:--}" --argjson r7 "$((NOW + ${6:-0}))" '
    {session_id: $s, cost: {total_cost_usd: $c}, context_window: {used_percentage: 12.34}}
    + (if $u5 == "-" and $u7 == "-" then {} else {rate_limits: (
        (if $u5 == "-" then {} else {five_hour: {used_percentage: ($u5|tonumber), resets_at: $r5}} end)
        + (if $u7 == "-" then {} else {seven_day: {used_percentage: ($u7|tonumber), resets_at: $r7}} end))} end)'
}
line() { bash "$SL" | sed 's/\x1b\[[0-9;]*m//g'; }
hook() { jq -n --arg s "$1" --arg e "$2" '{session_id: $s, hook_event_name: $e}' | bash "$HOOK"; }
sample() { echo "$((NOW + $2)) $((NOW - $3)) $4" >> "$USAGE_RUNWAY_HOME/state/samples-$1"; }

check() {  # check <name> <actual> <expected substring>
  if [[ "$2" == *"$3"* ]]; then pass=$((pass + 1)); echo "ok   $1"
  else fail=$((fail + 1)); echo "FAIL $1"; echo "     expected: $3"; echo "     actual:   $2"; fi
}
check_not() {
  if [[ "$2" != *"$3"* ]]; then pass=$((pass + 1)); echo "ok   $1"
  else fail=$((fail + 1)); echo "FAIL $1"; echo "     unexpected: $3"; echo "     actual:     $2"; fi
}

fresh
out=$(input A 1.5 - 0 | line)
check "no limit data: cost shown" "$out" 'Ctx 12.3% · $1.50'
check_not "no limit data: no 5h" "$out" '5h'

fresh
out=$(input A 1 20 7200 | line)
check "5h: used, projection, reset" "$out" '5h 20.0% → 33.3% ↻ 02:00'
check "Ses starts at zero" "$out" 'Ses 0.0%'
check_not "cost hidden with limit data" "$out" '$'

fresh
sample five_hour 7200 600 20
out=$(input A 1 45 7200 | line)
check "burst: red with projection and time to 100%" "$out" '5h 45.0% → '
check "burst: warning marker" "$out" '⚠ 00:'
alerts=$(cat "$USAGE_RUNWAY_HOME/state/alerts")
check "burst: alert recorded" "$alerts" 'runs out in'
msg=$(hook A UserPromptSubmit)
check "hook shows alert" "$msg" '"systemMessage": "⚠ 5h limit: 45.0% used'
msg=$(hook A UserPromptSubmit)
check "hook shows alert only once per session" "[$msg]" '[]'
msg=$(hook B PreToolUse)
check "hook shows alert in another session" "$msg" 'systemMessage'

fresh
out=$(input A 1 100 3600 | line)
check "limit reached" "$out" '5h 100% ⛔'

fresh
input A 1 14 3000 | line >/dev/null
input B 1 20 3000 | line >/dev/null
sleep 1
input B 2 25 3000 | line >/dev/null
out=$(input A 1 14 3000 | line)
check "idle session shows the freshest shared value" "$out" '5h 25.0%'

fresh
input A 1 20 3000 | line >/dev/null
hook A UserPromptSubmit >/dev/null
out=$(input A 2 24 3000 | line)
check "Ses counts own usage" "$out" 'Ses 4.0%'
check "Cmd counts current message" "$out" 'Cmd 4.0%'
out=$(input A 2 30 3000 | line)
check "Ses ignores other sessions' usage" "$out" 'Ses 4.0%'
hook A UserPromptSubmit >/dev/null
out=$(input A 3 33 3000 | line)
check "Cmd restarts per message" "$out" 'Cmd 3.0%'
out=$(input A 4 2 21000 | line)
check "Ses continues across a 5h reset" "$out" 'Ses 9.0%'

fresh
out=$(input A 1 - 0 1 $((604800 - 2800)) | line)
check "7d: no forecast until enough data" "$out" '7d 1.0% → … ↻ 6d23h'

fresh
conf 'WORK_DAYS="1 2 3 4 5"'; conf 'DAY_START=8'; conf 'NIGHT_WEIGHT=1'; conf 'OFF_DAY_WEIGHT=1'
out=$(input A 1 - 0 30 $((4 * 86400)) | line)
check "7d unweighted: wall-clock projection" "$out" '7d 30.0% → 70.0%'

fresh
out=$(input A 1 - 0 30 $((4 * 86400)) | line)
check "7d default schedule (every day, all day): wall clock" "$out" '7d 30.0% → 70.0%'

fresh
conf "WORK_DAYS=\"$(date +%u)\""   # only today is a working day
out=$(input A 1 - 0 30 $((4 * 86400)) | line)
check "7d work days: forecast shown" "$out" '7d 30.0% → '
check_not "7d work days: off days weighted" "$out" '→ 70.0%'

fresh
: > "$USAGE_RUNWAY_HOME/state/time-awk"   # simulate an awk without strftime/mktime
out=$(input A 1 - 0 30 $((4 * 86400)) | line)
check "7d without time awk: falls back to wall clock" "$out" '7d 30.0% → 70.0%'

fresh
out=$(input A 1 20 7200 | LANG=ru_RU.UTF-8 LC_ALL=ru_RU.UTF-8 line)
check "decimal point under a comma locale" "$out" '5h 20.0%'

fresh
conf 'GUARD=on'
input A 1 96 3600 | line >/dev/null
msg=$(hook A PreToolUse)
check "guard denies tool calls at threshold" "$msg" '"permissionDecision": "deny"'
touch "$USAGE_RUNWAY_HOME/state/bypass-A"
msg=$(hook A PreToolUse)
check_not "guard bypass per session" "$msg" 'deny'

fresh
conf 'GUARD=off'
input A 1 96 3600 | line >/dev/null
msg=$(hook A PreToolUse)
check_not "guard off by default" "$msg" 'deny'

fresh
msg=$(hook A SessionStart)
check "session start suggests setup" "$msg" '/usage-runway:setup'
check "session start records plugin path" "$(cat "$USAGE_RUNWAY_HOME/plugin-root")" "$ROOT"
msg=$(hook B SessionStart)
check_not "setup hint only once" "$msg" 'setup'

fresh
echo '{"statusLine": {"type": "command", "command": "my-line.sh"}, "model": "opus"}' > "$CLAUDE_CONFIG_DIR/settings.json"
bash "$SETUP" >/dev/null; rc=$?
check "setup refuses to replace another status line" "$rc" '3'
bash "$SETUP" --force >/dev/null
cfg=$(cat "$CLAUDE_CONFIG_DIR/settings.json")
check "setup --force installs launcher" "$cfg" "$USAGE_RUNWAY_HOME/statusline.sh"
check "setup keeps other settings" "$cfg" '"model": "opus"'
check "setup writes a backup" "$(cat "$CLAUDE_CONFIG_DIR/settings.json.bak-usage-runway")" 'my-line.sh'
out=$(input A 1 20 7200 | bash "$USAGE_RUNWAY_HOME/statusline.sh" | sed 's/\x1b\[[0-9;]*m//g')
check "launcher runs the plugin status line" "$out" '5h 20.0%'
bash "$SETUP" >/dev/null; rc=$?
check "setup is idempotent" "$rc" '0'
bash "$SETUP" --uninstall >/dev/null
check_not "uninstall removes the status line" "$(cat "$CLAUDE_CONFIG_DIR/settings.json")" 'statusLine'

fresh
rm "$USAGE_RUNWAY_HOME/config"   # --set creates it from the defaults
bash "$SETUP" --set "WORK_DAYS=1 2 3 4 5" DAY_START=09 DAY_END=18 >/dev/null; rc=$?
check "setup --set saves the schedule" "$rc" '0'
cfg=$(cat "$USAGE_RUNWAY_HOME/config")
check "setup --set writes work days" "$cfg" 'WORK_DAYS="1 2 3 4 5"'
check "setup --set normalises hours" "$cfg" 'DAY_START="9"'
check "setup --set keeps other defaults commented" "$cfg" '# WARN_PCT=80'
check "setup --status shows the schedule" "$(bash "$SETUP" --status)" 'days 1 2 3 4 5, hours 9-18'
bash "$SETUP" --set DAY_START=18 DAY_END=9 >/dev/null 2>&1; rc=$?
check "setup --set rejects start after end" "$rc" '1'
bash "$SETUP" --set 'WORK_DAYS=1 8' >/dev/null 2>&1; rc=$?
check "setup --set rejects bad days" "$rc" '1'
bash "$SETUP" --set 'DAY_START=$(touch x)' >/dev/null 2>&1; rc=$?
check "setup --set rejects shell code" "$rc" '1'
bash "$SETUP" --set GUARD=on >/dev/null 2>&1; rc=$?
check "setup --set rejects unsupported keys" "$rc" '1'
check "setup --set leaves config unchanged on error" "$(cat "$USAGE_RUNWAY_HOME/config")" "$cfg"

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
