#!/usr/bin/env python3
"""Self-check for eds_read.py's non-gi-dependent logic (the EDS/ECal calls
themselves were verified by hand against this machine's real calendars —
see the plan doc's build notes). Run with the system python3:
    /usr/bin/python3 sync/test_eds_read.py
"""
import json
import os
import tempfile

import eds_read


def test_strip_mailto():
    assert eds_read.strip_mailto("mailto:a@b.com") == "a@b.com"
    assert eds_read.strip_mailto("a@b.com") == "a@b.com"
    assert eds_read.strip_mailto("") == ""
    assert eds_read.strip_mailto(None) == ""


def test_conference_url_regex_via_extract_join_url():
    class FakeUrlProp:
        def get_url(self):
            return None

    class FakeIcal:
        def __init__(self, has_url_prop):
            self._has_url_prop = has_url_prop

        def get_first_property(self, kind):
            return FakeUrlProp() if self._has_url_prop else None

    # No dedicated URL property: falls back to a Meet/Zoom/Teams link in
    # the description, which is the real-world case eds_read hits often
    # (verified against this machine's own calendar data).
    ical = FakeIcal(has_url_prop=False)
    assert eds_read.extract_join_url(ical, "Join: https://meet.google.com/abc-defg-hij") == "https://meet.google.com/abc-defg-hij"
    assert eds_read.extract_join_url(ical, "Call in at https://tribalscale.zoom.us/j/12345") == "https://tribalscale.zoom.us/j/12345"
    assert eds_read.extract_join_url(ical, "no link here") == ""


def test_selected_uids_round_trip():
    # Point the module at a scratch config dir so this never touches the
    # real ~/.config/omarchy-google-calendar/calendars.json.
    with tempfile.TemporaryDirectory() as tmp:
        original_path = eds_read.CONFIG_PATH
        original_dir = eds_read.CONFIG_DIR
        eds_read.CONFIG_DIR = tmp
        eds_read.CONFIG_PATH = os.path.join(tmp, "calendars.json")
        try:
            assert eds_read.load_selected_uids() is None  # never configured

            eds_read.save_selected_uids({"uid-a", "uid-b"})
            loaded = eds_read.load_selected_uids()
            assert loaded == {"uid-a", "uid-b"}

            eds_read.save_selected_uids(set())
            assert eds_read.load_selected_uids() == set()  # deliberate empty selection, not None
        finally:
            eds_read.CONFIG_PATH = original_path
            eds_read.CONFIG_DIR = original_dir


def test_write_cache_preserves_events_on_total_failure():
    with tempfile.TemporaryDirectory() as tmp:
        original_cache_path = eds_read.CACHE_PATH
        original_cache_dir = eds_read.CACHE_DIR
        eds_read.CACHE_DIR = tmp
        eds_read.CACHE_PATH = os.path.join(tmp, "events.json")
        try:
            good = eds_read.write_cache([{"id": "1", "title": "Keep me"}], None)
            assert good["events"][0]["title"] == "Keep me"

            # A total failure must not blank a previously-good cache — a
            # broken sync must never look identical to "no events today".
            after_failure = eds_read.write_cache([], "everything broke")
            assert after_failure["events"][0]["title"] == "Keep me"
            assert after_failure["last_error"] == "everything broke"

            # A deliberate empty selection (error=None) DOES write empty —
            # that is a real "nothing selected" state, not a failure.
            deliberate_empty = eds_read.write_cache([], None)
            assert deliberate_empty["events"] == []
        finally:
            eds_read.CACHE_PATH = original_cache_path
            eds_read.CACHE_DIR = original_cache_dir


if __name__ == "__main__":
    test_strip_mailto()
    test_conference_url_regex_via_extract_join_url()
    test_selected_uids_round_trip()
    test_write_cache_preserves_events_on_total_failure()
    print("test_eds_read: all assertions passed")
