#!/bin/bash
set -euo pipefail
# Submit a ZIP/DMG, then staple its app/DMG only after explicit acceptance.
: "${NOTARY_PROFILE:?Notarytool keychain profile required}"
UPLOAD="${1:?Upload path required}"
TARGET="${2:?Staple target required}"
AUTH=(--keychain-profile "$NOTARY_PROFILE")
if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then AUTH+=(--keychain "$SIGNING_KEYCHAIN"); fi
RESULT="$(mktemp "${TMPDIR:-/tmp}/umamibar-notary.XXXXXX")"
trap 'rm -f "$RESULT"' EXIT
submission_exit=0
xcrun notarytool submit "$UPLOAD" "${AUTH[@]}" --wait --timeout 20m --output-format json > "$RESULT" || submission_exit=$?
if ! python3 - "$RESULT" <<'PY'
import json, sys
with open(sys.argv[1]) as result:
    data = json.load(result)
print('Notarization:', data.get('id'), data.get('status'))
sys.exit(0 if data.get('status') == 'Accepted' else 1)
PY
then
  ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id", ""))' "$RESULT" 2>/dev/null || true)"
  if [[ -n "$ID" ]]; then xcrun notarytool log "$ID" "${AUTH[@]}" || true; fi
  echo 'Apple notarization was not accepted; refusing to package/publish.' >&2
  exit 1
fi
if [[ "$submission_exit" != 0 ]]; then exit "$submission_exit"; fi
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
