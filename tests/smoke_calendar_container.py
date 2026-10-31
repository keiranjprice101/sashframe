"""Run a built production image against synthetic calendars, without Google access.

Usage: python3 tests/smoke_calendar_container.py --image sashframe-app:google-calendar
"""
from __future__ import annotations

import argparse
from datetime import date, timedelta
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
import uuid


def request(base, path, etag=None):
    headers = {"If-None-Match": etag} if etag else {}
    try:
        with urlopen(Request(base + path, headers=headers), timeout=2) as response:
            return response.status, response.headers, response.read().decode()
    except HTTPError as response:
        return response.code, response.headers, response.read().decode()


def smoke(image, runtime, provider):
    with tempfile.TemporaryDirectory(prefix="sashframe-container-smoke-") as directory:
        os.chmod(directory, 0o755)
        cache = Path(directory) / "google.json"
        today = date.today()
        snapshot = {
            "version": 1, "calendarId": "smoke-calendar",
            "events": [{"id": "smoke-event", "summary": "Feature smoke event",
                        "start": {"date": today.isoformat()},
                        "end": {"date": (today + timedelta(days=1)).isoformat()}}],
        }
        cache.write_text(json.dumps(snapshot))
        # Use an unused loopback port even when the host's Podman defaults to host networking.
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        name = "sashframe-calendar-smoke-" + uuid.uuid4().hex[:10]
        command = [runtime, "run", "--detach", "--rm", "--pull=never", "--name", name,
                   "--network=host", "-e", "HOST=127.0.0.1", "-e", f"PORT={port}",
                   "-v", f"{directory}:/data/calendar:ro",
                   "-e", f"SASHFRAME_CALENDAR_PROVIDER={provider}",
                   "-e", "GOOGLE_CALENDAR_ID=smoke-calendar",
                   "-e", "GOOGLE_CALENDAR_CACHE=/data/calendar/google.json",
                   "-e", "SHIFTER_INPUT_DIR=/data/calendar/missing",
                   "-e", "SHIFTER_FILE_PATH=/data/calendar/missing.Shifter", image]
        subprocess.run(command, check=True, capture_output=True, text=True)
        try:
            base = f"http://127.0.0.1:{port}"
            deadline = time.monotonic() + 30
            while True:
                try:
                    status, _, body = request(base, "/health")
                    if status == 200 and json.loads(body)["status"] == "ok":
                        break
                except (URLError, OSError):
                    pass
                if time.monotonic() >= deadline:
                    logs = subprocess.check_output([runtime, "logs", name], text=True, stderr=subprocess.STDOUT)
                    raise AssertionError(f"Production container did not become healthy at {base}:\n{logs}")
                time.sleep(0.1)
            status, headers, body = request(base, "/api/calendar")
            assert status == 200
            events = json.loads(body)
            etag = headers["ETag"]
            assert request(base, "/api/calendar", etag)[0] == 304
            status, _, page = request(base, "/")
            assert status == 200
            if provider == "google":
                assert len(events) == 1 and events[0]["source"] == "google"
                assert "Feature smoke event" in page
                cache.write_text("{invalid")
                assert request(base, "/api/calendar", etag)[0] == 304
                cache.write_text(json.dumps({**snapshot, "events": []}))
                status, empty_headers, empty_body = request(base, "/api/calendar", etag)
                assert status == 200 and json.loads(empty_body) == []
                assert empty_headers["ETag"] != etag
                status, _, page = request(base, "/")
                assert status == 200 and "Work Project Sprint" not in page
                assert "Feature smoke event" not in page
            else:
                assert events == []  # Shifter never consumes the Google snapshot.
                assert "Feature smoke event" not in page
                assert "Work Project Sprint" in page  # Existing demo fallback remains.
            print(f"{provider}: health, SSR, API, and conditional requests passed")
        finally:
            subprocess.run([runtime, "stop", "--time", "2", name], check=False, capture_output=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", default="sashframe-app:google-calendar")
    parser.add_argument("--runtime", default="podman")
    args = parser.parse_args()
    for selected in ("shifter", "google"):
        smoke(args.image, args.runtime, selected)
