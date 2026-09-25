---
name: setup
description: Enable, check or remove the usage-runway status line in the user's Claude Code settings, and set the working days and hours used by the weekly forecast. Use when the user runs /usage-runway:setup, asks to turn the usage-runway status line on or off, to check its status, to change their usage-runway working days or hours, or to change the symbols or prefix it shows.
---

# usage-runway setup

Plugins cannot set the status line themselves, so this skill runs the plugin's
setup script, which edits `~/.claude/settings.json` (it keeps a backup at
`settings.json.bak-usage-runway`).

Pick the mode from the user's request (default: install):

| Request | Command |
|---|---|
| enable / install (default) | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"` |
| check status | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" --status` |
| disable / remove | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" --uninstall` |
| remove including settings and history | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" --uninstall --purge` |
| change working days / hours | the schedule steps below |
| change symbols (arrow, separator, …) or prefix | the symbols steps below |

If `${CLAUDE_PLUGIN_ROOT}` is not expanded in the command, use
`"$(cat ~/.claude/usage-runway/plugin-root)/scripts/setup.sh"` instead.

If the install exits with code 3, another status line is configured. Show the
user the existing command from the output and ask whether to replace it. Only
if they agree, re-run with `--force`.

## Schedule

Run this after a successful install, and when the user asks to change their
working days or hours. Ask both questions in one AskUserQuestion call
(single-select; the user can pick "Other" to type their own):

1. "Which days do you usually work?" (header "Work days"). Options:
   "Every day (Recommended)", "Monday to Friday", "Monday to Saturday".
2. "Which hours do you usually work?" (header "Work hours"). Options:
   "All day (Recommended)", "08:00 to 22:00", "09:00 to 18:00".

Map the answers to settings. Days are numbered 1 = Monday to 7 = Sunday. Hours
are whole hours from 0 to 24 local time, and DAY_START must be less than DAY_END.

| Answer | Setting |
|---|---|
| Every day | `WORK_DAYS="1 2 3 4 5 6 7"` |
| Monday to Friday | `WORK_DAYS="1 2 3 4 5"` |
| Monday to Saturday | `WORK_DAYS="1 2 3 4 5 6"` |
| All day | `DAY_START=0 DAY_END=24` |
| 08:00 to 22:00 | `DAY_START=8 DAY_END=22` |
| 09:00 to 18:00 | `DAY_START=9 DAY_END=18` |

Convert an "Other" answer the same way. For example, "Mon, Wed, Fri" becomes
`WORK_DAYS="1 3 5"` and "7am-3pm" becomes `DAY_START=7 DAY_END=15`. If an
answer is unclear, ask again. Do not guess.

Save the settings in one call:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" --set "WORK_DAYS=1 2 3 4 5" DAY_START=9 DAY_END=18
```

If it exits with code 1, show the user the error and ask again.

Hours outside the working hours and days outside the working days count as
`NIGHT_WEIGHT` and `OFF_DAY_WEIGHT` of a working hour (default 0.1) in the
weekly forecast. The user can change both in the config file.

## Symbols

Run this after the schedule step of an install, and when the user asks to
change the signs (symbols) or the prefix. These settings hold them:

| Setting | Default | Shown |
|---|---|---|
| `SYM_PREFIX` | empty | before the whole status line, e.g. to tell setups apart |
| `SYM_ARROW` | `→` | before the projected % |
| `SYM_RESET` | `↻` | before the time until reset |
| `SYM_SEP` | `·` | between segments |
| `SYM_WARN` | `⚠` | projected to hit 100% before reset, and before alerts |
| `SYM_FULL` | `⛔` | limit reached |
| `SYM_WAIT` | `…` | not enough data for a forecast yet |

If the user already named the signs they want, skip the menus and save them.
Otherwise first run `setup.sh --status` and read the `symbols:` lines, so you
can add " (current)" to the option that matches each current value.

### Menu 1: style

One AskUserQuestion (header "Signs"): "How do you want to change the status
line signs? Pick Other to type all your signs at once." Options:

- "Pick each sign (Recommended)": go to menus 2 and 3.
- "Plain ASCII": save `SYM_ARROW="->" SYM_RESET="@" SYM_SEP="|" SYM_WARN="!" SYM_FULL="FULL" SYM_WAIT="..."`.
- "Unicode defaults": save the defaults from the table above (all except
  `SYM_PREFIX`).
- "Prefix only": ask only the "Prefix" question from menu 2.
- "Other" (typed text): map what the user typed to the settings, for example
  "arrow >> sep /" becomes `SYM_ARROW=">>" SYM_SEP="/"`. If it is unclear,
  ask again. Do not guess.

### Menu 2 and menu 3: each sign

Ask menu 2 as one AskUserQuestion call with four questions, then menu 3 as
one call with three questions. All are single-select, and the user can pick
"Other" to type their own sign. Each question ends with "Pick Other to type
your own." as in the table, because the Other option is easy to miss. The
first option is the default, marked "(Recommended)". Give each option a `preview` showing an example line with
that sign, for example `5h 20.0% → 33.3% ↻ 02:00 (16:42) · 7d 30.0%`.

| Menu | Header | Question | Options (setting value) |
|---|---|---|---|
| 2 | Prefix | "What text should come before the status line? Pick Other to type your own." | "None" (empty), "[work]" (`[work] `), "[home]" (`[home] `) |
| 2 | Arrow | "Which sign should point to the projected usage? Pick Other to type your own." | "→", "->", "»" |
| 2 | Reset | "Which sign should mark the time until reset? Pick Other to type your own." | "↻", "⟳", "@" |
| 2 | Separator | "Which sign should separate the segments? Pick Other to type your own." | "·", "\|", "•" |
| 3 | Warning | "Which sign should warn that a limit runs out before reset? Pick Other to type your own." | "⚠", "!", "‼" |
| 3 | Limit hit | "Which sign should show a limit is reached? Pick Other to type your own." | "⛔", "✖", "FULL" |
| 3 | Waiting | "Which sign should show there is no forecast yet? Pick Other to type your own." | "…", "...", "?" |

For a prefix typed with "Other", add a trailing space unless the user asked
for none, so the prefix does not run into `5h`.

### Save

Save only the settings that differ from their current values, in one call:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" --set "SYM_ARROW=->" "SYM_SEP=|" "SYM_PREFIX=[work] "
```

Each value other than `SYM_PREFIX` is 1 to 16 bytes (a Unicode symbol takes 2
to 4). `SYM_PREFIX` can be any length, or empty to remove it. None may contain
`"`, `\`, `$`, backtick or control characters. If the call exits with code 1,
show the user the error and ask that question again. Afterwards, tell the user
the status line picks up the change on its next refresh (about 10 seconds).

## After install

After a successful install and the schedule and symbols steps, tell the user:

- The status line appears within about 10 seconds.
- Limit numbers (`5h`, `7d`, `Ses`, `Cmd`) appear after the first response in a
  session, and only for Claude Pro/Max subscriptions. API-key accounts see
  context usage and session cost instead.
- Settings such as the auto-stop guard (`GUARD=on`) are in
  `~/.claude/usage-runway/config`.
- To change the working days and hours, or the signs and prefix, later, run
  `/usage-runway:setup` again and ask for that change.
