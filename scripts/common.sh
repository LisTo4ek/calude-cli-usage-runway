# Shared setup for usage-runway scripts: paths, settings and portable helpers.
# Sourced, not executed. Works with bash 3.2+ on Linux and macOS.

export LC_ALL=C   # dot as decimal separator in printf/awk, English day names

UR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UR_HOME="${USAGE_RUNWAY_HOME:-$HOME/.claude/usage-runway}"
UR_STATE="$UR_HOME/state"
UR_SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

. "$UR_ROOT/config.default"
[ -f "$UR_HOME/config" ] && . "$UR_HOME/config"

# fmt_date <epoch> <+format>: GNU date, falling back to BSD date.
fmt_date() {
  date -d "@$1" "$2" 2>/dev/null || date -r "$1" "$2"
}

# An awk with strftime/mktime (gawk, mawk 1.3.4+), cached; empty when none.
# Without one the weekly forecast falls back to plain wall-clock time.
time_awk() {
  local cache="$UR_STATE/time-awk" c
  if [ -f "$cache" ]; then cat "$cache"; return; fi
  for c in gawk mawk awk; do
    command -v "$c" >/dev/null 2>&1 || continue
    if "$c" 'BEGIN { t = mktime("2024 01 01 12 00 00"); exit !(t > 0 && strftime("%u", t) == 1) }' 2>/dev/null; then
      echo "$c" > "$cache"; echo "$c"; return
    fi
  done
  : > "$cache"
}

notify() {
  local text=$1
  if [ "$NOTIFY" = on ]; then
    if command -v notify-send >/dev/null 2>&1; then
      notify-send -u critical "usage-runway" "$text" 2>/dev/null
    elif command -v osascript >/dev/null 2>&1; then
      osascript -e "display notification \"${text//\"/\\\"}\" with title \"usage-runway\"" 2>/dev/null
    fi
  fi
  if [ "$BELL" = on ]; then
    { printf '\a' > /dev/tty; } 2>/dev/null || true
  fi
}
