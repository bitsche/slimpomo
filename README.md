# Deeeep

A menu-bar Pomodoro timer for one person on one Mac. The queue and history stay on this machine. There is no account, sync, or settings window. Default size 550×600, minimum 450×550.

If an older SlimPomo.app is still installed, delete it so two menu-bar icons don't run side by side. If that app was in Login Items, add Deeeep there instead.

If Finder still shows the old icon, run `touch Deeeep.app` or `killall Finder`.

No project lists, estimates, or due dates. A task can be snoozed to tomorrow or next Monday; there is no date picker. History shows worked time per day and per project prefix. No charts or long-term statistics.

Done is today's finished work. Past days live in History (read-only, local, kept indefinitely). Click the DONE or LATER header to collapse it; Deeeep remembers each. Rows with the same name and mode merge into one with a summed count and time.

Click a queue or LATER name to edit it; long names wrap to up to four lines while editing. Return saves, Esc cancels.

## Tags

A name like `Acme: write the report` starts with a project prefix (1 to 12 characters, no spaces, then a colon and a space). Deeeep shows it as a tag. Tags are plain text, not controls, and the name is stored as typed, and nothing else is added to the task.

- **Identity and look:** `Acme`, `ACME`, and `acme` are one tag, always shown in uppercase, 11 pt regular with slight letter spacing, in the tag's color (60% in Done and History). The menu-bar menu and the edit field show plain text.
- **Colors:** six warm colors (Coral, Amber, Rose, Lilac, Peach, Sage grey), kept apart from the mode colors and the break sand. A tag seen for the first time gets the first color no known tag uses; with all six taken, the color assigned longest ago. A tag keeps its color across days and relaunches. Colors are automatic; there is no way to change one.
- **Column:** each list decides on its own: the queue, LATER, Done, and the History window (one list across all days). If a list has at least one tagged row, every row in it, untagged ones included, gets a tag column between gauge and name, as wide as that list's widest tag plus 8 pt (28 to 60 pt; a longer tag ends in "…"), so its names line up. A list without tags has no column and no empty space. The column appears and disappears live, with a 150 ms slide (none with Reduce Motion). A row held in a drag uses the layout of the list it is over.
- **History:** under each day header, worked time per tag, biggest first, untagged work as Other, at most four entries and then `+N more`.

Each task has a pomodoro count of 0 to 5 (at least 1 while it runs). Hover a row to show − and + in a fixed slot at the right; at rest only `×2` and above is shown. Done and History show the count in the same place.

## Queue

Unfinished tasks stay in the queue across days until they are finished, deleted, or snoozed. From a task's ••• menu, move it to tomorrow or next Monday. It leaves the queue and waits in LATER, then returns to the end of the queue at the start of that day.

While work is running or paused, the current task sits in its own **NOW** section above TODO: a NOW header, the task as a row (name 14 pt semibold, gauge at 50% with the drifting wave, the full-strength bar at its left edge), and a divider before the TODO header. It has the same hover controls as any row (finish time, •••, − and +, with the count from 1 to 5), a click on the name renames it, and right-click opens the row menu with the snooze items disabled. It can't be dragged and nothing can be dropped into NOW. On START the task moves up from TODO into NOW; when a break starts it returns to the top of TODO (if pomodoros remain) and NOW collapses, 200 ms (instant with Reduce Motion). The TODO list never contains the current task, yet it stays first in the queue, and the TODO header's totals and "done by" still count its remaining time.

While the timer is idle or in a break there is no NOW section, and the task that START (or the end of the break) will begin next has the same thin bar at its left edge in its mode color at 40%. It moves at once when the order, counts, or snoozes change.

**Paused is grey and still.** Pausing work or a break turns the tank and the NOW row grey in 400 ms (instant with Reduce Motion): air, water, back wave, crest, digits, pause glyph, text line and scale in one grey family (a dusty sand-grey for a paused break), and in the NOW row the bar, the gauge ring, crest and water, and the name; the tag keeps its color at 60%. The waves freeze and the water level stays put. The Resume pill keeps its mode color, and there is no chip, badge or "Paused" text.

Dates are always English, whatever the system region: `Mon 5 Oct` in LATER and `TUE 22 SEP` in History (with the year when it is not this one).

## Planning in LATER

Every row in TODO and LATER can be dragged anywhere, and TODO and LATER are one drag area. Press a row anywhere and move the pointer 4 pt to lift it, with no hold delay. The gauge, tag, name, and empty space all start a drag; only the − and + stepper and ••• never do. A click without movement keeps its normal action (a gauge click changes the mode on mouse up, a click on the name edits it). Drag it:

- within the queue to reorder it,
- into a day of LATER (Tomorrow or next Monday) to plan it there, at the spot where you drop it,
- between days of LATER to change the day it returns, or within a day to set the order,
- from LATER up into the queue to work on it now, at the spot where you drop it.

While a row is held, LATER opens and shows both days, with a dashed drop zone for an empty day. Holding a row over a collapsed LATER header for 0.6 s opens it for good. The pointer's y alone picks the place: the upper half of a row means before it, the lower half after it, a day label or the LATER header the start of that day, an empty day's drop zone that day, and anything below the last row (Done included) the end of the last day. Esc, or releasing off to the side or outside the list area, puts the row back. The task under NOW can't be dragged and nothing can be dropped into NOW; every TODO row can go anywhere, the top included (it then runs after the current task), and a release between the divider and the list drops at the top of TODO. Done rows are not drop targets.

At the start of a day (midnight, launch, or wake), that day's tasks are appended to the end of the queue in the order planned in LATER; several days catching up at once go earlier day first. "Back to queue" in the ••• menu also appends to the end, while a drag from LATER lands exactly where you drop it. A task moved with ••• goes to the end of its day. In LATER you can also edit names, click the gauge to change the mode, and set the count; rows rest at 60% and come to full strength on hover.

## Modes

A small round gauge shows the depth as a tank: a ring, a dark inside, and a wave of water. The level rises from Dip (30%) to Dive (55%) to Deep dive (70%). The wave of the running task drifts slowly; every other gauge is still, and none move with Reduce Motion.

## Menu bar

The icon is a monochrome template so macOS tints it for light and dark menu bars. Idle is an empty tank with a still wave. While you work, the water rises with the time elapsed, and the minutes left sit beside it. Paused work keeps that water at 40% and adds two pause bars. During a break there is no tank: the sun rises out of the sea, from a small cap at the start to a full disc just above the horizon at the end. A paused break keeps the sun where it is, dimmed to 40%, with the sea line and the pause bars. The icon does not animate, and its width stays the same in every state.

Left-click the icon to open the menu: the current status, Show Window, Start, Pause, or Resume, and Quit. Right-click, or Control-click, opens the window.

## Sound

Two soft chords: work done slowly brightens (surfacing), break over slowly darkens (diving back in).

## Dev build

UI changes follow `.cursor/rules/ui-basics.mdc`.

`scripts/dev.sh` builds and launches Deeeep Dev.app. It keeps its own queue, Done list, and history, and it never reads or writes the release app's data.

```
scripts/dev.sh                  build and launch
scripts/dev.sh --seed           fill History with a fixed sample, and match today's Done
scripts/dev.sh --seed-large     the same sample, plus about three years of history
scripts/dev.sh --clear-history  empty history; leave the queue and Done
scripts/dev.sh --stale-done     leave yesterday's Done list so launch clears it
scripts/dev.sh --reset          wipe the dev store and its remembered settings
scripts/dev.sh --tour           show the first-run tour again
scripts/dev.sh --later          add later tasks: tomorrow, next Monday, and two already due
scripts/dev.sh --tank-level 0.5 [work|break]  freeze the tank at a level (0 to 1), waves still, to check the scale
scripts/dev.sh --debug-drop-zones  with any of the above: while a row is held, draw the bands the pointer maps through, to check there are no gaps
scripts/dev.sh --export-gauges DIR            write the depth gauges (Dip, Dive, Deep dive, muted) at 1x and 2x
```
