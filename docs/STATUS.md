# Status (as of 2026-08-31, live-tested on X1C)

This file exists because a session ran out of road mid-debug. Most of what it
tracked is now resolved — kept as a record until the repo is fully stable.

## How this was tested

Everything below was checked against a REAL install on the X1C machine:
`install.sh` was actually run, the bar actually swapped to
`google-calendar.clock`, real Google accounts (`felipe.paiva@gmail.com`,
`fpaiva@tribalscale.com`) synced real events. Every fix in this session
was deployed live (`cp` into `~/.config/omarchy/plugins/google-calendar.clock/`
and `~/.local/share/omarchy-google-calendar/eds_read.py`, then
`omarchy restart shell`) and checked against `journalctl` for QML errors
before asking for a visual check.

## Confirmed working (live-verified)

- Bar swap: stock `omarchy.clock` disabled, `google-calendar.clock`
  enabled, `bar.centerAnchor` in `shell.json` updated to match.
- Sync: `sync/eds_read.py` reads real events from both linked Google
  accounts via GNOME Online Accounts + Evolution Data Server, no OAuth
  code of our own. Recurring events (birthdays, daily standups) show the
  current occurrence, not the original date (`generate_instances_sync`).
- Calendar count problem: `--select-calendars` / `--list-options` /
  `--print-selected` / `--set-selected` let the user narrow 50+ calendars
  per account down to a chosen few (~20s sync for 2 calendars vs. minutes
  for 50+).
- Month grid: click a day, agenda shows just that day.
- Event detail: description HTML renders via `Text.RichText`.
- Join meeting button: labeled "Join meeting", not icon-only.
- Force-refresh: real sync completes in ~20s for 2 calendars.
- **Calendar picker (gear icon) Save button**: unchecking a calendar and
  clicking Save now correctly drops that calendar's events from the
  agenda. Confirmed live: the `saveProcess.running = false` reset before
  `= true` in `CalendarSettings.qml`'s `save()` (mirroring
  `qs.Ui/MultiSelect.qml`'s own `refresh()` pattern) was the correct fix.
  Live-tested by watching `~/.config/omarchy-google-calendar/calendars.json`
  and the resulting `events.json` calendar breakdown change after a real
  uncheck + Save.

## Known UX gap (not a correctness bug)

After Save, the settings screen closes immediately and the actual sync
(`forceRefresh()` → `omarchy-google-calendar-sync.service`) takes its
normal ~20s to complete in the background. There is no visible "syncing"
indicator on the agenda screen during that window — the only spinner
lives on the settings screen's own Save button, which is already gone by
then. This caused a real user to think Save was broken and reopen/close
settings repeatedly, when it just needed to wait ~20s. Worth a follow-up:
surface `root.refreshingCalendar` as a small visible indicator on the
agenda screen itself, not just as a disabled state on the refresh button.

## What to check first in the next session

Nothing outstanding on the calendar picker. If a Save still looks broken,
wait the full ~20s before concluding otherwise — see the UX gap above.
