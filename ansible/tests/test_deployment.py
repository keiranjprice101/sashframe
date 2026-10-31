"""Execute the actual Ansible deployment transaction against fake Docker and HTTP."""
from __future__ import annotations

import getpass
import grp
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest

REPOSITORY = Path(__file__).resolve().parents[2]


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "state").mkdir()
        self.pointer = self.root / "state/deployed-sha"
        self.log = self.root / "docker.log"
        self.tag = self.root / "running-tag"
        self.binary = self.root / "docker"
        self.binary.write_text('''#!/usr/bin/python3
import json, os
from pathlib import Path
root = Path(os.environ['FAKE_DOCKER_ROOT'])
args = __import__('sys').argv[1:]
pointer = root / 'state/deployed-sha'
with (root / 'docker.log').open('a') as log:
    log.write(json.dumps({'args': args, 'tag': os.environ.get('IMAGE_TAG'), 'pointer': pointer.read_text() if pointer.exists() else None}) + '\\n')
if 'up' in args:
    (root / 'running-tag').write_text(os.environ['IMAGE_TAG'])
elif 'stop' in args:
    (root / 'running-tag').unlink(missing_ok=True)
''')
        self.binary.chmod(0o755)
        owner = self

        class HealthHandler(BaseHTTPRequestHandler):
            def do_GET(self):
                tag = owner.tag.read_text() if owner.tag.exists() else ""
                with owner.log.open("a") as log:
                    log.write(json.dumps({"health": tag, "pointer": owner.pointer.read_text() if owner.pointer.exists() else None}) + "\n")
                self.send_response(503 if tag == "bad00001" else 200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"status":"ok"}' if tag != "bad00001" else b'{"status":"failed"}')

            def log_message(self, *args):
                pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), HealthHandler)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)

    def deploy(self, candidate, repeat=False):
        task = {"ansible.builtin.include_tasks": str(REPOSITORY / "ansible/roles/services/tasks/deploy-app.yml")}
        play = [{"hosts": "localhost", "connection": "local", "gather_facts": False, "become": False,
                 "environment": {"PATH": f"{self.root}:{os.environ['PATH']}", "FAKE_DOCKER_ROOT": str(self.root)},
                 "vars": {"sashframe_data_root": str(self.root), "sashframe_config_root": str(self.root),
                          "sashframe_app_dir": str(REPOSITORY), "sashframe_health_url": f"http://127.0.0.1:{self.server.server_port}/health",
                          "sashframe_user": getpass.getuser(), "sashframe_group": grp.getgrgid(os.getgid()).gr_name,
                          "sashframe_env_result": {"changed": False}, "built_images": {"changed": False},
                          "sashframe_required_images": ["sashframe-app", "sashframe-calendar-sync"],
                          "local_git_sha_cmd": {"stdout": candidate}, "sashframe_deployment_health_retries": 1,
                          "sashframe_deployment_health_delay": 0}, "tasks": [task, task, {"ansible.builtin.assert": {"that": ["not sashframe_deployment_required"]}}] if repeat else [task]}]
        playbook = self.root / "test.json"
        playbook.write_text(json.dumps(play))
        result = subprocess.run(["ansible-playbook", "-i", "localhost,", str(playbook)], capture_output=True, text=True)
        return result

    def events(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_health_precedes_promotion_and_second_run_does_not_redeploy(self):
        self.pointer.write_text("old00001abcdef\n")
        result = self.deploy("new00001abcdef", repeat=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        events = self.events()
        self.assertEqual(sum("up" in e.get("args", []) for e in events), 1)
        health = next(e for e in events if "health" in e)
        self.assertEqual(health["pointer"], "old00001abcdef\n")
        promotion = next(i for i, e in enumerate(events) if e.get("args", [""])[0] == "tag")
        self.assertLess(next(i for i, e in enumerate(events) if "health" in e), promotion)
        self.assertEqual(self.pointer.read_text(), "new00001abcdef\n")
        self.assertEqual(self.tag.read_text(), "new00001")

    def test_failed_candidate_restores_previous_image_and_pointer(self):
        self.pointer.write_text("old00001abcdef\n")
        result = self.deploy("bad00001abcdef")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Candidate application deployment failed", result.stdout)
        self.assertEqual(self.pointer.read_text(), "old00001abcdef\n")
        self.assertEqual(self.tag.read_text(), "old00001")
        self.assertFalse(any(e.get("args", [])[:2] == ["tag", "sashframe-app:bad00001"] for e in self.events()))

    def test_failed_first_install_leaves_no_pointer_or_running_candidate(self):
        result = self.deploy("bad00001abcdef")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.pointer.exists())
        self.assertFalse(self.tag.exists())
        self.assertFalse(any(e.get("args", [""])[0] == "tag" for e in self.events()))


class OwnershipTests(unittest.TestCase):
    def test_explicit_uid_and_gid_must_match_created_account(self):
        for variable in ("sashframe_puid", "sashframe_pgid"):
            with self.subTest(variable=variable):
                result = subprocess.run([
                    "ansible-playbook", "-i", "localhost,",
                    str(REPOSITORY / "ansible/tests/calendar-config.yml"),
                    "-e", "sashframe_shifter_drive_folder_id=fixture",
                    "-e", f"{variable}=1000",
                ], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("PUID/PGID overrides must match", result.stdout)


if __name__ == "__main__":
    unittest.main()
