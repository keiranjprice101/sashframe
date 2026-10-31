"""Fetch a complete bounded calendar snapshot without exposing credentials to the app."""
from __future__ import annotations

from datetime import date, datetime
import fcntl
import json
import os
from pathlib import Path
import random
import tempfile
import time
from urllib.parse import quote
from zoneinfo import ZoneInfo

from google.auth.transport.requests import AuthorizedSession, Request
from google.oauth2 import service_account
import requests

SCOPE = "https://www.googleapis.com/auth/calendar.events.readonly"
FIELDS = "nextPageToken,items(id,status,summary,description,location,visibility,start,end)"
RETRY_REASONS = {"rateLimitExceeded", "userRateLimitExceeded", "backendError"}


class SyncError(Exception):
    """An operator-safe message; never include API bodies, tokens, or event contents."""


class TimeoutRequest(Request):
    def __call__(self, *args, **kwargs):
        kwargs["timeout"] = (5, 20)
        return super().__call__(*args, **kwargs)


def sync_window(now: datetime, time_zone: str) -> tuple[str, str]:
    zone = ZoneInfo(time_zone)
    current = now.astimezone(zone)

    def month_start(offset: int) -> str:
        total = current.year * 12 + current.month - 1 + offset
        year, month = divmod(total, 12)
        return datetime(year, month + 1, 1, tzinfo=zone).isoformat()

    return month_start(-1), month_start(4)


def request_page(session, url: str, params: dict, sleep=time.sleep) -> dict:
    for attempt in range(4):
        try:
            response = session.get(url, params=params, timeout=(5, 25))
        except requests.RequestException:
            if attempt == 3:
                raise SyncError("Calendar request failed after retries") from None
        else:
            if response.status_code == 200:
                try:
                    page = response.json()
                except ValueError:
                    raise SyncError("Calendar returned invalid JSON") from None
                if not isinstance(page, dict) or not isinstance(page.get("items", []), list):
                    raise SyncError("Calendar returned an invalid event page")
                return page
            retry = response.status_code == 429 or 500 <= response.status_code < 600
            if response.status_code == 403:
                try:
                    errors = response.json().get("error", {}).get("errors", [])
                    retry = any(item.get("reason") in RETRY_REASONS for item in errors)
                except (ValueError, AttributeError, TypeError):
                    retry = False
            if not retry or attempt == 3:
                raise SyncError(f"Calendar request failed (HTTP {response.status_code}); check API access and calendar sharing")
        sleep(2 ** attempt + random.uniform(0, 0.5))
    raise SyncError("Calendar request failed")


def fetch_snapshot(session, calendar_id: str, time_zone: str, now: datetime, sleep=time.sleep) -> dict:
    time_min, time_max = sync_window(now, time_zone)
    url = f"https://www.googleapis.com/calendar/v3/calendars/{quote(calendar_id, safe='')}/events"
    params = {"singleEvents": "true", "showDeleted": "false", "timeMin": time_min,
              "timeMax": time_max, "timeZone": time_zone, "maxResults": 2500,
              "fields": FIELDS}
    events = []
    seen_tokens = set()
    while True:
        page = request_page(session, url, params.copy(), sleep)
        page_events = page.get("items", [])
        if not all(valid_event(event) for event in page_events):
            raise SyncError("Calendar returned an invalid event record")
        events.extend(page_events)
        token = page.get("nextPageToken")
        if not token:
            break
        if not isinstance(token, str) or token in seen_tokens:
            raise SyncError("Calendar returned an invalid pagination token")
        seen_tokens.add(token)
        params["pageToken"] = token
    return {"version": 1, "calendarId": calendar_id, "timeZone": time_zone,
            "syncedAt": now.isoformat(), "timeMin": time_min, "timeMax": time_max,
            "events": events}


def valid_event(event) -> bool:
    if not isinstance(event, dict) or not isinstance(event.get("id"), str) or not event["id"]:
        return False
    if event.get("status") == "cancelled":
        return True
    start, end = event.get("start"), event.get("end")
    if not isinstance(start, dict) or not isinstance(end, dict):
        return False
    try:
        if "date" in start and "date" in end:
            first, last = date.fromisoformat(start["date"]), date.fromisoformat(end["date"])
            return first.isoformat() == start["date"] and last.isoformat() == end["date"] and first < last
        first, last = datetime.fromisoformat(start["dateTime"]), datetime.fromisoformat(end["dateTime"])
        return first.tzinfo is not None and last.tzinfo is not None and first < last
    except (TypeError, ValueError, KeyError):
        return False


def atomic_write(path: Path, snapshot: dict):
    descriptor, temporary = tempfile.mkstemp(prefix=".google-", suffix=".json", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            # The web container runs with the same configured UID/GID.
            os.fchmod(output.fileno(), 0o640)
            json.dump(snapshot, output, ensure_ascii=False, separators=(",", ":"))
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def synchronize(calendar_id: str, credentials_path: str, cache_path: Path, time_zone: str, *, session=None, now=None, sleep=time.sleep) -> bool:
    if not calendar_id or calendar_id == "primary":
        raise SyncError("GOOGLE_CALENDAR_ID must identify the shared calendar explicitly")
    ZoneInfo(time_zone)
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    # Keep a persistent lock inode: unlinking lock files can let concurrent runs overlap.
    with cache_path.with_suffix(cache_path.suffix + ".lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return False
        owned_session = session is None
        if owned_session:
            credentials = service_account.Credentials.from_service_account_file(credentials_path, scopes=[SCOPE])
            session = AuthorizedSession(credentials, auth_request=TimeoutRequest(), max_refresh_attempts=1)
        try:
            snapshot = fetch_snapshot(session, calendar_id, time_zone, now or datetime.now().astimezone(), sleep)
            atomic_write(cache_path, snapshot)
        finally:
            if owned_session:
                session.close()
    return True


def main() -> int:
    try:
        credentials_path = os.environ.get("GOOGLE_SERVICE_ACCOUNT_FILE", "")
        if not credentials_path:
            raise SyncError("GOOGLE_SERVICE_ACCOUNT_FILE is required")
        completed = synchronize(os.environ.get("GOOGLE_CALENDAR_ID", ""), credentials_path,
                                Path(os.environ.get("GOOGLE_CALENDAR_CACHE", "data/calendar/google.json")),
                                os.environ.get("SASHFRAME_TIMEZONE", "Europe/London"))
        print("[Calendar] Snapshot synchronized" if completed else "[Calendar] Another sync is already running")
        return 0
    except SyncError as error:
        print(f"[Calendar] {error}")
    except Exception:
        print("[Calendar] Synchronization failed; check credentials, timezone, and cache permissions")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
