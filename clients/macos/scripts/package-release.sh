#!/bin/bash
# Package an already-built Developer ID app. Does not build or launch Glance.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
APP="${1:?Usage: package-release.sh /path/to/Glance.app}"
: "${GLANCE_NOTARY_PROFILE:?Set the notarytool keychain profile}"
: "${GLANCE_SIGN_IDENTITY:?Set the Developer ID Application identity}"
: "${SPARKLE_BIN:?Set the directory containing generate_appcast and sign_update}"
KEY="${GLANCE_UPDATE_KEY_FILE:-$ROOT/infomation/sparkle-update-key.txt}"
[[ "$GLANCE_SIGN_IDENTITY" == "Developer ID Application:"* ]] || { echo 'Developer ID required'; exit 1; }
[[ -f "$KEY" && -x "$SPARKLE_BIN/generate_appcast" ]] || { echo 'Update signing tools/key missing'; exit 1; }
codesign --verify --deep --strict "$APP"
SIGNATURE_INFO="$(codesign -dvv "$APP" 2>&1)"
grep -q '^Authority=Developer ID Application:' <<< "$SIGNATURE_INFO" || { echo 'App is not Developer ID signed'; exit 1; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/glance-release.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
codesign -d --entitlements :- "$APP" > "$TMP/entitlements.plist" 2>/dev/null
python3 - "$TMP/entitlements.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'rb') as f:d=plistlib.load(f)
assert not d.get('com.apple.security.get-task-allow'), 'Release contains debug entitlement'
assert not d.get('com.apple.security.cs.disable-library-validation'), 'Release disables library validation'
PY
# Refuse a stale app built before signed updates were configured.
python3 - "$APP/Contents/Info.plist" "$ROOT/clients/macos/Glance/Info.plist" <<'PYINFO'
import plistlib,sys
with open(sys.argv[1],'rb') as f: app=plistlib.load(f)
with open(sys.argv[2],'rb') as f: expected=plistlib.load(f)
for key in ('SUFeedURL','SUPublicEDKey','SURequireSignedFeed','SUVerifyUpdateBeforeExtraction'):
    assert app.get(key)==expected.get(key) and app.get(key), 'Update configuration mismatch: '+key
PYINFO
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$VERSION" =~ ^[A-Za-z0-9._-]+$ ]] || exit 1
OUT="$ROOT/clients/macos/dist/updates"
mkdir -p "$OUT"
DMG="$OUT/Glance-$VERSION.dmg"
[[ ! -e "$DMG" ]] || { echo 'Version archive already exists; increment version instead of replacing it'; exit 1; }
# Poll the existing submission across transient network failures. Never resubmit
# merely because the connection used to wait for Apple's result timed out.
wait_for_notarization() {
    local submission="$1" status failures=0
    while true; do
        if xcrun notarytool info "$submission" --keychain-profile "$GLANCE_NOTARY_PROFILE" --output-format json > "$TMP/status.json"; then
            failures=0
            status="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$TMP/status.json")"
            echo "Notarization $submission: $status"
            case "$status" in
                Accepted) return 0 ;;
                'In Progress') ;;
                *)
                    xcrun notarytool log "$submission" --keychain-profile "$GLANCE_NOTARY_PROFILE" || true
                    echo "Notarization did not succeed; stopping before packaging."
                    return 1 ;;
            esac
        else
            failures=$((failures + 1))
            echo "Status query failed ($failures/10); retaining submission $submission."
            [[ "$failures" -lt 10 ]] || return 1
        fi
        sleep 60
    done
}
submit_for_notarization() {
    xcrun notarytool submit "$1" --keychain-profile "$GLANCE_NOTARY_PROFILE" --output-format json > "$TMP/submission.json"
    cat "$TMP/submission.json"
    SUBMISSION_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$TMP/submission.json")"
}
if [[ -n "${GLANCE_APP_NOTARY_SUBMISSION:-}" ]]; then
    SUBMISSION_ID="$GLANCE_APP_NOTARY_SUBMISSION"
    echo "Resuming App notarization: $SUBMISSION_ID"
else
    ditto -c -k --keepParent "$APP" "$TMP/Glance.zip"
    submit_for_notarization "$TMP/Glance.zip"
fi
wait_for_notarization "$SUBMISSION_ID"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
mkdir "$TMP/disk"
ditto "$APP" "$TMP/disk/Glance.app"
ln -s /Applications "$TMP/disk/Applications"
hdiutil create -quiet -volname "Glance $VERSION" -srcfolder "$TMP/disk" -format UDZO "$DMG"
codesign --sign "$GLANCE_SIGN_IDENTITY" --timestamp "$DMG"
submit_for_notarization "$DMG"
wait_for_notarization "$SUBMISSION_ID"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
"$SPARKLE_BIN/generate_appcast" --ed-key-file "$KEY" --download-url-prefix https://glancepreview.com/updates/ "$OUT"
"$SPARKLE_BIN/sign_update" --verify --ed-key-file "$KEY" "$OUT/appcast.xml"
shasum -a 256 "$DMG" > "$DMG.sha256"
echo "Verified release files ready in $OUT. Publish archives before appcast.xml."
