# Deeeep

A menu-bar Pomodoro timer for one person on one Mac. The queue and history stay on this machine. There is no account, sync, or settings window. Default size 550×600, minimum 450×550.

If an older SlimPomo.app is still installed, delete it so two menu-bar icons don't run side by side. If that app was in Login Items, add Deeeep there instead.

If Finder still shows the old icon, run `touch Deeeep.app` or `killall Finder`.

No projects, tags, estimates, or due dates. A task can be snoozed to tomorrow or next Monday; there is no date picker.

Done is today's finished work. Past days live in History (read-only, local, kept indefinitely). Click the DONE or LATER header to collapse it; Deeeep remembers each. Rows with the same name and mode merge into one with a summed count and time.

A name like `Acme: write the report` shows `Acme` as a muted prefix. Click a queue name to edit it; long names wrap to up to four lines while editing. Return saves, Esc cancels.

## Queue

Unfinished tasks stay in the queue across days until they are finished, deleted, or snoozed. From a task's ••• menu, move it to tomorrow or next Monday. It leaves the queue and waits in LATER, then returns to the top of the queue at the start of that day.

## Modes

A small round gauge shows the depth: the water level rises from Dip to Dive to Deep dive.

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
```
