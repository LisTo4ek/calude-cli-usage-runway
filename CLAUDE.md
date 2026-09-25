# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Claude Code plugin, written in bash and jq with no build step. It provides a status line that forecasts the 5-hour and weekly subscription limits, plus hooks for one-time alerts and an optional guard that stops tool calls. `README.md` is the user-facing spec for the output format, colours and settings. Keep it in sync when behaviour changes.

## Commands

```
bash tests/run.sh          # full test suite (prints "N passed, M failed", exit 1 on failure)
claude plugin validate .   # validate .claude-plugin/ manifests
```

There is no way to run a single test. `tests/run.sh` is one sequential script: each scenario starts with `fresh`, which creates an isolated temp `USAGE_RUNWAY_HOME` and `CLAUDE_CONFIG_DIR`. To try one case by hand, feed JSON to the script the same way the tests do:

```
export USAGE_RUNWAY_HOME=$(mktemp -d) CLAUDE_CONFIG_DIR=$(mktemp -d)
jq -n '{session_id:"A",cost:{total_cost_usd:1},rate_limits:{five_hour:{used_percentage:20,resets_at:(now+7200|floor)}}}' | bash scripts/statusline.sh
jq -n '{session_id:"A",hook_event_name:"PreToolUse"}' | bash scripts/hook.sh
```

Test helpers: `input` builds statusLine JSON, `hook` builds hook JSON, `sample` seeds forecast history, `conf` appends a config override, and `check`/`check_not` do substring asserts on output with ANSI codes stripped.

## Architecture

There are two entry points. The status line and the hooks never call each other. They talk only through files in `$UR_HOME/state` (`~/.claude/usage-runway/state`, or `$USAGE_RUNWAY_HOME/state` when that is set).

- **`scripts/statusline.sh`**: Claude Code runs it every 10s with statusLine JSON on stdin. It does all the computation. It writes forecast samples, the current level for each limit, per-session accumulators and alerts to state, then prints the line.
- **`scripts/hook.sh`**: one script for `SessionStart`, `UserPromptSubmit` and `PreToolUse` (see `hooks/hooks.json`). It branches on `hook_event_name`. It reads what the status line wrote and shows each alert once per session. With `GUARD=on` it denies tool calls. It also records the plugin path and the turn start used for `Cmd`.
- **`scripts/common.sh`**: sourced by every script. It sets `LC_ALL=C`, resolves `UR_ROOT`, `UR_HOME`, `UR_STATE` and `UR_SETTINGS`, and sources `config.default` and then the user's `$UR_HOME/config`. Settings are plain shell variables. To add a setting, add it with a comment to `config.default` and to the README table.
- **Launcher indirection**: plugins cannot set `statusLine`, so `scripts/setup.sh` (run by `skills/setup/SKILL.md`) copies `scripts/launcher.sh` to `$UR_HOME/statusline.sh` and points `settings.json` at that copy. The plugin's install path changes with every update. The `SessionStart` hook therefore writes the current `UR_ROOT` to `$UR_HOME/plugin-root`, and the launcher runs `statusline.sh` from that path.
- The setup skill's schedule menu (AskUserQuestion presets) writes settings through `setup.sh --set KEY=VALUE`. The config is sourced by bash, so `--set` only accepts a whitelist of keys with checked values. Extend that validation when you expose another setting.
- `setup.sh` exits with **code 3** when another status line is configured. The skill relies on this to ask the user before re-running with `--force`.

### State files (in `$UR_STATE`)

| File | Writer → reader | Content |
|---|---|---|
| `samples-<five_hour\|seven_day>` | statusline | `resets_at ts used` history for the pace. Pruned to the current window and 2× lookback. |
| `current-<name>` | statusline → hook (guard) | `name upct proj eta resets_at level ts` |
| `alerted` / `alerts` | statusline → hook | Alert IDs `name-resets_at-level`, one per window per level. `alerts` is `id\treset\ttext`. |
| `seen-<sid>` | hook | Alert IDs already shown in this session. |
| `latest-rl`, `obs-<sid>` | statusline | Freshest rate limits shared across sessions (see below). |
| `acc-<sid>` | statusline → hook | `resets_at h5used cost total`, the running `Ses` total. |
| `turn-<sid>` | hook → statusline | `Ses` total when the prompt was submitted, the base for `Cmd`. |
| `bypass-<sid>` | user (`touch`) | Turns the guard off for one session. |
| `time-awk` | common.sh | Cached name of an awk with `strftime`/`mktime` (empty if none). |

Per-session files older than 7 days are deleted in `session_total`.

### Key ideas that span functions

- **Attribution by cost growth**: a session counts as having produced fresh rate-limit data, and a rise in 5h usage counts toward its `Ses`, only when `cost.total_cost_usd` grew since its previous render. `sync_rate_limits` uses this rule to decide whether to publish to `latest-rl` or to adopt a newer value from it. `session_total` uses it to decide whether a rise belongs to this session.
- **Forecast** (`forecast` in statusline.sh, mostly an embedded awk program): the pace is the average of the recent pace (over the lookback) and the pace since the window started. For 7d, time is weighted by the schedule (`WORK_DAYS`, `DAY_START`/`DAY_END`, `NIGHT_WEIGHT`, `OFF_DAY_WEIGHT`) using `W()`, `until_w()` and `next_day()`. Without a time-capable awk, `TIME_FUNCS` swaps in stubs so the forecast falls back to wall-clock time. Samples match their window when their `resets_at` is within ±300s.

## Constraints

- Must run on **bash 3.2** (the macOS default) and on Linux. That rules out associative arrays and `${var,,}`. Empty arrays are expanded with `${a[@]+"${a[@]}"}` because of `set -u`.
- Dates: use `fmt_date`, which tries GNU `date -d` and falls back to BSD `date -r`. Do not assume gawk. Code that needs `strftime`/`mktime` must go through `time_awk` and keep its fallback.
- `LC_ALL=C` is required for decimal points in `printf` and awk. A test covers this under a comma locale.
- Never let a script fail loudly. If jq is missing, the status line prints a hint and the hook exits 0. Hook output is JSON on stdout (`systemMessage`, `hookSpecificOutput.permissionDecision`).
