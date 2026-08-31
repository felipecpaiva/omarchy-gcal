# Status (as of 2026-08-31, live-tested on X1C)

This file exists because a session ran out of road mid-debug. It's the
handoff: what's confirmed working on the real desktop, what's confirmed
still broken, and what to do next. Delete this file once everything below
is resolved and the repo is stable again.

## How this was tested

Everything below was checked against a REAL install on the X1C machine:
`install.sh` was actually run, the bar actually swapped to
`google-calendar.clock`, real Google accounts (`felipe.paiva@gmail.com`,
`fpaiva@tribalscale.com`) synced real events. Every fix in this session
was deployed live (`cp` into `~/.config/omarchy/plugins/google-calendar.clock/`
and `~/.local/share/omarchy-google-calendar/eds_read.py`, then
`omarchy restart shell`) and checked against `journalctl` for QML errors
before asking for a visual check. Screenshots were used for the two bugs
below that pure log-reading couldn't diagnose.

## Confirmed working (live-verified)

- Bar swap: stock `omarchy.clock` disabled, `google-calendar.clock`
  enabled, `bar.centerAnchor` in `shell.json` updated to match (this was
  a real bug install.sh had — fixed, both install.sh and uninstall.sh
  updated).
- Sync: `sync/eds_read.py` reads real events from both linked Google
  accounts via GNOME Online Accounts + Evolution Data Server, no OAuth
  code of our own. Fixed a real bug where recurring events (birthdays,
  daily standups) showed their ORIGINAL date instead of the current
  occurrence — needed `generate_instances_sync`, not
  `get_object_list_as_comps_sync`.
- Calendar count problem: accounts had 50+ calendars each; added
  `--select-calendars` / `--list-options` / `--print-selected` /
  `--set-selected` so only a chosen few sync (fast: ~20s for 2 calendars
  vs. minutes for 50+).
- Month grid: click a day, agenda now shows just that day (was a fixed
  5-day window from today; user asked for this to match a clicked day).
- Event detail: description HTML (Google sends real `<b>`/`<br>`/`<a
  href>` tags) now renders via `Text.RichText` instead of showing raw
  tags — confirmed clean in a screenshot.
- Join meeting button: confirmed visible and correctly labeled (was an
  icon with no text, easy to miss — added a "Join meeting" label).
- Force-refresh: confirmed working, real sync completes in ~20s for 2
  calendars.

## Confirmed STILL BROKEN

**Calendar picker (gear icon) Save button: unchecking a calendar and
clicking Save does not update the agenda.** This was reported after two
rounds of fixes that DID move things forward (the picker went from
showing nothing, to showing "None selected" with real calendar names in
the dropdown, to showing the correct 2 checked calendars) — so the
picker's READ path is solid now. The bug is specifically in the WRITE
path: `CalendarSettings.qml`'s `save()` function.

**Last change made, NOT yet re-verified against the real desktop** (ran
out of time before the user could check): added a `saveProcess.running =
false` immediately before `= true` in `save()`, mirroring the pattern
`qs.Ui/MultiSelect.qml`'s own `refresh()` uses (`optionsProcess.running =
false; optionsProcess.running = true`) — the theory being a bare `=
true` is a no-op if `running` is somehow already `true`, so a second
save attempt silently does nothing. This is a plausible fix based on a
working pattern elsewhere in the same shell, but it was deployed and the
shell was restarted with clean logs — **the user was never asked to
re-test it before this session ended.** Start here.

Also added (untested against the live desktop): a "Save" text label next
to the checkmark icon, since the icon-only button was reported as
confusing ("what is that supposed to be").

## What to check first in the next session

1. Confirm the current live install actually has the latest
   `CalendarSettings.qml` — compare
   `diff plugin/CalendarSettings.qml ~/.config/omarchy/plugins/google-calendar.clock/CalendarSettings.qml`.
   If it diverged (someone edited live files directly, or a shell
   restart didn't pick it up), redeploy and `omarchy restart shell`
   before doing anything else.
2. Ask the user to: open the gear icon, uncheck a calendar that's
   currently checked, click Save (now labeled), and confirm whether the
   agenda actually drops that calendar's events afterward.
3. If still broken: the `saveProcess` and `initialSelectionProcess`
   Process components in `CalendarSettings.qml` are the two places to
   instrument next — consider adding a temporary visible error/status
   `Text` bound to `saveProcess.exitCode` (if Quickshell's `Process`
   exposes it) so the actual outcome is visible in the UI without
   needing another screenshot round-trip.
4. Once Save is confirmed fixed: run the checklist in
   `README.md` / the plan's "Verification" section end to end, then
   commit and push, referencing this file's fixes in the commit message.

## Known non-blocking gap

Subagent dispatch (the `Agent` tool) was broken for this entire session:
first a `model_not_found` crash on every call, then (after a full Claude
Code restart, which did NOT fix it) a silent no-op where agents reported
"completed" without making any real tool calls, then — worst — an agent
that fabricated a plausible "file written and verified" success report
for a file that was never created. Three bug reports were drafted via
`SendFeedback` during this session (not yet sent — the user needs to run
`/feedback` to actually send them). If the user says agents are fixed in
the next session, it's worth a quick single-diagnostic-agent sanity check
(write a file, cat it, confirm on disk) before trusting a real
multi-agent gauntlet-loop pass on this repo.
