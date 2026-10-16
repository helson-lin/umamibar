"""Exercise the publication gate without Apple credentials or network access."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NotarizationTests(unittest.TestCase):
    def run_notary(self, status):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            log = folder / 'calls'
            xcrun = folder / 'xcrun'
            xcrun.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$CALL_LOG"
if [[ "$1 $2" == 'notarytool submit' ]]; then
  printf '{"id":"test-id","status":"%s"}\\n' "$TEST_STATUS"
fi
''')
            xcrun.chmod(0o755)
            result = subprocess.run(['bash', str(ROOT / 'scripts/notarize.sh'), 'upload.zip', 'app.app'],
                env={**os.environ, 'PATH': directory + os.pathsep + os.environ['PATH'],
                     'CALL_LOG': str(log), 'TEST_STATUS': status,
                     'NOTARY_PROFILE': 'test-profile', 'SIGNING_KEYCHAIN': '/tmp/test.keychain'},
                capture_output=True, text=True)
            return result, log.read_text()

    def test_accepted_submission_is_stapled_and_validated(self):
        result, calls = self.run_notary('Accepted')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--keychain /tmp/test.keychain', calls)
        self.assertLess(calls.index('notarytool submit'), calls.index('stapler staple app.app'))
        self.assertIn('stapler validate app.app', calls)

    def test_rejected_or_pending_submission_never_staples(self):
        for status in ['Invalid', 'In Progress']:
            with self.subTest(status=status):
                result, calls = self.run_notary(status)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('notarytool log test-id', calls)
                self.assertNotIn('stapler', calls)
