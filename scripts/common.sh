# Shared setup for usage-runway scripts: paths, settings and portable helpers.
# Sourced, not executed. Works with bash 3.2+ on Linux and macOS.

export LC_ALL=C   # dot as decimal separator in printf/awk, English day names

UR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UR_HOME="${USAGE_RUNWAY_HOME:-$HOME/.claude/usage-runway}"
UR_STATE="$UR_HOME/state"
UR_SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

. "$UR_ROOT/config.default"
[ -f "$UR_HOME/config" ] && . "$UR_HOME/config"
# PREFIX was renamed to SYM_PREFIX in 0.1.2; keep reading configs that set it.
[ -z "$SYM_PREFIX" ] && [ -n "${PREFIX:-}" ] && SYM_PREFIX=$PREFIX

# color_valid <value>: empty, a 256-color index 0-255, R;G;B with each 0-255,
# #rrggbb or rrggbb, or dim (the terminal's faint text style).
color_valid() {
  local c
  [ -z "$1" ] && return 0
  [ "$1" = dim ] && return 0
  [[ $1 =~ ^#?[0-9a-fA-F]{6}$ ]] && return 0
  [[ $1 =~ ^[0-9]{1,3}(\;[0-9]{1,3}\;[0-9]{1,3})?$ ]] || return 1
  for c in ${1//;/ }; do (( 10#$c <= 255 )) || return 1; done
}

# color_code <value> <38|48>: the foreground (38) or background (48) escape
# for a valid non-empty color value ("dim" is the faint style either way). Indexes 0-15 use the basic ANSI codes
# (e.g. 1 is \e[31m), so they follow the terminal's own palette.
color_code() {
  local v=$1 n
  [ "$v" = dim ] && { printf '\e[2m'; return; }
  [ ${#v} = 6 ] && v="#$v"
  [[ $v == \#* ]] && v="$((16#${v:1:2}));$((16#${v:3:2}));$((16#${v:5:2}))"
  case $v in *\;*) printf '\e[%s;2;%sm' "$2" "$v"; return ;; esac
  n=$((10#$v))
  if (( n < 8 )); then printf '\e[%sm' "$(( $2 - 8 + n ))"
  elif (( n < 16 )); then printf '\e[%sm' "$(( $2 + 52 + n - 8 ))"
  else printf '\e[%s;5;%sm' "$2" "$n"; fi
}

# color_hex <value>: a valid color as it is saved in the config: #rrggbb
# (lower case) for an index 16-255, R;G;B or hex. Indexes 0-15 (the terminal's
# own palette, no fixed hex), dim and empty stay as they are.
color_hex() {
  local v=$1 n r g b l
  l=(0 95 135 175 215 255)
  [ ${#v} = 6 ] && v="#$v"
  case $v in
    \#*) printf '%s\n' "$v" | tr 'A-F' 'a-f' ;;
    *\;*) IFS=';' read -r r g b <<<"$v"; printf '#%02x%02x%02x\n' "$((10#$r))" "$((10#$g))" "$((10#$b))" ;;
    ''|dim) printf '%s\n' "$v" ;;
    *) n=$((10#$v))
       if (( n < 16 )); then echo "$n"
       elif (( n < 232 )); then n=$((n - 16)); printf '#%02x%02x%02x\n' "${l[n/36]}" "${l[n/6%6]}" "${l[n%6]}"
       else n=$((8 + 10 * (n - 232))); printf '#%02x%02x%02x\n' "$n" "$n" "$n"; fi ;;
  esac
}

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
