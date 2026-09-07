#!/bin/bash
set -e

# Optional first arg picks the build configuration. Defaults to Release;
# pass "Debug" to enable #if DEBUG paths (debug input window, etc).
CONFIG="${1:-Release}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Building Glance ($CONFIG)..."

cd "$SCRIPT_DIR"

# TCC grants are tied to the app's designated code requirement, not only its
# bundle identifier. Never publish an ad-hoc build: its CDHash changes whenever
# the binary changes, so Accessibility and Input Monitoring are revoked.
REQUESTED_SIGN_IDENTITY="${GLANCE_SIGN_IDENTITY:-Glance Self-Signed}"
# Sign by the certificate SHA-1 hash, not the name. The keychain can hold two
# entries with the same friendly name (e.g. cert created twice), which makes
# `codesign --sign "<name>"` fail with "ambiguous". The hash is unique.
SIGN_IDENTITY="$(security find-identity -v -p codesigning \
    | grep -F "\"$REQUESTED_SIGN_IDENTITY\"" \
    | head -n 1 \
    | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+([0-9A-F]+).*/\1/')"
if [ -z "$SIGN_IDENTITY" ]; then
    echo "Error: Glance signing identity '$REQUESTED_SIGN_IDENTITY' is not available."
    echo "Run $PROJECT_ROOT/scripts/create-signing-cert.sh once, then rebuild."
    exit 1
fi

if command -v xcodegen > /dev/null 2>&1; then
    xcodegen generate
    # Ensure the project defaults to Release so that auto-generated schemes
    # and any tool falling back to project defaults build a release binary.
    sed -i '' 's/defaultConfigurationName = Debug;/defaultConfigurationName = Release;/g' Glance.xcodeproj/project.pbxproj
fi

xcodebuild \
    -project Glance.xcodeproj \
    -scheme Glance \
    -configuration "$CONFIG" \
    -derivedDataPath ./DerivedData \
    build

BUILT_APP=$(find "./DerivedData/Build/Products/$CONFIG" -name "Glance.app" -type d | head -n 1)

if [ -z "$BUILT_APP" ]; then
    BUILT_APP=$(find "./debug/$CONFIG" -name "Glance.app" -type d | head -n 1)
fi

if [ -z "$BUILT_APP" ]; then
    echo "Error: Could not find built Glance.app"
    exit 1
fi

if [ -d "./Resources" ]; then
    mkdir -p "$BUILT_APP/Contents/Resources"
    cp -R ./Resources/* "$BUILT_APP/Contents/Resources/"
fi

rm -rf "$BUILT_APP/Contents/Resources/Resources"
rm -rf "$BUILT_APP/Contents/Resources/Assets.xcassets"

if [ -d "./Resources/Assets.xcassets" ]; then
    mkdir -p "$BUILT_APP/Contents/Resources"
    ASSETS_CAR="$BUILT_APP/Contents/Resources/Assets.car"
    xcrun actool \
        --output-format human-readable-text \
        --notices --warnings \
        --platform macosx \
        --minimum-deployment-target 12.3 \
        --target-device mac \
        --app-icon AppIcon \
        --development-region en \
        --enable-on-demand-resources NO \
        --output-partial-info-plist "$BUILT_APP/Contents/Resources/partial.plist" \
        --compile "$BUILT_APP/Contents/Resources" \
        "./Resources/Assets.xcassets" \
        > /dev/null 2>&1
    if [ -f "$ASSETS_CAR" ]; then
        echo "  Compiled Assets.car"
        rm -f "$BUILT_APP/Contents/Resources/partial.plist"
    else
        echo "  Warning: actool failed to compile Assets.car"
    fi
fi

DEST_APP="$PROJECT_ROOT/Glance.app"

[ -d "$DEST_APP" ] && rm -rf "$DEST_APP"

cp -R "$BUILT_APP" "$DEST_APP"

# Re-sign the final copied bundle because resource post-processing above
# invalidates the signature produced by xcodebuild.
echo "Signing with stable identity: $REQUESTED_SIGN_IDENTITY ($SIGN_IDENTITY)"
codesign --force --deep \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$SCRIPT_DIR/Glance.entitlements" \
    --options runtime \
    "$DEST_APP"
codesign --verify --deep --strict "$DEST_APP"

SIGNATURE_INFO="$(codesign -dvv "$DEST_APP" 2>&1)"
if printf '%s\n' "$SIGNATURE_INFO" | grep -q '^Signature=adhoc$'; then
    echo "Error: final Glance.app is not signed with a persistent identity."
    exit 1
fi
if ! printf '%s\n' "$SIGNATURE_INFO" | grep -q '^Authority='; then
    echo "Error: final Glance.app has no certificate authority in its signature."
    exit 1
fi
echo "  Signature verified with: $REQUESTED_SIGN_IDENTITY"

echo ""
echo "Build complete!"
echo "  Released: $DEST_APP"
