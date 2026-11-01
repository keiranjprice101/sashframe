"""Exercise release downloads, local alias migration, and pull failure behavior."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class ReleasePullTests(unittest.TestCase):
    def test_pull_verify_alias_and_repeat_without_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / 'state.json'
            log = root / 'commands'
            binary = root / 'docker'
            binary.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
p=Path(os.environ['IMAGE_STATE'])
a=json.loads(p.read_text()) if p.exists() else {}
args=sys.argv[1:]
with open(os.environ['IMAGE_LOG'],'a') as log: log.write(json.dumps(args)+'\\n')
if args[0]=='pull':
 if os.environ.get('PULL_FAIL'): sys.exit(1)
 a[args[-1]]='sha256:published'
elif args[:2]==['image','inspect']:
 name=args[-1]
 if name not in a: sys.exit(1)
 if '--format' in args:
  print(os.environ.get('IMAGE_PLATFORM','linux/arm64') if 'Architecture' in args[args.index('--format')+1] else a[name])
elif args[0]=='tag': a[args[-1]]=a[args[-2]]
p.write_text(json.dumps(a))
''')
            binary.chmod(0o755)
            env = dict(os.environ, PATH=f'{root}:{os.environ["PATH"]}', IMAGE_STATE=str(state), IMAGE_LOG=str(log))
            script = Path(__file__).resolve().parents[1] / 'scripts/pull-release.sh'
            sha = 'a' * 40
            command = ['bash', str(script), sha, 'sashframe-app']
            first = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertIn('Prepared image:', first.stdout)
            self.assertEqual(json.loads(state.read_text())['sashframe-app:aaaaaaaa'], 'sha256:published')
            second = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertNotIn('Prepared image:', second.stdout)
            commands = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual(sum(c[0] == 'pull' for c in commands), 1)
            self.assertIn(['pull', '--platform', 'linux/arm64', f'ghcr.io/keiranjprice101/sashframe-app:sha-{sha}'], commands)
            failed = subprocess.run(['bash', str(script), 'b' * 40, 'sashframe-app'], env=dict(env, PULL_FAIL='1'), capture_output=True, text=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn('GitHub Actions', failed.stderr)
            self.assertNotIn('sashframe-app:bbbbbbbb', json.loads(state.read_text()))
            wrong_arch = subprocess.run(command, env=dict(env, IMAGE_PLATFORM='linux/amd64'), capture_output=True, text=True)
            self.assertNotEqual(wrong_arch.returncode, 0)
            self.assertIn('Unexpected image platform', wrong_arch.stderr)


if __name__ == '__main__':
    unittest.main()
