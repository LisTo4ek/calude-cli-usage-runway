---
name: setup
description: Enable, check or remove the usage-runway status line in the user's Claude Code settings, and set the working days and hours used by the weekly forecast. Use when the user runs /usage-runway:setup, asks to turn the usage-runway status line on or off, to check its status, to change their usage-runway working days or hours, or to change the symbols or prefix it shows.
argument-hint: "[status | uninstall | Mon to Fri | 9 to 18 | arrow -> | sep / | prefix [work] | plain ASCII]"
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
| change working days / hours, symbols (arrow, separator, …) or prefix | the settings menu below |

If `${CLAUDE_PLUGIN_ROOT}` is not expanded in the command, use
`"$(cat ~/.claude/usage-runway/plugin-root)/scripts/setup.sh"` instead.

If the install exits with code 3, another status line is configured. Show the
user the existing command from the output and ask whether to replace it. Only
if they agree, re-run with `--force`.

## Settings menu

Run this after a successful install, and when the user asks to change their
working days, hours, signs (symbols) or prefix. The main menu is one
AskUserQuestion call with four single-select questions. Only if the user
picks "Pick each sign" do you ask the sign menus that follow it.

If the user already said what they want (for example "arrow ->" or "Mon to
Fri, 9 to 18"), skip the menu and save just that.

If the user names a setting without a value (for example "prefix" or
"arrow"), skip the main menu and ask only that setting's question in one
AskUserQuestion call. For work days, work hours and the prefix, use its
question from the main menu. For a sign, use its question from the sign menus.
Mark the current value the same way as below.

First run `setup.sh --status` and read the `schedule:` and `symbols:` lines.
Add " (current)" to the option that matches each current value. If the
current value matches no option, replace the third option with
"Keep current: <value>".

Do not give any option a `preview`. Previews hide the automatic "Other" text
field, which is where the user types their own value.

| Header | Question | Options |
|---|---|---|
| Work days | "Which days do you usually work? Pick Other to type your own, e.g. Mon, Wed, Fri." | "Every day (Recommended)", "Monday to Friday", "Monday to Saturday" |
| Work hours | "Which hours do you usually work? Pick Other to type your own, e.g. 7-15." | "All day (Recommended)", "08:00 to 22:00", "09:00 to 18:00" |
| Signs | "Which status line signs? Pick Other to set single signs, e.g. arrow -> reset @ sep \| (names: arrow, reset, sep, warn, full, wait)." | "Keep current (Recommended)", "Pick each sign", "Unicode defaults", "Plain ASCII" |
| Prefix | "What text should come before the status line? Pick Other to type your own." | "None (Recommended)", "[work]", "[home]" |

Give each option a short `description`. For "Keep current", list the current
signs. For "Pick each sign", say it opens a menu with one question per sign.
For the other sign sets and the prefixes, show an example line such as
`5h 20.0% → 33.3% ↻ 02:00 (16:42) · 7d 30.0%`.

### Sign menus

Ask these only if the user picked "Pick each sign". AskUserQuestion takes at
most four questions per call, so ask menu A as one call with four questions,
then menu B as one call with two. All are single-select, and like the main
menu they have no previews. Mark the option that matches the current value
with " (current)"; if the current value matches no option, replace the third
option with "Keep current: <value>". Give each option a `description` with an
example line using that sign, such as `5h 20.0% -> 33.3% ↻ 02:00 (16:42) · 7d
30.0%`.

Give each sign question exactly three options. AskUserQuestion adds "Other"
as the fourth option, and it has a text field where the user types their own
sign right in the menu. Do not add a "Type my own" option and do not ask for
a custom sign in a later message. Use the typed text as the value.

| Menu | Header | Question | Options (setting value) |
|---|---|---|---|
| A | Arrow | "Which sign should point to the projected usage? Pick Other to type your own." | "→" (default), "->", "»" |
| A | Reset | "Which sign should mark the time until reset? Pick Other to type your own." | "↻" (default), "⟳", "@" |
| A | Separator | "Which sign should separate the segments? Pick Other to type your own." | "·" (default), "\|", "•" |
| A | Warning | "Which sign should warn that a limit runs out before reset? Pick Other to type your own." | "⚠" (default), "!", "‼" |
| B | Limit hit | "Which sign should show a limit is reached? Pick Other to type your own." | "⛔" (default), "✖", "FULL" |
| B | Waiting | "Which sign should show there is no forecast yet? Pick Other to type your own." | "…" (default), "...", "?" |

The option label is the setting value, so "->" in Arrow becomes
`SYM_ARROW="->"`. Mark no option "(Recommended)"; label the default option
"→ (default)" and so on, and drop " (default)" from the saved value.

### Map the answers

Days are numbered 1 = Monday to 7 = Sunday. Hours are whole hours from 0 to
24 local time, and DAY_START must be less than DAY_END.

| Answer | Setting |
|---|---|
| Every day | `WORK_DAYS="1 2 3 4 5 6 7"` |
| Monday to Friday | `WORK_DAYS="1 2 3 4 5"` |
| Monday to Saturday | `WORK_DAYS="1 2 3 4 5 6"` |
| All day | `DAY_START=0 DAY_END=24` |
| 08:00 to 22:00 | `DAY_START=8 DAY_END=22` |
| 09:00 to 18:00 | `DAY_START=9 DAY_END=18` |
| Keep current (signs) | nothing |
| Pick each sign | the answers from the sign menus |
| Unicode defaults | the defaults from the table below, all except `SYM_PREFIX` |
| Plain ASCII | `SYM_ARROW="->" SYM_RESET="@" SYM_SEP="\|" SYM_WARN="!" SYM_FULL="FULL" SYM_WAIT="..."` |
| None | `SYM_PREFIX=""` |
| [work] / [home] | `SYM_PREFIX="[work] "` / `SYM_PREFIX="[home] "` |

| Sign name | Setting | Default | Shown |
|---|---|---|---|
| (prefix) | `SYM_PREFIX` | empty | before the whole status line, e.g. to tell setups apart |
| arrow | `SYM_ARROW` | `→` | before the projected % |
| reset | `SYM_RESET` | `↻` | before the time until reset |
| sep | `SYM_SEP` | `·` | between segments |
| warn | `SYM_WARN` | `⚠` | projected to hit 100% before reset, and before alerts |
| full | `SYM_FULL` | `⛔` | limit reached |
| wait | `SYM_WAIT` | `…` | not enough data for a forecast yet |

Convert "Other" answers the same way. "Mon, Wed, Fri" becomes
`WORK_DAYS="1 3 5"`, "7am-3pm" becomes `DAY_START=7 DAY_END=15`, and
"arrow >> sep /" becomes `SYM_ARROW=">>" SYM_SEP="/"`. Accept the setting
names and plain words too ("separator", "warning"). Notes added to an option
that name a value count the same way. For a custom prefix, add a trailing
space unless the user asked for none, so the prefix does not run into `5h`.
If an answer is unclear, ask about that one setting in a plain chat message.
Do not guess.

### Save

Save only the settings that differ from their current values, in one call:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" --set "WORK_DAYS=1 2 3 4 5" DAY_START=9 DAY_END=18 "SYM_ARROW=->" "SYM_PREFIX=[work] "
```

Each sign value is 1 to 16 bytes (a Unicode symbol takes 2 to 4).
`SYM_PREFIX` can be any length, or empty to remove it. None may contain `"`,
`\`, `$`, backtick or control characters. If the call exits with code 1, show
the user the error and ask about that setting again. Afterwards, tell the
user the status line picks up the change on its next refresh (about 10
seconds).

Hours outside the working hours and days outside the working days count as
`NIGHT_WEIGHT` and `OFF_DAY_WEIGHT` of a working hour (default 0.1) in the
weekly forecast. The user can change both in the config file.

## After install

After a successful install and the settings menu, tell the user:

- The status line appears within about 10 seconds.
- Limit numbers (`5h`, `7d`, `Ses`, `Cmd`) appear only for Claude Pro/Max
  subscriptions. Until the first response the line may show
  `Usage runway: starting...`. API-key accounts always see that and context usage.
- Settings such as the auto-stop guard (`GUARD=on`) are in
  `~/.claude/usage-runway/config`.
- To change the working days and hours, or the signs and prefix, later, run
  `/usage-runway:setup` again, or name the change directly, e.g.
  `/usage-runway:setup arrow ->`.
