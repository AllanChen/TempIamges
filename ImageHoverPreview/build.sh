#!/bin/bash
set -e

echo "Building ImageHoverPreview..."

cd "$(dirname "$0")"

if command -v xcodegen > /dev/null 2>&1; then
    xcodegen generate
fi
xcodebuild -project ImageHoverPreview.xcodeproj -scheme ImageHoverPreview -configuration Release build

echo "Build complete. App bundle located at:"
echo "  build/Release/ImageHoverPreview.app"
