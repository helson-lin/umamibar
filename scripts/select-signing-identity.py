#!/usr/bin/env python3
"""Select only a valid Developer ID Application identity for the configured team."""
import os
import re
import subprocess
import sys

keychain = os.environ['SIGNING_KEYCHAIN']
team = os.environ['APPLE_TEAM_ID'].strip()
result = subprocess.run(['security', 'find-identity', '-v', '-p', 'codesigning', keychain],
                        check=True, capture_output=True, text=True)
identities = re.findall(r'\b([A-Fa-f0-9]{40}) "([^"]+)"', result.stdout)
matches = [(fingerprint, name) for fingerprint, name in identities
           if name.startswith('Developer ID Application:') and name.endswith(f'({team})')]
configured = os.environ.get('SIGNING_IDENTITY', '').strip().strip('"')
selected = [fingerprint for fingerprint, name in matches if configured in (fingerprint, name)]
if not selected and len(matches) == 1:
    selected = [matches[0][0]]
if len(selected) != 1:
    print(f'::error::Found {len(matches)} valid Developer ID Application identities for the configured team '
          f'({len(identities)} valid code-signing identities total). '
          'Export a Developer ID Application certificate WITH its private key; check expiry, team ID, '
          'and MACOS_SIGNING_IDENTITY. Apple Development/Distribution certificates cannot be used.', file=sys.stderr)
    sys.exit(1)
print(f'::add-mask::{selected[0]}')
with open(os.environ['GITHUB_ENV'], 'a') as output:
    output.write(f'SIGNING_IDENTITY={selected[0]}\n')
print('Selected a valid Developer ID Application identity matching the configured team.')
