# omarchy-gcal

A drop-in replacement for [Omarchy](https://omarchy.org/)'s stock top-bar
clock widget — same clock, same month-grid popup, same life-expectancy
easter egg, plus a Google Calendar agenda: upcoming events, full event
details (description, location, attendees, a one-click Join button for
Meet/Zoom/Teams links), and a force-refresh button that syncs every linked
account at once.

## How it gets your events (no password, no new Google app access)

Google Calendar API access normally means either registering your own
OAuth app in Google Cloud Console, or trusting a shared client someone
else registered. This widget does neither. It reads through **GNOME
Online Accounts** (GOA) and **Evolution Data Server** (EDS) — the exact
same stack GNOME Calendar itself uses. If GNOME Calendar already shows
your events on this machine, this widget reads that same data; nothing
new is asked of Google, and no credentials of any kind pass through this
repo's code.

Built and verified against a real 2-account setup with 50+ calendars
between them — see `docs/` for the details that came out of that (the
recurring-event date bug, the calendar-count problem, and how each was
fixed).

## Quickstart

```bash
git clone https://github.com/felipecpaiva/omarchy-gcal.git
cd omarchy-gcal
./install.sh
```

`install.sh` will:
1. install the 4 prerequisite packages if you don't already have them ([docs/prerequisites.md](docs/prerequisites.md))
2. check for a linked Google account, and open Settings → Online Accounts if you don't have one yet ([docs/link-google-account.md](docs/link-google-account.md))
3. let you pick which calendars show on the bar (most accounts have dozens; you probably want 4 or 5)
4. install the plugin and a background sync timer (every 5 minutes)
5. swap the bar over from the stock clock to this one

Re-run `install.sh` any time — it's idempotent.

## Changing which calendars are shown

```bash
/usr/bin/python3 ~/.local/share/omarchy-google-calendar/eds_read.py --select-calendars
```

## Uninstalling

```bash
./uninstall.sh
```

Restores the stock `omarchy.clock` widget and removes everything this
repo installed.

## How it's built

- `plugin/` — the QML bar widget, forked from Omarchy's own stock clock
  source so every existing behavior (format cycling, month grid, timezone
  picker, life bar) keeps working unchanged; see `plugin/test/` for the
  self-check on the added agenda/date logic.
- `sync/eds_read.py` — reads events from EDS/GOA and writes a JSON cache
  the widget reads; see `sync/test_eds_read.py` for the self-check on its
  non-EDS logic. Run with the system `/usr/bin/python3`, not a pyenv/mise
  shim — see [docs/prerequisites.md](docs/prerequisites.md).
