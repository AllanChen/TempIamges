#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
DERIVED_DIR="$ROOT_DIR/DerivedData"
PROJECT_PATH="$ROOT_DIR/GlanceNativeLayout.xcodeproj"
APP_SOURCE="$DERIVED_DIR/Build/Products/Release/Glance Layout.app"
APP_DEST="$ROOT_DIR/Glance Layout.app"

cd "$ROOT_DIR"
xcodegen generate
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme GlanceNativeLayout \
  -configuration Release \
  -derivedDataPath "$DERIVED_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build

ditto "$APP_SOURCE" "$APP_DEST"
open -n "$APP_DEST"
