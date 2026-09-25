#!/usr/bin/env bash
# usage-runway status line launcher, installed by setup.sh into
# ~/.claude/usage-runway/statusline.sh. The plugin's install path changes with
# every update, so this runs whichever version the SessionStart hook recorded.
d="${USAGE_RUNWAY_HOME:-$HOME/.claude/usage-runway}"
root=$(cat "$d/plugin-root" 2>/dev/null)
if [ -n "$root" ] && [ -f "$root/scripts/statusline.sh" ]; then
  exec bash "$root/scripts/statusline.sh"
fi
cat >/dev/null
