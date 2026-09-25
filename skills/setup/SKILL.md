---
name: setup
description: Enable, check or remove the usage-runway status line in the user's Claude Code settings, and set the working days and hours used by the weekly forecast. Use when the user runs /usage-runway:setup, asks to turn the usage-runway status line on or off, to check its status, or to change their usage-runway working days or hours.
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

## After install

After a successful install and the schedule step, tell the user:

- The status line appears within about 10 seconds.
- Limit numbers (`5h`, `7d`, `Ses`, `Cmd`) appear after the first response in a
  session, and only for Claude Pro/Max subscriptions. API-key accounts see
  context usage and session cost instead.
- Settings such as the auto-stop guard (`GUARD=on`) are in
  `~/.claude/usage-runway/config`.
