#!/bin/bash
set -e

APP_NAME="ImageHoverPreview"
APP_PATH="$(cd "$(dirname "$0")" && pwd)/$APP_NAME.app"
LOG_FILE="$HOME/Library/Application Support/$APP_NAME/app.log"

echo "Killing any running $APP_NAME instances..."
pkill -x "$APP_NAME" 2>/dev/null && sleep 0.3 || true

if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH not found. Run ./ImageHoverPreview/build.sh first."
    exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

echo "Launching $APP_PATH ..."
open "$APP_PATH"

echo "Tailing $LOG_FILE (Ctrl+C to stop)"
echo "---"
exec tail -F "$LOG_FILE"
