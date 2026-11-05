#!/bin/zsh
set -e
cd "$(dirname "$0")"
pkill -x GlanceMacOSPreview 2>/dev/null || true
swift build
APP_ROOT=".build/arm64-apple-macosx/debug/GlanceMacOSPreview.app"
mkdir -p "$APP_ROOT/Contents/MacOS" "$APP_ROOT/Contents/Resources"
cp -f ".build/arm64-apple-macosx/debug/GlanceMacOSPreview" "$APP_ROOT/Contents/MacOS/GlanceMacOSPreview"
cp -f "Info.plist" "$APP_ROOT/Contents/Info.plist"
open -n "$APP_ROOT"
osascript -e 'tell application "GlanceMacOSPreview" to activate'
