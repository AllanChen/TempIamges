#!/bin/bash
set -e

# Optional first arg picks the build configuration. Defaults to Release;
# pass "Debug" to enable #if DEBUG paths (debug input window, etc).
CONFIG="${1:-Release}"

echo "Building Glance ($CONFIG)..."

cd "$(dirname "$0")"

if command -v xcodegen > /dev/null 2>&1; then
    xcodegen generate
fi

xcodebuild \
    -project Glance.xcodeproj \
    -scheme Glance \
    -configuration "$CONFIG" \
    -derivedDataPath ./DerivedData \
    build

BUILT_APP=$(find "./debug/$CONFIG" -name "Glance.app" -type d | head -n 1)

if [ -z "$BUILT_APP" ]; then
    BUILT_APP=$(find "./DerivedData/Build/Products/$CONFIG" -name "Glance.app" -type d | head -n 1)
fi

if [ -z "$BUILT_APP" ]; then
    echo "Error: Could not find built Glance.app"
    exit 1
fi

DEST_APP="$(cd .. && pwd)/Glance.app"

[ -d "$DEST_APP" ] && rm -rf "$DEST_APP"

cp -R "$BUILT_APP" "$DEST_APP"

echo ""
echo "Build complete!"
echo "  Released: $DEST_APP"
