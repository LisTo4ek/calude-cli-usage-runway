#!/usr/bin/env bash
# usage-runway setup: points the Claude Code status line at the usage-runway
# launcher. Plugins cannot set the status line themselves, so this edits the
# user's settings.json (a backup is written next to it first).
#
#   setup.sh            install; refuses to replace another status line
#   setup.sh --force    install, replacing another status line
#   setup.sh --status   show what is configured
#   setup.sh --uninstall [--purge]   remove the status line (--purge: also data)
#   setup.sh --set KEY=VALUE...      write settings to the user config
#                                    (WORK_DAYS, DAY_START, DAY_END, SYM_PREFIX,
#                                    SYM_ARROW, SYM_RESET, SYM_SEP, SYM_WARN,
#                                    SYM_FULL, SYM_WAIT, BG)
#
# Exit codes: 0 ok, 1 error, 3 another status line is configured.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

mode=install force=0 purge=0 sets=()
for a in "$@"; do
  case $a in
    --force) force=1 ;;
    --status) mode=status ;;
    --uninstall) mode=uninstall ;;
    --purge) purge=1 ;;
    --set) mode=set ;;
    [A-Z]*=*) [ "$mode" = set ] || { echo "KEY=VALUE needs --set: $a" >&2; exit 1; }; sets+=("$a") ;;
    *) echo "unknown option: $a" >&2; exit 1 ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "usage-runway needs jq: https://jqlang.org (apt install jq / brew install jq)" >&2
  exit 1
fi

launcher="$UR_HOME/statusline.sh"
current=""
[ -f "$UR_SETTINGS" ] && current=$(jq -r '.statusLine.command // ""' "$UR_SETTINGS")
ours=0
case $current in "$launcher"|*usage-runway*) ours=1 ;; esac

# The config is sourced by bash, so only known keys with checked values are written.
days_re='^[1-7]( [1-7])*$' hour_re='^[0-9]{1,2}$'
prefix_re='^[^"\$`[:cntrl:]]*$'   # no quote, backslash, $, backtick or control chars
sym_re='^[^"\$`[:cntrl:]]{1,16}$'

ensure_config() {
  mkdir -p "$UR_HOME"
  [ -f "$UR_HOME/config" ] || sed 's/^\([A-Z_]*=\)/# \1/' "$UR_ROOT/config.default" > "$UR_HOME/config"
}

set_config() {  # set_config KEY VALUE: replace (or uncomment) KEY in the user config
  local f="$UR_HOME/config"
  awk -v k="$1" -v v="$2" '
    $0 ~ "^(# )?" k "=" { if (!done) print k "=\"" v "\""; done = 1; next }
    { print }
    END { if (!done) print k "=\"" v "\"" }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

write_settings() {  # write_settings <jq filter> [jq args...]
  local filter=$1; shift
  mkdir -p "$(dirname "$UR_SETTINGS")"
  [ -f "$UR_SETTINGS" ] || echo '{}' > "$UR_SETTINGS"
  cp "$UR_SETTINGS" "$UR_SETTINGS.bak-usage-runway"
  jq "$@" "$filter" "$UR_SETTINGS" > "$UR_SETTINGS.tmp" && mv "$UR_SETTINGS.tmp" "$UR_SETTINGS"
}

case $mode in
  status)
    echo "settings:    $UR_SETTINGS"
    echo "status line: ${current:-<none>}"
    [ "$ours" = 1 ] && echo "usage-runway status line is enabled." || echo "usage-runway status line is not enabled."
    echo "plugin:      $(cat "$UR_HOME/plugin-root" 2>/dev/null || echo "$UR_ROOT")"
    echo "config:      $UR_HOME/config"
    echo "schedule:    days $WORK_DAYS, hours $DAY_START-$DAY_END (1 = Monday)"
    echo "symbols:     SYM_PREFIX=\"$SYM_PREFIX\" SYM_ARROW=\"$SYM_ARROW\" SYM_RESET=\"$SYM_RESET\" SYM_SEP=\"$SYM_SEP\""
    echo "             SYM_WARN=\"$SYM_WARN\" SYM_FULL=\"$SYM_FULL\" SYM_WAIT=\"$SYM_WAIT\""
    echo "background:  BG=\"$BG\""
    awk_name=$(time_awk)
    echo "time awk:    ${awk_name:-<none: weekly forecast uses wall-clock time>}"
    ;;

  install)
    if [ -n "$current" ] && [ "$ours" = 0 ] && [ "$force" = 0 ]; then
      echo "Another status line is configured: $current"
      echo "Re-run with --force to replace it (a backup of settings.json is kept)."
      exit 3
    fi
    mkdir -p "$UR_STATE"
    echo "$UR_ROOT" > "$UR_HOME/plugin-root"
    cp "$UR_ROOT/scripts/launcher.sh" "$launcher" && chmod +x "$launcher"
    ensure_config
    write_settings '.statusLine = {type: "command", command: $cmd, padding: 0, refreshInterval: 10}' \
      --arg cmd "$launcher"
    echo "usage-runway status line enabled (backup: $UR_SETTINGS.bak-usage-runway)."
    echo "Settings: $UR_HOME/config"
    ;;

  set)
    [ ${#sets[@]} -gt 0 ] || { echo "--set needs KEY=VALUE arguments" >&2; exit 1; }
    ds=$DAY_START de=$DAY_END
    for kv in "${sets[@]}"; do
      k=${kv%%=*} v=${kv#*=}
      case $k in
        WORK_DAYS)
          [[ $v =~ $days_re ]] || { echo "WORK_DAYS: space-separated days 1-7 (1 = Monday), got: $v" >&2; exit 1; } ;;
        DAY_START|DAY_END)
          [[ $v =~ $hour_re ]] && (( 10#$v <= 24 )) || { echo "$k: an hour 0-24, got: $v" >&2; exit 1; }
          v=$((10#$v))
          [ "$k" = DAY_START ] && ds=$v || de=$v ;;
        SYM_PREFIX)
          [[ $v =~ $prefix_re ]] || { echo "SYM_PREFIX: text without \", \\, \$, \` or control characters, got: $v" >&2; exit 1; } ;;
        SYM_ARROW|SYM_RESET|SYM_SEP|SYM_WARN|SYM_FULL|SYM_WAIT)
          [[ $v =~ $sym_re ]] || { echo "$k: 1-16 bytes (a Unicode symbol is 2-4) without \", \\, \$, \` or control characters, got: $v" >&2; exit 1; } ;;
        BG)
          bg_valid "$v" || { echo "BG: empty, a colour index 0-255 or R;G;B (each 0-255), got: $v" >&2; exit 1; } ;;
        *) echo "unsupported setting: $k (supported: WORK_DAYS, DAY_START, DAY_END, SYM_PREFIX, SYM_ARROW, SYM_RESET, SYM_SEP, SYM_WARN, SYM_FULL, SYM_WAIT, BG)" >&2; exit 1 ;;
      esac
    done
    (( ds < de )) || { echo "DAY_START ($ds) must be before DAY_END ($de)" >&2; exit 1; }
    ensure_config
    for kv in "${sets[@]}"; do
      k=${kv%%=*} v=${kv#*=}
      case $k in DAY_START|DAY_END) v=$((10#$v)) ;; esac
      set_config "$k" "$v"
    done
    echo "Saved to $UR_HOME/config: ${sets[*]}"
    ;;

  uninstall)
    if [ "$ours" = 1 ]; then
      write_settings 'del(.statusLine)'
      echo "usage-runway status line removed from $UR_SETTINGS."
    else
      echo "usage-runway status line is not configured; settings.json left unchanged."
    fi
    if [ "$purge" = 1 ]; then
      rm -rf "$UR_HOME"
      echo "Removed $UR_HOME."
    fi
    echo "To remove the hooks as well, uninstall the plugin: /plugin uninstall usage-runway"
    ;;
esac
