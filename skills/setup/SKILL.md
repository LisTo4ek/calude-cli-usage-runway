---
name: setup
description: Enable, check or remove the usage-runway status line in the user's Claude Code settings, and set the working days and hours used by the weekly forecast. Use when the user runs /usage-runway:setup, asks to turn the usage-runway status line on or off, to check its status, to change their usage-runway working days or hours, or to change the symbols, prefix, background or colors it shows.
argument-hint: "[status | uninstall | Mon to Fri | 9 to 18 | arrow -> | sep / | prefix [work] | bg 236 | plain ASCII]"
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
| change working days / hours, symbols (arrow, separator, …), prefix, background or colors (green, red, …) | the settings menu below |

If `${CLAUDE_PLUGIN_ROOT}` is not expanded in the command, use
`"$(cat ~/.claude/usage-runway/plugin-root)/scripts/setup.sh"` instead.

If the install exits with code 3, another status line is configured. Show the
user the existing command from the output and ask whether to replace it. Only
if they agree, re-run with `--force`.

## Settings menu

Run this after a successful install, and when the user asks to change their
working days, hours, signs (symbols), prefix, background or colors. The main
menu is one AskUserQuestion call with four single-select questions, followed
by one call with the Background and Colors questions. Only if the user picks
"Pick each sign" do you ask the sign menus, and only if they pick "Pick each
color" do you ask the color menus.

If the user already said what they want (for example "arrow ->" or "Mon to
Fri, 9 to 18"), skip the menu and save just that.

If the user names a setting without a value (for example "prefix" or
"arrow"), skip the main menu and ask only that setting's question in one
AskUserQuestion call. For work days, work hours and the prefix, use its
question from the main menu; for the background or the colors, the
Background or Colors question. For a sign, use its question from the sign
menus; for a single color (for example "red"), its question from the color
menus.
Mark the current value the same way as below.

First run `setup.sh --status` and read the `schedule:`, `symbols:`,
`separator:`, `background:` and `colors:` lines.
Add " (current)" to the option that matches each current value. If the
current value matches no option, replace the third option with
"Keep current: <value>".

### Previews

Give every option of every menu question a `preview`, so the user sees the
result before choosing. Build the status line previews with the setup script,
which prints a sample line in plain text with the current config plus the
given settings. It saves nothing. Render all previews of one menu in a single
Bash call, one `--preview` per option:

```
S="${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"
bash "$S" --preview "SYM_ARROW=->" "SYM_RESET=@"; bash "$S" --preview "SEP= | "
```

`--preview` with no settings shows the current line ("Keep current", "(current)"
options). For "Pick each sign" and "Pick each color", the preview is the
current line followed by the list of signs or colors the menu asks about.

- **Signs, separator, prefix, background:** the `--preview` line with that
  option's settings. A background shows only as the padding around segments.
  `SYM_WARN`, `SYM_FULL` and `SYM_WAIT` do not appear on the sample line; write
  the `5h` segment in that state yourself, e.g. `5h 90.0% → 120.0% ⚠ 00:40 ↻
  02:00 (16:42)`, `5h 100% ⛔ ↻ 02:00 (16:42)` or `5h 2.0% → … ↻ 04:50 (19:32)`.
- **Colors:** previews are plain text and cannot show color. Show the
  current line, then one line per color the option sets, naming the part it
  colors and its hex value, e.g. `red   #d75f5f  runs out before reset, Cmd
  at CMD_CRIT`. Indexes 0-15 depend on the terminal theme: write `terminal
  red` and so on instead of a hex code.
- **Work days and hours:** a week table with one row per day, marking the
  working hours, e.g. `Mon  08-22 work, other hours count 0.1`, `Sat  off day,
  counts 0.1`.

With previews the menu shows options side by side and the "Other" field may
not be visible. Keep the "Pick Other to type your own" hint in the questions.
If the user picks Other without a value, or says they want their own value,
ask for it in a plain chat message, then show its `--preview` line before
saving.

| Header | Question | Options |
|---|---|---|
| Work days | "Which days do you usually work? Pick Other to type your own, e.g. Mon, Wed, Fri." | "Every day (Recommended)", "Monday to Friday", "Monday to Saturday" |
| Work hours | "Which hours do you usually work? Pick Other to type your own, e.g. 7-15." | "All day (Recommended)", "08:00 to 22:00", "09:00 to 18:00" |
| Signs | "Which status line signs? Pick Other to set single signs, e.g. arrow -> reset @ sep \| (names: arrow, reset, sep, warn, full, wait, ses sep)." | "Keep current (Recommended)", "Pick each sign", "Unicode defaults", "Plain ASCII" |
| Prefix | "What text should come before the status line? Pick Other to type your own." | "None (Recommended)", "[work]", "[home]" |

Right after the main menu, ask the Background and Colors questions together
in one AskUserQuestion call (both single-select, with previews):

| Header | Question | Options |
|---|---|---|
| Background | "Which background for the status line segments? Each segment becomes a pill; separators keep the terminal background. Pick Other to type a 256-color index 0-255, R;G;B or #rrggbb." | "None (Recommended)", "Dark grey (236)", "Slate (40;44;52)" |
| Colors | "Which colors? Pick Other to set single colors, e.g. red d75f5f green #5faf5f (names: text, prefix, labels, muted, separator, faint, green, yellow, red)." | "Keep current (Recommended)", "Interactive picker", "Pick each color", "Defaults" |

Give each option a short `description`. For "Keep current", list the current
signs or colors. For "Pick each sign" and "Pick each color", say it opens a
menu with one question per sign or color. For "Defaults", list the default
hex colors. For
"Interactive picker", say it opens in a terminal with arrow keys and a live
preview in the real colors and background.

### Interactive picker

If the user picks "Interactive picker" or asks to choose colors
interactively, do not run it yourself: it needs a terminal, and Bash commands
here have none. Tell the user to run it in a terminal window (not with `!`):

```
bash "$(cat ~/.claude/usage-runway/plugin-root)/scripts/colors.sh"
```

It shows three sample lines (on track, warning, runs out) rendered by the
status line with the real colors and background, the list of color
settings and the 256-color palette. Keys: ↑/↓ choose a setting, ←/→ step
through the 256 colors, `[` `]` jump a palette row, `{` `}` step by 6, `t`
type a value, `e` empty (main color; for COLOR_TEXT the terminal default), `d` dim, `u` undo, Enter saves, `q` quits
without saving. Saved colors reach the status line on its next refresh.
For the other sign sets and the prefixes, show an example line such as
`5h 20.0% → 33.3% ↻ 02:00 (16:42) · 7d 30.0%`.

### Sign menus

Ask these only if the user picked "Pick each sign". AskUserQuestion takes at
most four questions per call, so ask menu A as one call with four questions,
then menu B as one call with three. All are single-select, and like the main
menu each option has a preview. Mark the option that matches the current value
with " (current)"; if the current value matches no option, replace the third
option with "Keep current: <value>". Give each option a `description` with an
example line using that sign, such as `5h 20.0% -> 33.3% ↻ 02:00 (16:42) · 7d
30.0%`.

Give each sign question exactly three options. AskUserQuestion adds "Other"
as the fourth option. Do not add a "Type my own" option. Use the typed text as
the value; if Other comes without one, ask for it as described under Previews.

| Menu | Header | Question | Options (setting value) |
|---|---|---|---|
| A | Arrow | "Which sign should point to the projected usage? Pick Other to type your own." | "→" (default), "->", "»" |
| A | Reset | "Which sign should mark the time until reset? Pick Other to type your own." | "↻" (default), "⟳", "@" |
| A | Separator | "What should separate the segments? Pick Other to type your own, spaces included, e.g. \" \| \"." | "·" (default), "\|", "Spaces only" (`SEP="   "`) |
| A | Warning | "Which sign should warn that a limit runs out before reset? Pick Other to type your own." | "⚠" (default), "!", "‼" |
| B | Limit hit | "Which sign should show a limit is reached? Pick Other to type your own." | "⛔" (default), "✖", "FULL" |
| B | Waiting | "Which sign should show there is no forecast yet? Pick Other to type your own." | "…" (default), "...", "?" |
| B | Ses sep | "What should separate the 5-hour windows in Ses? It is shown in COLOR_MUTED. Pick Other to type your own, spaces included." | "\" \| \"" (default), "\" / \"", "\" · \"" |

The option label is the setting value, so "->" in Arrow becomes
`SYM_ARROW="->"`, and "\" / \"" in Ses sep becomes `SES_SEP=" / "` (the quotes
show the spaces; save the text between them). Preview the Ses sep options
with a sample such as `Ses 38.0% / 60.0% / 4.0%`; `--preview` shows only one
window. Mark no option "(Recommended)"; label the default option
"→ (default)" and so on, and drop " (default)" from the saved value.

### Color menus

Ask these only if the user picked "Pick each color": menu C as one call with
four questions, then menu D as one call with four. They follow the rules of
the sign menus: single-select, previews, exactly three options, " (current)"
on the option that matches the current value, "Keep current: <value>" in place
of the third option when none matches, and Other for a typed value. The
option label is the hex value to save, e.g. "#d75f5f" becomes
`COLOR_RED="#d75f5f"`. Describe each option by where the color shows.

| Menu | Header | Question | Options (setting value) |
|---|---|---|---|
| C | Green | "Which color for a limit that is on track? Pick Other to type #rrggbb, rrggbb or a 256-color index." | "#5faf5f (default)", "#87af87", "#00d75f" |
| C | Yellow | "Which color for a warning (projected above WARN_PCT, Cmd at CMD_WARN)? Pick Other to type your own." | "#d7af5f (default)", "#ffaf00", "#d7d75f" |
| C | Red | "Which color for a limit that runs out before reset, and Cmd at CMD_CRIT? Pick Other to type your own." | "#d75f5f (default)", "#af5f5f", "#ff5f5f" |
| C | Muted | "Which color for the arrow, reset sign and the separator inside Ses? Pick Other to type your own." | "#808080 (default)", "#585858", "#a8a8a8" |
| D | Labels | "Which color for the segment names (5h, 7d, Ctx, Ses, Cmd)? Pick Other to type your own." | "#5f87d7 (default)", "#87afd7", "#5fafaf" |
| D | Separator | "Which color for the separator between segments? Pick Other to type your own." | "#6c6c6c (default)", "#444444", "#a8a8a8" |
| D | Faint | "Which color for the time until reset? Pick Other to type your own." | "#8a8a8a (default)", "#6c6c6c", "dim" |
| D | Text | "Which main color for every panel (also Ctx %, Ses %, Cmd %)? Pick Other to type your own." | "Terminal default (default)", "#d0d0d0", "#ffffff" |

The prefix color (`COLOR_PREFIX`) has no menu question; set it from an Other
answer or the interactive picker. "Terminal default" saves an empty value.
Any other color left empty shows in the Text color.
`setup.sh --set` saves every color as `#rrggbb`, except indexes 0-15 (the
terminal's own palette, which follows its theme), `dim` and empty.

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
| None (background) | `BG=""` |
| Dark grey (236) / Slate (40;44;52) | `BG="236"` / `BG="40;44;52"` |
| Keep current (colors) | nothing |
| Pick each color | the answers from the color menus |
| Interactive picker | nothing; tell the user how to run it (see Interactive picker) |
| Defaults | `COLOR_TEXT="" COLOR_PREFIX="" COLOR_LABEL="#5f87d7" COLOR_MUTED="#808080" COLOR_SEP="#6c6c6c" COLOR_FAINT="#8a8a8a" COLOR_GREEN="#5faf5f" COLOR_YELLOW="#d7af5f" COLOR_RED="#d75f5f"` |
| Terminal palette (Other: "terminal colors") | `COLOR_LABEL="4" COLOR_MUTED="8" COLOR_SEP="8" COLOR_FAINT="dim" COLOR_GREEN="2" COLOR_YELLOW="3" COLOR_RED="1"` (follow the terminal theme) |

| Sign name | Setting | Default | Shown |
|---|---|---|---|
| (prefix) | `SYM_PREFIX` | empty | before the whole status line, e.g. to tell setups apart |
| arrow | `SYM_ARROW` | `→` | before the projected % |
| reset | `SYM_RESET` | `↻` | before the time until reset |
| sep | `SYM_SEP` | `·` | between segments, with a space on each side |
| (separator) | `SEP` | unset | the whole text between segments, spaces included; replaces ` SYM_SEP ` |
| (Ses separator) | `SES_SEP` | ` \| ` | between the 5-hour windows in `Ses`, spaces included, in `COLOR_MUTED` |
| warn | `SYM_WARN` | `⚠` | projected to hit 100% before reset, and before alerts |
| full | `SYM_FULL` | `⛔` | limit reached |
| wait | `SYM_WAIT` | `…` | not enough data for a forecast yet |

A separator answer that is only spaces, or that asks for different spacing
around the sign (for example "no spaces around |"), goes to `SEP` with exactly
the text between segments. Any other separator answer goes to `SYM_SEP`, and
then save `SEP` as well only if it is currently set (see the `separator:` line
of `--status`), since `SEP` takes precedence: `SEP=" <sign> "`.

Convert "Other" answers the same way. "Mon, Wed, Fri" becomes
`WORK_DAYS="1 3 5"`, "7am-3pm" becomes `DAY_START=7 DAY_END=15`, ,
"arrow >> sep /" becomes `SYM_ARROW=">>" SYM_SEP="/"`, "Ses separator /"
or "sessions separator /" becomes `SES_SEP=" / "` (add a space on each side
unless the user gives the spacing), "only spaces between
the segments" becomes `SEP="   "`, and "bg 40,44,52" or
"background 40 44 52" becomes `BG="40;44;52"`, and "red #b44141" becomes
`COLOR_RED="#b44141"` (the names text, prefix, labels, muted, separator,
faint, green, yellow and red map to `COLOR_TEXT`, `COLOR_PREFIX`,
`COLOR_LABEL`, `COLOR_MUTED`, `COLOR_SEP`, `COLOR_FAINT`, `COLOR_GREEN`,
`COLOR_YELLOW` and `COLOR_RED`; `COLOR_TEXT` is the main color of every
panel, any other color left empty shows in it, `COLOR_TEXT` empty is the
terminal's default text color, and hex works with or without `#`). Accept the setting
names and plain words too ("separator", "warning", and "colour" for color). Notes added to an option
that name a value count the same way. For a custom prefix, add a trailing
space unless the user asked for none, so the prefix does not run into `5h`.
If an answer is unclear, ask about that one setting in a plain chat message.
Do not guess.

### Save

Save only the settings that differ from their current values, in one call:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" --set "WORK_DAYS=1 2 3 4 5" DAY_START=9 DAY_END=18 "SYM_ARROW=->" "SYM_PREFIX=[work] " "BG=236"
```

Each sign value is 1 to 16 bytes (a Unicode symbol takes 2 to 4). `SEP` and
`SES_SEP` are 0 to 32 bytes, spaces included.
`SYM_PREFIX` can be any length, or empty to remove it. None may contain `"`,
`\`, `$`, backtick or control characters. If the call exits with code 1, show
the user the error and ask about that setting again. `BG` and the `COLOR_*`
settings are empty, a color index 0-255, `R;G;B` with each part 0-255, or
`#rrggbb` (the `#` is optional); `COLOR_*` may also be `dim`. Afterwards, tell the
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
- To change the working days and hours, or the signs, prefix, background and colors, later, run
  `/usage-runway:setup` again, or name the change directly, e.g.
  `/usage-runway:setup arrow ->`.
