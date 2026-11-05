#!/bin/bash
set -e

# Daily builds are for local testing. Release must be requested explicitly.
CONFIG="${1:-Debug}"
case "$CONFIG" in Debug|Release) ;; *) echo "Expected Debug or Release"; exit 1 ;; esac
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Building Glance ($CONFIG)..."

cd "$SCRIPT_DIR"

# TCC grants are tied to the app's designated code requirement, not only its
# bundle identifier. Never publish an ad-hoc build: its CDHash changes whenever
# the binary changes, so Accessibility and Input Monitoring are revoked.
REQUESTED_SIGN_IDENTITY="${GLANCE_SIGN_IDENTITY:-Glance Self-Signed}"
ALLOW_ADHOC="${GLANCE_ALLOW_ADHOC:-0}"
# Sign by the certificate SHA-1 hash, not the name. The keychain can hold two
# entries with the same friendly name (e.g. cert created twice), which makes
# `codesign --sign "<name>"` fail with "ambiguous". The hash is unique.
SIGN_IDENTITY="$(security find-identity -v -p codesigning \
    | grep -F "\"$REQUESTED_SIGN_IDENTITY\"" \
    | head -n 1 \
    | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+([0-9A-F]+).*/\1/')"
if [ -z "$SIGN_IDENTITY" ]; then
    if [ "$ALLOW_ADHOC" = "1" ] && [ "$CONFIG" = "Debug" ]; then
        SIGN_IDENTITY="-"
        echo "Warning: '$REQUESTED_SIGN_IDENTITY' is unavailable; using ad-hoc Debug signing."
    else
        echo "Error: Glance signing identity '$REQUESTED_SIGN_IDENTITY' is not available."
        echo "Run $PROJECT_ROOT/scripts/create-signing-cert.sh once, then rebuild."
        exit 1
    fi
fi

if command -v xcodegen > /dev/null 2>&1; then
    xcodegen generate
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
ENTITLEMENTS="$SCRIPT_DIR/Glance.entitlements"
if [ "$CONFIG" = Debug ]; then ENTITLEMENTS="$SCRIPT_DIR/Glance.Debug.entitlements"; fi
# Local self-signed identities have no Apple Team ID. Even frameworks signed
# with that same certificate cannot pass hardened-runtime library validation.
# Keep this exception out of Developer ID Release builds and their source plist.
if [ "$CONFIG" = Release ] && { [ "$REQUESTED_SIGN_IDENTITY" = "Glance Self-Signed" ] || [ "$SIGN_IDENTITY" = "-" ]; }; then
    LOCAL_ENTITLEMENTS="$(mktemp "${TMPDIR:-/tmp}/glance-local-entitlements.XXXXXX")"
    trap 'rm -f "$LOCAL_ENTITLEMENTS"' EXIT
    cp "$ENTITLEMENTS" "$LOCAL_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c 'Add :com.apple.security.cs.disable-library-validation bool true' "$LOCAL_ENTITLEMENTS"
    ENTITLEMENTS="$LOCAL_ENTITLEMENTS"
    echo "  Local self-signed build: enabling framework loading without an Apple Team ID."
fi
SIGN_TIMESTAMP_ARGS=(--timestamp=none)
if [[ "$REQUESTED_SIGN_IDENTITY" == "Developer ID Application:"* ]]; then
    SIGN_TIMESTAMP_ARGS=(--timestamp)
fi
# Sign embedded framework helpers from the inside out, preserving symlinks.
# Sparkle ships nested XPC services and apps; --deep alone is insufficient.
if [ -d "$DEST_APP/Contents/Frameworks" ]; then
    while IFS= read -r -d '' binary; do
        if file "$binary" | grep -q 'Mach-O'; then
            codesign --force --sign "$SIGN_IDENTITY" --options runtime --preserve-metadata=entitlements "${SIGN_TIMESTAMP_ARGS[@]}" "$binary"
        fi
    done < <(find "$DEST_APP/Contents/Frameworks" -type f -print0)
    while IFS= read -r -d '' bundle; do
        codesign --force --sign "$SIGN_IDENTITY" --options runtime --preserve-metadata=entitlements "${SIGN_TIMESTAMP_ARGS[@]}" "$bundle"
    done < <(find "$DEST_APP/Contents/Frameworks" -depth -type d \( -name '*.xpc' -o -name '*.app' -o -name '*.framework' \) -print0)
fi
codesign --force \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    "${SIGN_TIMESTAMP_ARGS[@]}" \
    "$DEST_APP"
codesign --verify --deep --strict "$DEST_APP"

SIGNATURE_INFO="$(codesign -dvv "$DEST_APP" 2>&1)"
if [ "$ALLOW_ADHOC" != "1" ] && printf '%s\n' "$SIGNATURE_INFO" | grep -q '^Signature=adhoc$'; then
    echo "Error: final Glance.app is not signed with a persistent identity."
    exit 1
fi
if [ "$ALLOW_ADHOC" != "1" ] && ! printf '%s\n' "$SIGNATURE_INFO" | grep -q '^Authority='; then
    echo "Error: final Glance.app has no certificate authority in its signature."
    exit 1
fi
if [ "$ALLOW_ADHOC" = "1" ]; then
    echo "  Debug ad-hoc signature verified (permissions may need re-authorization)."
else
    echo "  Signature verified with: $REQUESTED_SIGN_IDENTITY"
fi

echo ""
echo "Build complete!"
echo "  Local build ($CONFIG): $DEST_APP"

# Optional: GLANCE_DMG=1 also packs the signed bundle into dist/Glance-<version>.dmg
# with an Applications shortcut. Until the app is notarized with a Developer ID,
# Gatekeeper blocks first launch; docs/installation.md tells users how to allow it.
if [ "${GLANCE_DMG:-0}" = "1" ]; then
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST_APP/Contents/Info.plist")"
    DIST_DIR="$PROJECT_ROOT/dist"
    DMG_PATH="$DIST_DIR/Glance-$VERSION.dmg"
    STAGING="$(mktemp -d "${TMPDIR:-/tmp}/glance-dmg.XXXXXX")"
    mkdir -p "$DIST_DIR"
    rm -f "$DMG_PATH"
    cp -R "$DEST_APP" "$STAGING/Glance.app"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -quiet -volname "Glance $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
    rm -rf "$STAGING"
    echo "  DMG: $DMG_PATH"
fi
