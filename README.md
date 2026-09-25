# usage-runway

A Claude Code status line that shows how much of your subscription limits you
have used, where your current pace will take you by the time each limit resets,
and how much of it the current session and message are using.

```
5h 20.0% → 33.3% ↻ 02:00 (16:42) · 7d 30.0% → 52.0% ↻ 4d0h (Mon 13:00) · Ctx 12.3% · Ses 4.0% · Cmd 1.0%
```

It warns once when a limit is on track to run out early, and can optionally stop
Claude from running more tools when a limit is nearly used up.

## Install

```
/plugin marketplace add <owner>/usage-runway
/plugin install usage-runway@usage-runway
/usage-runway:setup
```

Plugins cannot set the status line themselves, so `/usage-runway:setup` adds it
to `~/.claude/settings.json`. It keeps a backup at
`settings.json.bak-usage-runway` and does not replace an existing status line
without asking. The status line appears within about 10 seconds. Setup
then asks for your working days and hours (default: every day, all day). Run
`/usage-runway:setup` again at any time to change them.

### Requirements

- `bash` and [`jq`](https://jqlang.org) (`apt install jq`, `brew install jq`).
- Linux or macOS.
- For the weekly forecast's night and weekend weighting: an `awk` with
  `strftime`/`mktime`, such as `gawk` or `mawk` 1.3.4+ (`brew install gawk` on
  macOS). Without one the weekly forecast uses plain wall-clock time.
- Limit numbers (`5h`, `7d`, `Ses`, `Cmd`) are available only for Claude Pro and
  Max subscriptions, after the first response in a session. API-key accounts see
  context usage and session cost.

## Reading the status line

| Part | Meaning |
|---|---|
| `5h 20.0%` | Share of the 5-hour limit used, across your whole account (all sessions, claude.ai, the desktop app). |
| `→ 33.3%` | Projected usage when the limit resets, at your current pace. It can exceed 100%. |
| `⚠ 00:40` | Shown in red when the projection passes 100%: time until the limit runs out. |
| `100% ⛔` | Limit used up. |
| `→ …` | Not enough data yet for a forecast. |
| `↻ 02:00 (16:42)` | Time until reset, and the reset time (24h; weekday prefix when not today). |
| `7d …` | The same for the weekly limit. |
| `Ctx 12.3%` | How full this session's context window is. |
| `Ses 4.0%` | 5-hour-limit usage by this session since it started or since `/clear`, across 5-hour resets. |
| `Cmd 1.0%` | 5-hour-limit usage by your last message, including all tools, skills and subagents it ran. |
| `$1.50` | Session cost at API list prices (see `SHOW_COST`). |

Colours: green is on track, yellow means the limit is projected above
`WARN_PCT` at reset, red means it is projected to run out before reset. `Cmd`
turns yellow at `CMD_WARN` and red at `CMD_CRIT`.

### How the forecast works

The pace is the average of two rates: the recent one (last 30 minutes for 5h,
last 6 hours for 7d) and the average since the window started. A single burst
therefore raises the forecast only partly; red requires sustained heavy use.

For the weekly limit you can set your working days and hours with
`/usage-runway:setup`. Hours outside `DAY_START`–`DAY_END` and days not in
`WORK_DAYS` count as `NIGHT_WEIGHT` and `OFF_DAY_WEIGHT` of a working hour,
both when measuring pace and when projecting it forward. By default every day
and every hour is a working one, so the forecast uses plain wall-clock time.
The forecast appears once the window has `MIN_DATA_7D` seconds of weighted time.

Each session receives limit numbers only with its own API responses. The
freshest value any session has seen is shared, so idle sessions stay current.

### Accuracy of Ses and Cmd

Claude Code reports limit usage for the whole account, in whole percent. `Ses`
and `Cmd` count a rise in 5-hour usage when it arrives together with this
session's own responses. Usage by another session working at the very same
moment can therefore land in this session's numbers, and values move in steps
of 1%.

Not counted in `Ses`/`Cmd` (but counted in `5h`): other sessions, headless
`claude -p` runs, claude.ai and the desktop app.

## Alerts and the guard

When a limit first turns yellow or red, each session shows a one-time message,
for example:

> ⚠ 5h limit: 45.0% used, at this pace it runs out in 00:40, resets in 02:00. Press Esc to stop the current task.

It also sends a desktop notification (`notify-send` on Linux, `osascript` on
macOS) and rings the terminal bell.

With `GUARD=on`, tool calls are denied once the 5-hour or weekly limit reaches
`GUARD_PCT`, and Claude is told to stop and ask you whether to continue. To keep
working in that session, run the `! touch …` command from the message, or set
`GUARD=off`.

## Settings

`~/.claude/usage-runway/config` holds your overrides (every default is listed
there, commented out). Changes apply on the next refresh.

| Setting | Default | Meaning |
|---|---|---|
| `WARN_PCT` | `80` | Projected % at reset that turns a limit yellow. |
| `LOOKBACK_5H`, `LOOKBACK_7D` | `1800`, `21600` | Recent-pace lookback, seconds. |
| `MIN_DATA_5H`, `MIN_DATA_7D` | `600`, `21600` | Window time before a forecast is shown, seconds. |
| `WORK_DAYS` | `"1 2 3 4 5 6 7"` | Working days for the weekly forecast, 1 = Monday. |
| `DAY_START`, `DAY_END` | `0`, `24` | Working hours for the weekly forecast, local time. |
| `NIGHT_WEIGHT`, `OFF_DAY_WEIGHT` | `0.1`, `0.1` | Weight of off hours and off days; `1` disables weighting. |
| `CMD_WARN`, `CMD_CRIT` | `3`, `5` | `Cmd` thresholds, %. |
| `SHOW_COST` | `auto` | `auto`: cost only without limit data; `on`; `off`. |
| `GUARD`, `GUARD_PCT` | `off`, `95` | Auto-stop guard. |
| `NOTIFY`, `BELL` | `on`, `on` | Desktop notification and terminal bell for alerts. |

Set `USAGE_RUNWAY_HOME` to keep settings and state somewhere other than
`~/.claude/usage-runway`.

## Uninstall

```
/usage-runway:setup uninstall
/plugin uninstall usage-runway@usage-runway
```

`/usage-runway:setup` with "uninstall and purge" also deletes
`~/.claude/usage-runway`.

## Development

```
bash tests/run.sh
claude plugin validate .
```

Local install for testing:

```
/plugin marketplace add /path/to/usage-runway
/plugin install usage-runway@usage-runway
```

## License

MIT
