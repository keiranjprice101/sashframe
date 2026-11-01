"""Exercise calendar shell entrypoints without Docker, credentials, or systemd."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class CalendarLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="sashframe-lifecycle-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "scripts").mkdir()
        (self.root / "bin").mkdir()
        (self.root / "state").mkdir()
        (self.root / "state/deployed-sha").write_text("abcdef1234567890\n")
        self.log = self.root / "commands.jsonl"
        self.env = {
            **os.environ,
            "PATH": f"{self.root / 'bin'}:{os.environ['PATH']}",
            "ENV_FILE": str(self.root / "installation.env"),
            "SASHFRAME_STATE_DIR": str(self.root / "state"),
            "SASHFRAME_CALENDAR_PROVIDER": "google",
            "COMMAND_LOG": str(self.log),
        }
        self.env.pop("IMAGE_TAG", None)
        self.executable("docker", """#!/usr/bin/env python3
import json, os, sys
with open(os.environ['COMMAND_LOG'], 'a') as output:
    output.write(json.dumps({'args': sys.argv[1:], 'image': os.environ.get('IMAGE_TAG')}) + '\\n')
if sys.argv[1:3] == ['inspect', '--format']:
    print('true')
if sys.argv[1:3] == ['image', 'inspect'] and os.environ.get('PULL_FAIL') and 'ghcr.io/' in sys.argv[-1]:
    sys.exit(1)
if sys.argv[1] == 'pull' and os.environ.get('PULL_FAIL'):
    sys.exit(1)
if sys.argv[1:3] == ['image', 'inspect'] and '--format' in sys.argv:
    print('linux/arm64' if 'Architecture' in sys.argv[sys.argv.index('--format') + 1] else 'sha256:published')
if sys.argv[1:3] == ['image', 'inspect'] and 'sashframe-calendar-sync:' in sys.argv[-1] and os.environ.get('WORKER_MISSING'):
    sys.exit(1)
if 'run' in sys.argv and '--no-build' in sys.argv:
    sys.exit('unknown flag: --no-build')
if 'build' in sys.argv and os.environ.get('BUILD_FAILS'):
    sys.exit(1)
""")
        self.executable("curl", '#!/bin/sh\nprintf \'{"status":"ok"}\\n\'\n')

    def executable(self, name, content):
        target = self.root / "bin" / name
        target.write_text(content)
        target.chmod(0o755)

    def run_script(self, name):
        source = Path(__file__).resolve().parents[1] / "scripts" / name
        target = self.root / "scripts" / name
        shutil.copyfile(source, target)
        shutil.copyfile(source.parent / "pull-release.sh", self.root / "scripts/pull-release.sh")
        return subprocess.run(["bash", str(target)], env=self.env, text=True,
                              capture_output=True, timeout=10, check=True)

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_google_sync_uses_deployed_release_and_explicit_service(self):
        self.run_script("sync-google-calendar.sh")
        commands = self.commands()
        self.assertTrue(commands)
        command = commands[-1]
        self.assertEqual(command["image"], "abcdef12")
        self.assertEqual(command["args"][-6:], ["run", "--pull", "never", "--rm", "--no-deps", "sashframe-calendar-sync"])

    def test_photo_entrypoints_use_cached_deployed_worker(self):
        self.env["SASHFRAME_PHOTOS_DIR"] = str(self.root / "photos")
        self.env["RCLONE_REMOTE"] = ""
        (self.root / "compose.yaml").touch()
        for name in ("process-photos.sh", "sync-photos.sh"):
            with self.subTest(script=name):
                self.run_script(name)
                command = self.commands()[-1]
                self.assertEqual(command["image"], "abcdef12")
                self.assertEqual(command["args"][-5:],
                                 ["run", "--pull", "never", "--rm", "sashframe-photo-processor"])

    def test_google_sync_skips_when_shifter_selected(self):
        self.env["SASHFRAME_CALENDAR_PROVIDER"] = "shifter"
        self.run_script("sync-google-calendar.sh")
        self.assertEqual(self.commands(), [])

    def test_shifter_sync_skips_when_google_selected(self):
        self.run_script("sync-shifter.sh")
        self.assertEqual(self.commands(), [])

    def test_google_sync_honours_environment_file_and_image_override(self):
        self.env["SASHFRAME_CALENDAR_PROVIDER"] = "shifter"
        self.env["IMAGE_TAG"] = "review-build"
        Path(self.env["ENV_FILE"]).write_text("SASHFRAME_CALENDAR_PROVIDER=google\n")
        self.run_script("sync-google-calendar.sh")
        command = self.commands()[-1]
        self.assertEqual(command["image"], "review-build")
        self.assertIn(self.env["ENV_FILE"], command["args"])

    def test_start_reconciles_configuration_even_when_container_is_healthy(self):
        self.run_script("start-app.sh")
        deployments = [command for command in self.commands()
                       if "up" in command["args"] and "sashframe-app" in command["args"]]
        self.assertEqual(len(deployments), 1)
        self.assertEqual(deployments[0]["image"], "abcdef12")

    def test_offline_start_does_not_build_missing_optional_worker(self):
        self.env.update(WORKER_MISSING="1", BUILD_FAILS="1")
        self.run_script("start-app.sh")
        self.assertFalse(any("build" in command["args"] for command in self.commands()))
        self.assertTrue(any("up" in command["args"] for command in self.commands()))

    def configure_update(self):
        self.executable("git", """#!/bin/sh
if [ "$1" = rev-parse ]; then
 case "$2" in origin/main) printf '%s\\n' bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb;; *) printf '%s\\n' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;; esac
fi
""")

    def test_updater_pulls_and_never_builds(self):
        self.configure_update()
        self.run_script("update.sh")
        commands = self.commands()
        self.assertFalse(any("build" in c["args"] for c in commands))
        self.assertTrue(any("ghcr.io/" in " ".join(c["args"]) for c in commands))
        self.assertTrue(any("up" in c["args"] and "--no-build" in c["args"] for c in commands))
        self.assertEqual((self.root / "state/deployed-sha").read_text().strip(), "b" * 40)

    def test_unpublished_release_keeps_accepted_deployment(self):
        self.configure_update()
        self.env["PULL_FAIL"] = "1"
        self.run_script("update.sh")
        self.assertFalse(any("up" in c["args"] or "build" in c["args"] for c in self.commands()))
        self.assertEqual((self.root / "state/deployed-sha").read_text().strip(), "abcdef1234567890")


if __name__ == "__main__":
    unittest.main()
