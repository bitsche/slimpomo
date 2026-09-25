# SlimPomo

A menu-bar Pomodoro timer for one person on one Mac. The queue and history stay on this machine. There is no account, sync, or settings window.

No projects, tags, estimates, or due dates. A task can be snoozed to tomorrow or next Monday; there is no date picker.

Done is today's finished work. Past days live in History (read-only, local, kept indefinitely).

## Queue

Unfinished tasks stay in the queue across days until they are finished, deleted, or snoozed. From a task's ••• menu, move it to tomorrow or next Monday. It leaves the queue and waits in LATER, then returns to the top of the queue at the start of that day.

## Menu bar

Left-click the icon to open the menu: the current status, Show Window, Start, Pause, or Resume, and Quit. Right-click, or Control-click, opens the window.

## Dev build

`scripts/dev.sh` builds and launches SlimPomo Dev.app. It keeps its own queue, Done list, and history, and it never reads or writes the release app's data.

```
scripts/dev.sh                  build and launch
scripts/dev.sh --seed           fill History with a fixed sample, and match today's Done
scripts/dev.sh --seed-large     the same sample, plus about three years of history
scripts/dev.sh --clear-history  empty history; leave the queue and Done
scripts/dev.sh --stale-done     leave yesterday's Done list so launch clears it
scripts/dev.sh --reset          wipe the dev store and its remembered settings
scripts/dev.sh --tour           show the first-run tour again
scripts/dev.sh --later          add later tasks: tomorrow, next Monday, and two already due
```
