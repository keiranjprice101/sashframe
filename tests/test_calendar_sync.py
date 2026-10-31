from datetime import datetime, timezone
import fcntl
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import requests

from services.calendar.sync import SCOPE, SyncError, atomic_write, fetch_snapshot, request_page, synchronize, sync_window


def response(status=200, data=None):
    result = Mock(status_code=status)
    result.json.return_value = data if data is not None else {"items": []}
    return result


def event(event_id):
    return {"id": event_id, "start": {"date": "2026-11-01"}, "end": {"date": "2026-11-02"}}


class CalendarSyncTests(unittest.TestCase):
    now = datetime(2026, 10, 31, 12, tzinfo=timezone.utc)

    def test_window_covers_previous_month_through_three_months_ahead_in_local_timezone(self):
        self.assertEqual(sync_window(self.now, "Europe/London"), ("2026-09-01T00:00:00+01:00", "2027-02-01T00:00:00+00:00"))
        self.assertEqual(sync_window(datetime(2026, 12, 31, 23, 30, tzinfo=timezone.utc), "Europe/Paris")[0], "2026-12-01T00:00:00+01:00")

    def test_all_pages_are_loaded_with_recurrence_expansion_and_encoded_calendar_id(self):
        session = Mock()
        session.get.side_effect = [response(data={"items": [event("first")], "nextPageToken": "page2"}), response(data={"items": [event("second")]})]
        snapshot = fetch_snapshot(session, "family@example.com", "Europe/London", self.now)
        self.assertEqual([event["id"] for event in snapshot["events"]], ["first", "second"])
        self.assertIn("family%40example.com", session.get.call_args.args[0])
        first_params = session.get.call_args_list[0].kwargs["params"]
        second_params = session.get.call_args_list[1].kwargs["params"]
        self.assertEqual(first_params["singleEvents"], "true")
        self.assertEqual(first_params["showDeleted"], "false")
        self.assertNotIn("pageToken", first_params)
        self.assertEqual(second_params["pageToken"], "page2")
        self.assertEqual(snapshot["version"], 1)

    def test_retryable_failures_are_bounded_and_access_denied_is_not_retried(self):
        session = Mock()
        session.get.side_effect = [requests.Timeout(), response(429), response(503), response()]
        sleep = Mock()
        self.assertEqual(request_page(session, "url", {}, sleep), {"items": []})
        self.assertEqual(sleep.call_count, 3)
        session.get.side_effect = None
        session.get.return_value = response(403, {"error": {"errors": [{"reason": "forbidden"}]}})
        session.get.reset_mock()
        with self.assertRaisesRegex(SyncError, "HTTP 403"):
            request_page(session, "url", {}, sleep)
        self.assertEqual(session.get.call_count, 1)
        session.get.return_value = response(403, {"error": {"errors": [{"reason": "rateLimitExceeded"}]}})
        session.get.reset_mock()
        with self.assertRaises(SyncError):
            request_page(session, "url", {}, Mock())
        self.assertEqual(session.get.call_count, 4)

    def test_failed_second_page_keeps_previous_snapshot_and_successful_empty_sync_clears_it(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / "google.json"
            atomic_write(cache, {"events": [{"id": "old"}]})
            old = cache.read_bytes()
            session = Mock()
            session.get.side_effect = [response(data={"items": [event("new")], "nextPageToken": "next"}), response(403)]
            with self.assertRaises(SyncError):
                synchronize("calendar", "unused", cache, "Europe/London", session=session, now=self.now)
            self.assertEqual(cache.read_bytes(), old)
            session.get.side_effect = [response()]
            self.assertTrue(synchronize("calendar", "unused", cache, "Europe/London", session=session, now=self.now))
            self.assertEqual(json.loads(cache.read_text())["events"], [])
            self.assertEqual(cache.stat().st_mode & 0o777, 0o640)

    def test_malformed_events_do_not_replace_persistent_last_good_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / "google.json"
            atomic_write(cache, {"events": [event("old")]})
            previous = cache.read_bytes()
            for invalid in [None, {}, {"id": "missing-times"}, {"id": "bad-date", "start": {"date": "2026-02-30"}, "end": {"date": "2026-03-02"}}, {"id": "reverse", "start": {"dateTime": "2026-11-02T10:00:00Z"}, "end": {"dateTime": "2026-11-01T10:00:00Z"}}]:
                session = Mock()
                session.get.return_value = response(data={"items": [invalid]})
                with self.assertRaisesRegex(SyncError, "invalid event record"):
                    synchronize("calendar", "unused", cache, "Europe/London", session=session, now=self.now)
                self.assertEqual(cache.read_bytes(), previous)

    def test_interrupted_atomic_write_preserves_cache_and_cleans_temporary_file(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / "google.json"
            atomic_write(cache, {"events": ["old"]})
            with patch("services.calendar.sync.os.replace", side_effect=OSError("disk failure")):
                with self.assertRaises(OSError):
                    atomic_write(cache, {"events": ["new"]})
            self.assertEqual(json.loads(cache.read_text())["events"], ["old"])
            self.assertEqual(list(Path(directory).iterdir()), [cache])

    def test_concurrent_run_does_not_fetch_or_replace_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / "google.json"
            with cache.with_suffix(".json.lock").open("a") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                session = Mock()
                self.assertFalse(synchronize("calendar", "unused", cache, "Europe/London", session=session))
                session.get.assert_not_called()

    def test_authentication_reuses_service_account_with_readonly_scope_and_no_impersonation(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / "google.json"
            with patch("services.calendar.sync.service_account.Credentials.from_service_account_file") as credentials, patch("services.calendar.sync.AuthorizedSession") as authorized:
                authorized.return_value.get.return_value = response()
                synchronize("calendar", "/existing/photo-key.json", cache, "Europe/London", now=self.now)
                credentials.assert_called_once_with("/existing/photo-key.json", scopes=[SCOPE])
                authorized.return_value.close.assert_called_once()

    def test_invalid_pagination_and_malformed_pages_do_not_loop_or_overwrite(self):
        session = Mock()
        session.get.return_value = response(data={"items": [], "nextPageToken": "same"})
        with self.assertRaisesRegex(SyncError, "pagination"):
            fetch_snapshot(session, "calendar", "Europe/London", self.now)
        self.assertEqual(session.get.call_count, 2)
        session.get.return_value = response(data={"items": "bad"})
        with self.assertRaisesRegex(SyncError, "invalid event page"):
            fetch_snapshot(session, "calendar", "Europe/London", self.now)


if __name__ == "__main__":
    unittest.main()
