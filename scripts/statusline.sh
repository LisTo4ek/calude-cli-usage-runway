#!/usr/bin/env bash
# usage-runway status line. Reads the Claude Code statusLine JSON on stdin and
# prints one line: 5h / 7d limit usage with a forecast to reset, context usage,
# this session's and this message's share of the 5h limit.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if ! command -v jq >/dev/null 2>&1; then
  cat >/dev/null
  echo "usage-runway: jq is required (https://jqlang.org)"
  exit 0
fi
mkdir -p "$UR_STATE"

in=$(cat)
now=$(date +%s)

IFS=$'\t' read -r sid ctx cost h5u h5r d7u d7r < <(jq -r '[
  (.session_id // "unknown"),
  (.context_window.used_percentage // "-"),
  (.cost.total_cost_usd // 0),
  (.rate_limits.five_hour.used_percentage // "-"),
  (.rate_limits.five_hour.resets_at // "-"),
  (.rate_limits.seven_day.used_percentage // "-"),
  (.rate_limits.seven_day.resets_at // "-")
] | @tsv' <<<"$in")

K=$'\e[90m'; B=$'\e[34m'; R=$'\e[31m'; Y=$'\e[33m'; G=$'\e[32m'; D=$'\e[2m'; N=$'\e[0m'

# Rate limits arrive with each session's own API responses, so an idle session
# holds stale values. The freshest observation is shared across sessions: a
# session's values are fresh when its cost grew since its previous render. A
# session without values of its own yet (before its first response) adopts the
# shared ones.
sync_rate_limits() {
  local acc="$UR_STATE/acc-$sid" latest="$UR_STATE/latest-rl" own="$UR_STATE/obs-$sid"
  local lr lu lc lt fresh=0 ots=0 gts g5u g5r g7u g7r
  if [ "$h5u" = "-" ] && [ "$d7u" = "-" ]; then
    { [ -f "$latest" ] && read -r gts g5u g5r g7u g7r < "$latest"; } || return
    [ "$g5r" != "-" ] && (( ${g5r%.*} > now )) && { h5u=$g5u; h5r=$g5r; }
    [ "$g7r" != "-" ] && (( ${g7r%.*} > now )) && { d7u=$g7u; d7r=$g7r; }
    return
  fi
  if [ -f "$acc" ] && read -r lr lu lc lt < "$acc"; then
    awk -v c="$cost" -v l="$lc" 'BEGIN { exit !(c > l) }' && fresh=1
  else
    fresh=1
  fi
  if [ "$fresh" = 1 ]; then
    echo "$now" > "$own"
    printf '%s %s %s %s %s\n' "$now" "$h5u" "$h5r" "$d7u" "$d7r" > "$latest.tmp" && mv "$latest.tmp" "$latest"
    return
  fi
  [ -f "$own" ] && read -r ots < "$own"
  { [ -f "$latest" ] && read -r gts g5u g5r g7u g7r < "$latest"; } || return
  (( gts > ots )) || return
  [ "$g5r" != "-" ] && (( ${g5r%.*} > now )) && { h5u=$g5u; h5r=$g5r; }
  [ "$g7r" != "-" ] && (( ${g7r%.*} > now )) && { d7u=$g7u; d7r=$g7r; }
}
sync_rate_limits

fmt_dur() {
  local s=$1
  if (( s < 86400 )); then printf '%02d:%02d' $(( s / 3600 )) $(( s % 3600 / 60 ))
  else printf '%dd%dh' $(( s / 86400 )) $(( s % 86400 / 3600 ))
  fi
}

# Reset time of day, 24h; weekday prefix when it is not today.
fmt_clock() {
  if [ "$(fmt_date "$1" +%F)" = "$(date +%F)" ]; then
    fmt_date "$1" +%H:%M
  else
    fmt_date "$1" '+%a %H:%M'
  fi
}

TAWK=$(time_awk)

# Time-weighting helpers for the forecast program. Without an awk that has
# strftime/mktime they are stubs and the forecast uses wall-clock time.
if [ -n "$TAWK" ]; then
  FAWK=$TAWK
  TIME_FUNCS='
    # Usage weight at t relative to a working hour: off hours count as nw,
    # days not in WORK_DAYS as ww (off-day off hours as the smaller of the two).
    function wday(t,   h, day, we) {
      h = strftime("%H", t) + 0; day = (h >= ds && h < de)
      we = !index(" " wd " ", " " strftime("%u", t) " ")
      if (we) return day ? ww : (ww < nw ? ww : nw)
      return day ? 1 : nw }
    # Next point after t where the weight can change: DAY_START, DAY_END or midnight.
    function next_day(t,   d, a, b, c) { d = strftime("%Y %m %d", t); split(d, a, " ")
      b = mktime(a[1] " " a[2] " " a[3] " " ds " 00 00")
      c = mktime(a[1] " " a[2] " " a[3] " " de " 00 00")
      if (b > t) return b
      if (c > t) return c
      return mktime(a[1] " " a[2] " " (a[3] + 1) " 00 00 00") }'
else
  FAWK=awk
  TIME_FUNCS='
    function wday(t) { return 1 }
    function next_day(t) { return t + 86400 }'
fi

# forecast <name> <label> <window_len> <lookback> <used> <resets_at>
forecast() {
  local name=$1 label=$2 len=$3 lb=$4 u=$5 r=$6
  { [ "$u" = "-" ] || [ "$r" = "-" ]; } && return
  local f="$UR_STATE/samples-$name" r0 last
  r0=${r%.*}

  # Keep samples of the current window only, drop the ones outside 2x lookback.
  if [ -f "$f" ]; then
    awk -v r="$r0" -v now="$now" -v lb="$lb" \
      '($1-r<300 && r-$1<300) && now-$2<=2*lb' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  fi
  last=$(tail -n1 "$f" 2>/dev/null | awk '{print $2}')
  if [ -z "$last" ] || (( now - last >= 30 )); then
    echo "$r0 $now $u" >> "$f"
  fi

  local proj eta projd weighted=0 mindata=$MIN_DATA_5H
  if [ "$name" = seven_day ]; then
    mindata=$MIN_DATA_7D
    [ -n "$TAWK" ] && weighted=1
  fi
  read -r proj eta projd < <("$FAWK" -v now="$now" -v u="$u" -v r="$r0" -v len="$len" \
      -v lb="$lb" -v span="$MIN_SPAN" -v weighted="$weighted" -v ww="$OFF_DAY_WEIGHT" -v wd="$WORK_DAYS" \
      -v mindata="$mindata" -v nw="$NIGHT_WEIGHT" -v ds="$DAY_START" -v de="$DAY_END" "$TIME_FUNCS"'
    # Weighted seconds between a and b.
    function W(a, b,   s, n) { if (!weighted) return b - a
      s = 0; while (a < b) { n = next_day(a); if (n > b) n = b; s += (n - a) * wday(a); a = n }
      return s }
    # Real seconds from t until w weighted seconds have passed (capped at 30 days).
    function until_w(t, w,   start, n, seg) { if (!weighted) return w
      start = t; while (t - start < 2592000) { n = next_day(t); seg = (n - t) * wday(t)
        if (seg >= w) return t - start + (wday(t) > 0 ? w / wday(t) : 0); w -= seg; t = n }
      return 2592000 }
    now-$2<=lb { if (t0=="" || $2<t0) { t0=$2; u0=$3 } }
    END {
      # Blend the recent pace with the whole-window average so a single burst
      # cannot drive the forecast on its own. Paces are per weighted second.
      recent=-1; avg=-1
      if (t0!="" && now-t0>=span) {
        dw=W(t0, now)
        # Skip the recent pace when it was measured mostly in low-weight hours.
        if (dw >= 0.5*(now-t0)) { recent=(u-u0)/dw; if (recent<0) recent=0 }
      }
      ew=W(r-len, now); if (ew>=mindata) avg=u/ew
      if (recent>=0 && avg>=0) rate=(recent+avg)/2
      else if (avg>=0) rate=avg
      else { print "- -1 -"; exit }
      proj=u+rate*W(now, r)
      eta=(rate>0) ? until_w(now, (100-u)/rate) : -1
      printf "%.0f %d %.1f\n", proj, eta, proj
    }' "$f")

  local left=$(( r0 - now )) level color seg upct upd reset
  (( left < 0 )) && left=0
  upct=$(printf '%.0f' "$u")
  upd=$(printf '%.1f' "$u")
  reset="${K}${SYM_RESET}${N} ${D}$(fmt_dur "$left") ($(fmt_clock "$r0"))${N}"
  if (( upct >= 100 )) || { (( eta >= 0 )) && (( eta < left )); }; then
    level=crit; color=$R
  elif [ "$proj" = "-" ]; then
    level=ok; color=$D
  elif (( proj >= WARN_PCT )); then
    level=warn; color=$Y
  else
    level=ok; color=$G
  fi

  if [ "$level" = crit ] && (( upct >= 100 )); then
    seg="${B}${label}${N} ${color}100% ${SYM_FULL}${N} $reset"
  elif [ "$level" = crit ]; then
    seg="${B}${label}${N} ${color}${upd}%${N} ${K}${SYM_ARROW}${N} ${color}${projd}% ${SYM_WARN} $(fmt_dur "$eta")${N} $reset"
  elif [ "$proj" = "-" ]; then
    seg="${B}${label}${N} ${color}${upd}%${N} ${K}${SYM_ARROW}${N} ${color}${SYM_WAIT}${N} $reset"
  else
    seg="${B}${label}${N} ${color}${upd}%${N} ${K}${SYM_ARROW}${N} ${color}${projd}%${N} $reset"
  fi
  SEGS+=("$seg")

  echo "$name $upct $proj $eta $r0 $level $now" > "$UR_STATE/current-$name"

  # One alert per window per level; hook.sh shows it once in each session.
  if [ "$level" != ok ]; then
    local id="$name-$r0-$level" text
    if ! grep -qxF "$id" "$UR_STATE/alerted" 2>/dev/null; then
      echo "$id" >> "$UR_STATE/alerted"
      if [ "$level" = crit ]; then
        text="${label} limit: ${upd}% used, at this pace it runs out in $(fmt_dur "$eta"), resets in $(fmt_dur "$left"). Press Esc to stop the current task."
      else
        text="${label} limit: ${upd}% used, projected ${projd}% by reset in $(fmt_dur "$left")."
      fi
      printf '%s\t%s\t%s\n' "$id" "$r0" "$text" >> "$UR_STATE/alerts"
      notify "$text"
    fi
  fi
}

# 5h usage accumulated by this session since it started (or since /clear, which
# starts a new session). A rise in 5h usage counts when this session's cost grew
# since its previous render, i.e. the rise came with its own API responses.
session_total() {
  { [ "$h5u" = "-" ] || [ "$h5r" = "-" ]; } && return
  local f="$UR_STATE/acc-$sid" r0=${h5r%.*} lr lu lc total=0.0
  if [ -f "$f" ] && read -r lr lu lc total < "$f"; then
    total=$(awk -v u="$h5u" -v r="$r0" -v lr="$lr" -v lu="$lu" -v c="$cost" -v lc="$lc" -v t="$total" '
      BEGIN { if (c > lc) { d = (lr-r<300 && r-lr<300) ? u-lu : u; if (d > 0) t += d }
              printf "%.1f", t }')
  fi
  echo "$r0 $h5u $cost $total" > "$f"
  find "$UR_STATE" -maxdepth 1 \( -name 'acc-*' -o -name 'turn-*' -o -name 'seen-*' -o -name 'obs-*' \) \
    -mtime +7 -delete 2>/dev/null
  SESS_TOTAL=$total
}

# This session's usage since the current message was submitted (hook.sh records
# the session total at prompt start).
turn_delta() {
  [ -n "$SESS_TOTAL" ] || return
  local f="$UR_STATE/turn-$sid" start d color=$N
  { [ -f "$f" ] && read -r start < "$f"; } || return
  d=$(awk -v t="$SESS_TOTAL" -v s="$start" 'BEGIN { d = t - s; if (d < 0) d = 0; printf "%.1f", d }')
  if awk -v d="$d" -v c="$CMD_CRIT" 'BEGIN { exit !(d >= c) }'; then color=$R
  elif awk -v d="$d" -v w="$CMD_WARN" 'BEGIN { exit !(d >= w) }'; then color=$Y; fi
  TURN_SEG="${color}${d}%${N}"
}

SEGS=()
forecast five_hour 5h 18000 "$LOOKBACK_5H" "$h5u" "$h5r"
forecast seven_day 7d 604800 "$LOOKBACK_7D" "$d7u" "$d7r"

[ "$ctx" != "-" ] && SEGS+=("${B}Ctx${N} $(printf '%.1f' "$ctx")%")

TURN_SEG=""; SESS_TOTAL=""
session_total
turn_delta
if [ -n "$SESS_TOTAL" ]; then
  SEGS+=("${B}Ses${N} ${SESS_TOTAL}%")
  [ -n "$TURN_SEG" ] && SEGS+=("${B}Cmd${N} ${TURN_SEG}")
fi

# No limit data from this session or a recent one: first render, or an API-key
# account.
if [ "$h5u" = "-" ] && [ "$d7u" = "-" ]; then
  SEGS=("Usage runway: starting..." ${SEGS[@]+"${SEGS[@]}"})
fi

out=""
for s in ${SEGS[@]+"${SEGS[@]}"}; do out+="${out:+ ${K}${SYM_SEP}${N} }$s"; done
printf '%s%s\n' "$SYM_PREFIX" "$out"
