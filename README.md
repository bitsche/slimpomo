# Deeeep

A menu-bar Pomodoro timer for one person on one Mac. The queue and history stay on this machine. There is no account, sync, or settings window. Default size 550×600, minimum 450×550.

If an older SlimPomo.app is still installed, delete it so two menu-bar icons don't run side by side. If that app was in Login Items, add Deeeep there instead.

If Finder still shows the old icon, run `touch Deeeep.app` or `killall Finder`.

No projects, tags, estimates, or due dates. A task can be snoozed to tomorrow or next Monday; there is no date picker.

Done is today's finished work. Past days live in History (read-only, local, kept indefinitely). Click the DONE or LATER header to collapse it; Deeeep remembers each. Rows with the same name and mode merge into one with a summed count and time.

A name like `Acme: write the report` shows `Acme` as a muted prefix. Click a queue or LATER name to edit it; long names wrap to up to four lines while editing. Return saves, Esc cancels.

Each task has a pomodoro count of 0 to 5 (at least 1 while it runs). Hover a row to show − and + in a fixed slot at the right; at rest only `×2` and above is shown. Done and History show the count in the same place.

## Queue

Unfinished tasks stay in the queue across days until they are finished, deleted, or snoozed. From a task's ••• menu, move it to tomorrow or next Monday. It leaves the queue and waits in LATER, then returns to the top of the queue at the start of that day.

## Planning in LATER

Queue and LATER are one drag area. Press a row anywhere and move the pointer 4 pt to lift it, with no hold delay. The gauge, the − and + stepper, and ••• are controls and never start a drag; a click without movement keeps its normal action (a click on the name edits it). Drag it:

- within the queue to reorder it,
- into a day of LATER (Tomorrow or next Monday) to plan it there, at the spot where you drop it,
- between days of LATER to change the day it returns, or within a day to set the order,
- from LATER up into the queue to work on it now, at the spot where you drop it.

While a row is held, LATER opens and shows both days, with a dashed drop zone for an empty day. Holding a row over a collapsed LATER header for 0.6 s opens it for good. Esc, or releasing outside the list, puts the row back. A task that is running can't be dragged and nothing can be dropped above it. Done rows are not drop targets.

At midnight of a day, that day's tasks return to the top of the queue (below a running task) in the order planned in LATER. A task moved with ••• goes to the end of its day. In LATER you can also edit names, click the gauge to change the mode, and set the count; rows rest at 60% and come to full strength on hover.

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
scripts/dev.sh --export-gauges DIR            write the depth gauges (Dip, Dive, Deep dive, muted) at 1x and 2x
```
