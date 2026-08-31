#!/usr/bin/env python3
"""Read Google Calendar events through GNOME Online Accounts + Evolution
Data Server — no OAuth code of our own. See the plan doc's "Data layer"
section for why: GOA already holds an approved Google login for this
machine, EDS already syncs and stores events, this script only queries
what is already there and writes it out as JSON for the QML widget.

Run with the SYSTEM python3 (the one gnome-online-accounts/python-gobject
were installed against), not a pyenv/mise/asdf shim — those usually lack
the `gi` bindings entirely. On Arch that's /usr/bin/python3.
"""
import argparse
import datetime
import json
import os
import re
import sys

import gi

gi.require_version("EDataServer", "1.2")
gi.require_version("ECal", "2.0")
gi.require_version("ICalGLib", "4.0")
from gi.repository import EDataServer, ECal, ICalGLib, GLib  # noqa: E402

CACHE_DIR = os.path.expanduser("~/.cache/omarchy-google-calendar")
CACHE_PATH = os.path.join(CACHE_DIR, "events.json")
CONFIG_DIR = os.path.expanduser("~/.config/omarchy-google-calendar")
CONFIG_PATH = os.path.join(CONFIG_DIR, "calendars.json")

CONFERENCE_URL_RE = re.compile(
    r"https?://[^\s<>\"]*(meet\.google\.com|zoom\.us|teams\.microsoft\.com)[^\s<>\"]*",
    re.IGNORECASE,
)

CONNECT_TIMEOUT_SECONDS = 10


def google_account_roots(registry):
    """Top-level sources that are a Google account linked through GOA —
    the same test GNOME Calendar's own backend uses, not a guess."""
    roots = []
    for source in registry.list_sources(None):
        if source.get_parent():
            continue
        if not (source.has_extension("Collection") and source.has_extension("GNOME Online Accounts")):
            continue
        if source.get_extension("Collection").get_backend_name() != "google":
            continue
        roots.append(source)
    return roots


def all_calendar_sources(registry, root_uids):
    """Every real, enabled calendar under a Google account — before the
    user has picked which ones they actually want on the bar. Used by
    --list-calendars and --select-calendars; the normal sync path narrows
    this down further with load_selected_uids()."""
    for source in registry.list_sources(None):
        if source.get_parent() not in root_uids:
            continue
        if not source.has_extension("Calendar"):
            continue
        if not source.get_enabled():
            continue
        yield source


def load_selected_uids():
    """None means "never configured" (distinct from an empty set, which
    means the user picked zero calendars on purpose) — read_events() turns
    the None case into an actionable error instead of silently syncing
    nothing, or worse, silently syncing everything."""
    try:
        with open(CONFIG_PATH) as f:
            data = json.load(f)
        return set(data.get("enabled_uids", []))
    except (OSError, ValueError):
        return None


def save_selected_uids(uids):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(CONFIG_PATH, "w") as f:
        json.dump({"enabled_uids": sorted(uids)}, f, indent=2)


def calendar_sources_for(registry, root_uids, selected_uids):
    for source in all_calendar_sources(registry, root_uids):
        if source.get_uid() in selected_uids:
            yield source


def ical_time_to_iso(t):
    if t.is_date():
        return "%04d-%02d-%02dT00:00:00Z" % (t.get_year(), t.get_month(), t.get_day())
    # ICalGLib.Time.as_timet() ignores the timezone attached via
    # get_timezone() and reads the wall-clock numbers as if they were
    # already UTC — a 9am America/Toronto event comes back as "09:00:00Z"
    # instead of "13:00:00Z". Converting to the UTC zone first forces the
    # actual offset to be applied. Confirmed against a real EDT (UTC-4)
    # event: as_timet() alone was off by exactly the zone's offset.
    if not t.is_utc() and t.get_timezone() is not None:
        t = t.convert_to_zone(ICalGLib.Timezone.get_utc_timezone())
    dt = datetime.datetime.fromtimestamp(t.as_timet(), tz=datetime.timezone.utc)
    return dt.isoformat().replace("+00:00", "Z")


def strip_mailto(value):
    if not value:
        return ""
    return value[7:] if value.lower().startswith("mailto:") else value


def extract_attendees(ical):
    attendees = []
    prop = ical.get_first_property(ICalGLib.PropertyKind.ATTENDEE_PROPERTY)
    while prop:
        email = strip_mailto(prop.get_attendee())
        name = prop.get_parameter_as_string("CN") or email
        status = (prop.get_parameter_as_string("PARTSTAT") or "").lower()
        attendees.append({"name": name, "email": email, "status": status})
        prop = ical.get_next_property(ICalGLib.PropertyKind.ATTENDEE_PROPERTY)
    return attendees


STATUS_LABELS = {
    ICalGLib.PropertyStatus.TENTATIVE: "tentative",
    ICalGLib.PropertyStatus.CANCELLED: "cancelled",
}


def extract_status(ical):
    # CONFIRMED is the default for every synced event and carries no
    # signal — only the two states worth a banner are worth returning.
    prop = ical.get_first_property(ICalGLib.PropertyKind.STATUS_PROPERTY)
    if not prop:
        return ""
    return STATUS_LABELS.get(ical.get_status(), "")


def extract_busy(ical):
    prop = ical.get_first_property(ICalGLib.PropertyKind.TRANSP_PROPERTY)
    if not prop:
        return None
    return prop.get_transp() == ICalGLib.PropertyTransp.OPAQUE


def extract_reminder_minutes(ical):
    alarm = ical.get_first_component(ICalGLib.ComponentKind.VALARM_COMPONENT)
    if not alarm:
        return None
    trigger_prop = alarm.get_first_property(ICalGLib.PropertyKind.TRIGGER_PROPERTY)
    if not trigger_prop:
        return None
    trigger = trigger_prop.get_trigger()
    if not trigger or trigger.is_null_trigger() or trigger.is_bad_trigger():
        return None
    seconds = trigger.get_duration().as_seconds()
    return abs(seconds) // 60 if seconds else None


def extract_organizer(ical):
    prop = ical.get_first_property(ICalGLib.PropertyKind.ORGANIZER_PROPERTY)
    if not prop:
        return None
    email = strip_mailto(prop.get_organizer())
    if not email:
        return None
    return {"name": prop.get_parameter_as_string("CN") or email, "email": email}


RRULE_WEEKDAY_NAMES = {"MO": "Monday", "TU": "Tuesday", "WE": "Wednesday", "TH": "Thursday",
                        "FR": "Friday", "SA": "Saturday", "SU": "Sunday"}
RRULE_WEEKDAYS = ("MO", "TU", "WE", "TH", "FR")


def humanize_recurrence(rrule_text):
    """"FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR" -> "Every weekday" — the same
    plain-English summary Google Calendar's own event card shows, covering
    the FREQ/INTERVAL/BYDAY/UNTIL/COUNT terms real calendars actually use
    rather than the full RFC 5545 grammar."""
    if not rrule_text:
        return ""
    parts = dict(p.split("=", 1) for p in rrule_text.split(";") if "=" in p)
    freq = parts.get("FREQ", "")
    interval = int(parts.get("INTERVAL", "1") or "1")
    byday = [d for d in parts.get("BYDAY", "").split(",") if d]

    if freq == "DAILY":
        base = "Daily" if interval == 1 else "Every %d days" % interval
    elif freq == "WEEKLY":
        if interval == 1 and set(byday) == set(RRULE_WEEKDAYS):
            base = "Every weekday"
        elif byday:
            base = ("Weekly" if interval == 1 else "Every %d weeks" % interval) \
                + " on " + ", ".join(RRULE_WEEKDAY_NAMES.get(d, d) for d in byday)
        else:
            base = "Weekly" if interval == 1 else "Every %d weeks" % interval
    elif freq == "MONTHLY":
        base = "Monthly" if interval == 1 else "Every %d months" % interval
    elif freq == "YEARLY":
        base = "Yearly" if interval == 1 else "Every %d years" % interval
    else:
        return ""

    until = parts.get("UNTIL", "")
    count = parts.get("COUNT", "")
    if until:
        try:
            base += " until " + datetime.datetime.strptime(until[:8], "%Y%m%d").strftime("%b %-d, %Y")
        except ValueError:
            pass
    elif count:
        base += " (%s times)" % count
    return base


def extract_recurrence(ical):
    prop = ical.get_first_property(ICalGLib.PropertyKind.RRULE_PROPERTY)
    if not prop:
        return ""
    recur = prop.get_rrule()
    return humanize_recurrence(recur.to_string()) if recur else ""


def extract_join_url(ical, description):
    url_prop = ical.get_first_property(ICalGLib.PropertyKind.URL_PROPERTY)
    if url_prop:
        url = url_prop.get_url()
        if url:
            return url
    match = CONFERENCE_URL_RE.search(description or "")
    return match.group(0) if match else ""


def event_to_dict(ical, instance_start, instance_end, calendar_name, calendar_color, account_label):
    # `ical` here is the ICalGLib.Component generate_instances_sync handed
    # back for THIS occurrence — its own get_dtstart()/get_dtend() still
    # read the recurrence master's original date (a birthday's 1988, not
    # this year's), which is why the instance start/end the callback
    # passed separately are what gets used below, not ical.get_dtstart().
    description = ical.get_description() or ""
    recurrence_id = ical.get_recurrenceid()
    instance_key = recurrence_id.as_ical_string() if recurrence_id and not recurrence_id.is_null_time() else "single"
    return {
        "id": "%s:%s" % (ical.get_uid(), instance_key),
        "title": ical.get_summary() or "(untitled event)",
        "start": ical_time_to_iso(instance_start),
        "end": ical_time_to_iso(instance_end),
        "allDay": bool(instance_start.is_date()),
        "location": ical.get_location() or "",
        "description": description,
        "calendarName": calendar_name,
        "calendarColor": calendar_color or "",
        "accountLabel": account_label,
        "attendees": extract_attendees(ical),
        "joinUrl": extract_join_url(ical, description),
        "organizer": extract_organizer(ical),
        "recurrence": extract_recurrence(ical),
        "status": extract_status(ical),
        "busy": extract_busy(ical),
        "reminderMinutes": extract_reminder_minutes(ical),
    }


def read_events(days, force_refresh):
    """Returns (events, error). `error` is a human-readable string
    naming what went wrong; it is never raised past this function, since
    a partial failure on one calendar must not blank the others."""
    registry = EDataServer.SourceRegistry.new_sync(None)
    roots = google_account_roots(registry)
    if not roots:
        return [], "No Google account linked — add one in Settings > Online Accounts"

    root_uids = {r.get_uid() for r in roots}
    account_labels = {r.get_uid(): r.get_display_name() for r in roots}

    selected_uids = load_selected_uids()
    if selected_uids is None:
        return [], "No calendars selected — run: eds_read.py --select-calendars"
    if not selected_uids:
        # A deliberate empty selection is not an error — it is "I don't
        # want any of these on the bar right now".
        return [], None

    now = datetime.datetime.now(datetime.timezone.utc)
    end = now + datetime.timedelta(days=days)
    start_epoch = int(now.timestamp())
    end_epoch = int(end.timestamp())

    events = []
    failures = []
    for source in calendar_sources_for(registry, root_uids, selected_uids):
        calendar_name = source.get_display_name()
        try:
            client = ECal.Client.connect_sync(source, ECal.ClientSourceType.EVENTS, CONNECT_TIMEOUT_SECONDS, None)
            if force_refresh and client.check_refresh_supported():
                client.refresh_sync(None)
            calendar_color = source.get_extension("Calendar").get_color()
            account_label = account_labels.get(source.get_parent(), "")

            # generate_instances_sync (not get_object_list_as_comps_sync)
            # is what actually expands recurrences to real per-occurrence
            # dates — see event_to_dict's comment for why this matters.
            def on_instance(ical, instance_start, instance_end, _data=None):
                events.append(event_to_dict(ical, instance_start, instance_end, calendar_name, calendar_color, account_label))
                return True

            client.generate_instances_sync(start_epoch, end_epoch, None, on_instance)
        except GLib.Error as e:
            failures.append("%s (%s)" % (calendar_name, e.message))

    error = ("Some calendars failed to sync: " + ", ".join(failures)) if failures else None
    return events, error


def load_previous_cache():
    try:
        with open(CACHE_PATH) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {"events": [], "last_sync_utc": None, "last_error": None}


def write_cache(events, error):
    os.makedirs(CACHE_DIR, exist_ok=True)
    now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")

    # A total failure (no accounts, or every calendar errored with nothing
    # read) must never blank a previously-good cache — that would look
    # identical to "you have no events today" in the widget.
    if not events and error:
        previous = load_previous_cache()
        events = previous.get("events", [])

    payload = {"events": events, "last_sync_utc": now_iso, "last_error": error}
    tmp_path = CACHE_PATH + ".tmp"
    with open(tmp_path, "w") as f:
        json.dump(payload, f)
    os.replace(tmp_path, CACHE_PATH)
    return payload


def discover_calendars():
    """(registry, [(source, account_label), ...]) for every real calendar
    across every linked Google account — the full list --list-calendars
    and --select-calendars both start from."""
    registry = EDataServer.SourceRegistry.new_sync(None)
    roots = google_account_roots(registry)
    root_uids = {r.get_uid() for r in roots}
    account_labels = {r.get_uid(): r.get_display_name() for r in roots}
    calendars = [
        (source, account_labels.get(source.get_parent(), ""))
        for source in all_calendar_sources(registry, root_uids)
    ]
    return registry, roots, calendars


def cmd_list_calendars_json():
    """Machine-readable form of --list-calendars for the QML settings
    panel — same discovery logic, no terminal interaction, so the widget
    can render its own checklist instead of shelling out to a picker."""
    registry, roots, calendars = discover_calendars()
    if not roots:
        print(json.dumps({"error": "No Google account linked", "calendars": []}))
        return 1
    selected = load_selected_uids() or set()
    payload = [
        {
            "uid": source.get_uid(),
            "name": source.get_display_name(),
            "account": account_label,
            "color": source.get_extension("Calendar").get_color() or "",
            "selected": source.get_uid() in selected,
        }
        for source, account_label in calendars
    ]
    print(json.dumps({"error": None, "calendars": payload}))
    return 0


def cmd_list_options():
    """Flat `[{value,label,description}]` array — the exact shape the
    shell's own Ui/MultiSelect.qml expects from an `optionsCommand`. Used
    as the widget's calendar picker instead of building a custom checkbox
    list from scratch."""
    registry, roots, calendars = discover_calendars()
    options = [
        {"value": source.get_uid(), "label": source.get_display_name(), "description": account_label}
        for source, account_label in calendars
    ]
    print(json.dumps(options))
    return 0


def cmd_print_selected():
    """Just the current selection as a JSON array — MultiSelect's `values`
    binding needs this once, up front, separately from the option list
    itself (which comes from --list-options)."""
    print(json.dumps(sorted(load_selected_uids() or set())))
    return 0


def cmd_set_selected(raw_uids):
    uids = {u.strip() for u in raw_uids.split(",") if u.strip()}
    save_selected_uids(uids)
    print("Saved %d selected calendar(s) to %s" % (len(uids), CONFIG_PATH))
    return 0


def cmd_list_calendars():
    registry, roots, calendars = discover_calendars()
    if not roots:
        print("No Google account linked — add one in Settings > Online Accounts")
        return 1
    selected = load_selected_uids() or set()
    for i, (source, account_label) in enumerate(calendars, start=1):
        mark = "x" if source.get_uid() in selected else " "
        print("[%s] %2d. %s  (%s)" % (mark, i, source.get_display_name(), account_label))
    return 0


def cmd_select_calendars():
    """Interactive terminal picker, the same idea as GNOME Calendar's own
    "which calendars to display" toggle list — most Google accounts carry
    dozens of calendars (holidays, shared bookings, read-only feeds); most
    people want 4 or 5 of them on a bar clock, not all of them."""
    registry, roots, calendars = discover_calendars()
    if not roots:
        print("No Google account linked — add one in Settings > Online Accounts, then run this again.")
        return 1
    if not calendars:
        print("No calendars found on your linked Google account(s).")
        return 1

    previously_selected = load_selected_uids() or set()
    print("Pick the calendars to show on the bar (comma-separated numbers, e.g. 1,3,5):\n")
    for i, (source, account_label) in enumerate(calendars, start=1):
        mark = "x" if source.get_uid() in previously_selected else " "
        print("[%s] %2d. %s  (%s)" % (mark, i, source.get_display_name(), account_label))

    raw = input("\n> ").strip()
    if raw == "":
        print("No change made.")
        return 0

    try:
        indices = {int(part.strip()) for part in raw.split(",") if part.strip()}
    except ValueError:
        print("Could not parse that — expected comma-separated numbers like 1,3,5")
        return 1

    chosen_uids = set()
    for i in indices:
        if 1 <= i <= len(calendars):
            chosen_uids.add(calendars[i - 1][0].get_uid())
    save_selected_uids(chosen_uids)
    print("Saved %d selected calendar(s) to %s" % (len(chosen_uids), CONFIG_PATH))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--days", type=int, default=14, help="how many days ahead to fetch (default 14)")
    parser.add_argument("--refresh", action="store_true", help="force EDS to refresh every linked calendar before reading")
    parser.add_argument("--check-accounts", action="store_true", help="print whether a Google GOA account is linked and exit (no event fetch, no cache write) — used by install.sh")
    parser.add_argument("--list-calendars", action="store_true", help="list every calendar under your linked Google account(s) and which are selected, then exit")
    parser.add_argument("--list-calendars-json", action="store_true", help="same as --list-calendars but as JSON, for the widget's own calendar picker")
    parser.add_argument("--list-options", action="store_true", help="flat [{value,label,description}] array — the shape qs.Ui MultiSelect's optionsCommand expects")
    parser.add_argument("--print-selected", action="store_true", help="print the currently selected calendar UIDs as a JSON array")
    parser.add_argument("--select-calendars", action="store_true", help="interactively pick which calendars show on the bar, then exit")
    parser.add_argument("--set-selected", metavar="UID1,UID2,...", help="non-interactively set the selected calendar UIDs (empty string clears the selection) — used by the widget's calendar picker")
    args = parser.parse_args()

    if args.check_accounts:
        registry = EDataServer.SourceRegistry.new_sync(None)
        roots = google_account_roots(registry)
        for r in roots:
            print(r.get_display_name())
        return 0 if roots else 1

    if args.list_calendars:
        return cmd_list_calendars()

    if args.list_calendars_json:
        return cmd_list_calendars_json()

    if args.list_options:
        return cmd_list_options()

    if args.print_selected:
        return cmd_print_selected()

    if args.set_selected is not None:
        return cmd_set_selected(args.set_selected)

    if args.select_calendars:
        return cmd_select_calendars()

    events, error = read_events(args.days, args.refresh)
    payload = write_cache(events, error)

    print("wrote %d events to %s%s" % (len(payload["events"]), CACHE_PATH, (" (error: %s)" % error) if error else ""))
    return 1 if error else 0


if __name__ == "__main__":
    sys.exit(main())
