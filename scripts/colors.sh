#!/usr/bin/env bash
# usage-runway color picker: choose the background and every color of the
# status line with the arrow keys, on a live preview rendered by statusline.sh.
# Needs a terminal; run it directly, not through Claude:
#
#   bash "$(cat ~/.claude/usage-runway/plugin-root)/scripts/colors.sh"
#
# Saves through setup.sh --set on Enter; q quits without saving.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if [ ! -t 0 ] || [ ! -t 1 ]; then
  echo "The color picker needs a terminal. Run it in a terminal window:" >&2
  echo "  bash \"$UR_ROOT/scripts/colors.sh\"" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "usage-runway needs jq" >&2; exit 1; }

KEYS=(BG COLOR_TEXT COLOR_LABEL COLOR_MUTED COLOR_SEP COLOR_FAINT COLOR_GREEN COLOR_YELLOW COLOR_RED COLOR_PREFIX)
DESC=("segment background" "main color of every panel" "segment names: 5h, 7d, Ctx" "arrow and reset sign"
      "separator" "time until reset" "on track" "warning, Cmd at CMD_WARN" "runs out, Cmd at CMD_CRIT"
      "prefix text")
VALS=() ORIG=()
for k in "${KEYS[@]}"; do VALS+=("${!k}"); ORIG+=("${!k}"); done
sel=0 msg="" PREVIEW="" PREVIEW_KEY=""

tmp=$(mktemp -d) || exit 1
cleanup() { printf '\e[0m\e[?25h\e[?1049l'; stty "$stty_saved" 2>/dev/null; rm -rf "$tmp"; }
stty_saved=$(stty -g)
trap cleanup EXIT
trap 'exit 130' INT TERM
printf '\e[?1049h\e[?25l'

# Three sample lines (on track, warning, runs out) with a Cmd value in each
# color. Each line renders in its own throwaway home.
now=$(date +%s) r5=$(( $(date +%s) + 7200 ))
SAMPLE_U=(20 55 70) SAMPLE_ACC=("18 0.5 4.0 4.0 -" "54 0.5 2.0 2.0 -" "64 0.5 10.0 10.0 -") SAMPLE_TURN=(3.0 2.0 6.0)
for i in 0 1 2; do mkdir -p "$tmp/h$i/state"; done

render() {  # render: set PREVIEW to the three preview lines, re-rendering
  # only when a value changed (moving between settings costs nothing)
  local i j key IFS=$'\x1f'
  key="${VALS[*]}"
  [ "$key" = "$PREVIEW_KEY" ] && return
  IFS=$' \t\n'
  for i in 0 1 2; do
    (
      rm -f "$tmp/h$i/state/"*
      { [ -f "$UR_HOME/config" ] && cat "$UR_HOME/config"
        echo 'NOTIFY=off BELL=off'
        for j in "${!KEYS[@]}"; do echo "${KEYS[$j]}=\"${VALS[$j]}\""; done
      } > "$tmp/h$i/config"
      echo "$r5 ${SAMPLE_ACC[$i]}" > "$tmp/h$i/state/acc-preview"
      echo "${SAMPLE_TURN[$i]}" > "$tmp/h$i/state/turn-preview"
      jq -n --argjson u "${SAMPLE_U[$i]}" --argjson r "$r5" --argjson t "$now" \
        '{session_id: "preview", cost: {total_cost_usd: 1}, context_window: {used_percentage: 12.3},
          rate_limits: {five_hour: {used_percentage: $u, resets_at: $r},
                        seven_day: {used_percentage: 30, resets_at: ($t + 345600)}}}' \
        | USAGE_RUNWAY_HOME="$tmp/h$i" CLAUDE_CONFIG_DIR="$tmp/h$i" bash "$UR_ROOT/scripts/statusline.sh" \
        > "$tmp/out$i"
    ) &
  done
  wait
  PREVIEW=$(cat "$tmp/out0" "$tmp/out1" "$tmp/out2")
  PREVIEW_KEY=$key
}

hex_of() {  # hex_of <value>: the hex code shown next to a value
  case $1 in
    ''|dim) echo "" ;;
    [0-9]|1[0-5]) echo "terminal palette" ;;
    *) color_hex "$1" ;;
  esac
}

index_of() {  # index_of <value>: the 256-color index nearest to a value
  local v=$1 r g b
  [ ${#v} = 6 ] && v="#$v"
  case $v in
    ''|dim) echo -1; return ;;
    \#*) r=$((16#${v:1:2})) g=$((16#${v:3:2})) b=$((16#${v:5:2})) ;;
    *\;*) IFS=';' read -r r g b <<<"$v" ;;
    *) echo $((10#$v)); return ;;
  esac
  awk -v r="$r" -v g="$g" -v b="$b" 'BEGIN {
    split("0 95 135 175 215 255", l, " "); best = 1e9
    for (n = 16; n < 256; n++) {
      if (n < 232) { m = n - 16; R = l[int(m/36)+1]; G = l[int(m/6)%6+1]; B = l[m%6+1] }
      else R = G = B = 8 + 10 * (n - 232)
      d = (R-r)^2 + (G-g)^2 + (B-b)^2; if (d < best) { best = d; idx = n }
    }
    print idx }'
}

step() {  # step <delta>: move the selected value through the 256 colors
  local n
  n=$(index_of "${VALS[$sel]}")
  if (( n < 0 )); then n=0; (( $1 < 0 )) && n=255
  else n=$(( (n + $1 + 256) % 256 )); fi
  VALS[$sel]=$n
}

palette() {  # palette: the 256 colors, the selected value marked
  local cur n mark
  cur=$(index_of "${VALS[$sel]}")
  for (( n = 0; n < 256; n++ )); do
    mark="  "; (( n == cur )) && mark="[]"
    if (( n < 8 )); then printf '\e[%sm%s' "$((40 + n))" "$mark"
    elif (( n < 16 )); then printf '\e[%sm%s' "$((92 + n))" "$mark"
    else printf '\e[48;5;%sm%s' "$n" "$mark"; fi
    case $n in 15|51|87|123|159|195|231|255) printf '\e[0m\n' ;; esac
  done
}

frame() {  # frame: the whole screen as text
  local i v h
  printf 'usage-runway colors   ↑/↓ setting  ←/→ color  [ ] row  { } block\n'
  printf '                       t type a value  e empty (main color)  d dim  u undo  Enter save  q quit\n\n'
  printf '%s\n\n' "$PREVIEW"
  for i in "${!KEYS[@]}"; do
    v=${VALS[$i]} h=$(hex_of "$v")
    [ "$h" = "$v" ] && h=""
    if [ -z "$v" ]; then
      case ${KEYS[$i]} in BG) v="(none)" ;; COLOR_TEXT) v="(terminal default)" ;; *) v="(main color)" ;; esac
    fi
    if (( i == sel )); then printf '\e[7m> %-13s %-24s %s\e[0m' "${KEYS[$i]}" "$v${h:+  $h}" "${DESC[$i]}"
    else printf '  %-13s %-24s %s' "${KEYS[$i]}" "$v${h:+  $h}" "${DESC[$i]}"; fi
    [ "${VALS[$i]}" != "${ORIG[$i]}" ] && printf '  *'
    printf '\n'
  done
  printf '\n'
  palette
  [ -n "$msg" ] && printf '\n%s\n' "$msg"
}

# Build the frame first, then paint it over the previous one in a single write:
# no screen clear, each line ends with "clear to end of line", and "clear
# below" removes leftovers, so unchanged parts never blink.
draw() {
  local f
  render
  f=$(frame)
  msg=""
  f=${f//$'\n'/$'\e[K\n'}
  printf '\e[H%s\e[K\e[J' "$f"
}

read_key() {  # read_key: one key, arrows and page keys as names
  local k rest
  IFS= read -rsn1 k
  if [ "$k" = $'\e' ]; then
    IFS= read -rsn2 -t 1 rest
    case $rest in
      '[A') k=up ;; '[B') k=down ;; '[C') k=right ;; '[D') k=left ;;
      *) k=esc ;;
    esac
  fi
  [ -z "$k" ] && k=enter
  printf '%s' "$k"
}

while :; do
  draw
  case $(read_key) in
    up|k) sel=$(( (sel - 1 + ${#KEYS[@]}) % ${#KEYS[@]} )) ;;
    down|j) sel=$(( (sel + 1) % ${#KEYS[@]} )) ;;
    right|l) step 1 ;;
    left|h) step -1 ;;
    ']') step 36 ;; '[') step -36 ;;
    '}') step 6 ;; '{') step -6 ;;
    e) VALS[$sel]="" ;;
    d) [ "${KEYS[$sel]}" = BG ] && msg="dim is a text style; it does not apply to BG" || VALS[$sel]=dim ;;
    u) VALS[$sel]=${ORIG[$sel]} ;;
    t)
      printf '\e[?25h'; stty "$stty_saved"
      printf '\n%s (index 0-255, R;G;B, #rrggbb or rrggbb, dim, empty for default): ' "${KEYS[$sel]}"
      IFS= read -r v
      printf '\e[?25l'
      if color_valid "$v" && { [ "$v" != dim ] || [ "${KEYS[$sel]}" != BG ]; }; then VALS[$sel]=$v
      else msg="Not a color: $v"; fi ;;
    enter)
      sets=()
      for i in "${!KEYS[@]}"; do
        [ "${VALS[$i]}" != "${ORIG[$i]}" ] && sets+=("${KEYS[$i]}=${VALS[$i]}")
      done
      cleanup; trap - EXIT
      if [ ${#sets[@]} -eq 0 ]; then echo "No color changed."; exit 0; fi
      exec bash "$UR_ROOT/scripts/setup.sh" --set "${sets[@]}" ;;
    q|esc) cleanup; trap - EXIT; echo "Colors not changed."; exit 0 ;;
  esac
done
