# Status (as of 2026-08-31, live-tested on X1C)

Everything below was checked against a REAL install on the X1C machine:
`install.sh` was actually run, the bar swapped to `google-calendar.clock`,
real Google accounts (`felipe.paiva@gmail.com`, `fpaiva@tribalscale.com`)
synced real events. Every fix in this session was deployed live (`cp`
into `~/.config/omarchy/plugins/google-calendar.clock/` and
`~/.local/share/omarchy-google-calendar/eds_read.py`, then `omarchy
restart shell`), checked against `journalctl` for QML errors, and
confirmed either by screenshot or by the user directly re-testing on
the real desktop.

## Confirmed working (live-verified)

- Bar swap, sync via GOA/EDS, recurring-event date handling,
  `--select-calendars` narrowing, month-grid day selection, rich-text
  event descriptions, Join meeting button, force-refresh — all from
  earlier sessions, unchanged.
- **Calendar picker Save button**: unchecking a calendar and clicking
  Save correctly drops it from the agenda. Takes ~20s (the normal sync
  round-trip) — a **"Syncing…" indicator** on the agenda screen now
  makes that wait visible instead of looking broken.
- **Timezone bug**: a 9am America/Toronto event was showing at 9am/13:00
  local (Dubai) instead of the correct 5pm/17:00. `ICalGLib.Time.as_timet()`
  silently ignores the timezone `get_timezone()` reports and reads the
  wall-clock numbers as UTC — fixed by calling
  `t.convert_to_zone(ICalGLib.Timezone.get_utc_timezone())` first in
  `eds_read.py`'s `ical_time_to_iso()`.
- **Next-event marker**: the agenda row matching `Model.nextUpcomingEvent`
  (same computation the bar badge uses) shows a "now" / "in Nm" badge.
  Compared by `.id`, not object identity — a `property var` holding
  parsed JSON does not reliably return the same object across two
  separate reads of `eventsCache.events`.
- **Birthdays collapse into one expandable row** ("🎂 N birthdays ⌄")
  instead of one row per birthday. `Model.isBirthdayEvent` detects them
  by `allDay && title` matching `"X's birthday"` — Google's own birthday
  calendar carries no dedicated type field.
- **Event detail now surfaces everything the calendar data actually
  carries** (audited every ICalGLib property present across real synced
  events first, only added fields with real, varying values — see
  `sync/eds_read.py`'s `extract_*` functions): which calendar it's on
  (name + color dot), organizer, human-readable recurrence ("Every
  weekday", "Weekly on Tuesday, Thursday"), Busy/Free (from `TRANSP`),
  a Cancelled/Tentative banner (from `STATUS` — silent when CONFIRMED,
  since that's true of every event and carries no signal), and the
  reminder offset (from the event's `VALARM`).
- **Location is always tappable** — a bare `http(s)://` link opens
  as-is; a plain street address becomes a Google Maps search URL, same
  as Google Calendar's own app treats either.
- **Opening any external link (Join meeting, location, a description
  link) now closes the whole calendar popup** — `EventDetail.qml` emits
  `externalOpened()` before shelling out, `Panel.qml` connects it to
  `root.close()`.

## Gotchas hit this session (useful if this bites again)

- **`Qt.openUrlExternally` is unusable in this Quickshell context** — it
  goes through Qt's own portal-based desktop-services path, which
  conflicts with the `qt.qpa.services` portal registration warning that
  shows up in `journalctl` on every shell start here. It caused the whole
  panel to glitch (shrink, agenda go blank) on tap with **zero QML error
  logged** — nothing pointed at it directly; it was found by noticing
  `Qt.openUrlExternally` doesn't appear anywhere else in the Omarchy
  shell, which uses `Quickshell.execDetached` / `Util.execArgv`
  everywhere instead. Use `Util.execArgv(["xdg-open", url])` for any new
  external-open call — never `Qt.openUrlExternally`.
- **A `\U000fXXXX` nerd-font glyph escape silently breaks if it picks up
  an extra backslash** (`"\\U000f0026"` instead of `"\U000f0026"`) — the
  file then contains a literal backslash + literal digits, which renders
  as visible text like "U000f0026" instead of an icon, with no QML error
  either. Neither the Read tool's display nor a plain editor can tell the
  difference by eye — verify with `python3 -c "print(repr(open(path).read()))"`
  and check the codepoint's presence in the actual font
  (`fontTools.ttLib.TTFont(...).getBestCmap()`) before trusting a glyph
  renders. A `\uXXXX` (4-digit) escape also truncates silently for any
  codepoint above `U+FFFF` (all the nerd-font icons used here are in the
  `U+F0000+` range) — always use the 6-digit `\U000fXXXX` form for these.
- **Quickshell's plugin file-watcher doesn't always fully pick up a QML
  change** — a clean "Local plugin changed, reloading" log line does not
  guarantee the change is actually live. `omarchy restart shell` (a full
  process restart, visible as a new "Launching config" log line) is the
  reliable way to deploy.
- `qs -p /usr/share/omarchy/shell/shell.qml ipc call google-calendar.clock open`
  opens the panel non-interactively for screenshotting
  (`grim -o <monitor>`); there's no equivalent IPC for clicking inside
  it, so anything past "open the panel" needs the user to actually
  click and report back or screenshot.

## What to check first in the next session

Nothing outstanding.
