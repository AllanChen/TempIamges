#!/bin/bash
set -e

echo "Building ImageHoverPreview..."

cd "$(dirname "$0")"

if command -v xcodegen > /dev/null 2>&1; then
    xcodegen generate
fi

xcodebuild \
    -project ImageHoverPreview.xcodeproj \
    -scheme ImageHoverPreview \
    -configuration Release \
    -derivedDataPath ./DerivedData \
    build

BUILT_APP=$(find ./DerivedData -name "ImageHoverPreview.app" -type d | head -n 1)

if [ -z "$BUILT_APP" ]; then
    echo "Error: Could not find built ImageHoverPreview.app"
    exit 1
fi

DEST_APP="$(cd .. && pwd)/ImageHoverPreview.app"

[ -d "$DEST_APP" ] && rm -rf "$DEST_APP"

cp -R "$BUILT_APP" "$DEST_APP"

echo ""
echo "Build complete!"
echo "  Released: $DEST_APP"
