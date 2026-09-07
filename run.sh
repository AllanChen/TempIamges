#!/bin/bash
set -e

APP_NAME="Glance"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$ROOT_DIR/$APP_NAME.app"
BUILD_SCRIPT="$ROOT_DIR/Glance/build.sh"
SIGNING_SETUP_SCRIPT="$ROOT_DIR/scripts/create-signing-cert.sh"
SIGN_IDENTITY="${GLANCE_SIGN_IDENTITY:-Glance Self-Signed}"
LOG_FILE="$HOME/Library/Application Support/$APP_NAME/app.log"

echo "Killing any running $APP_NAME instances..."
pkill -x "$APP_NAME" 2>/dev/null && sleep 0.3 || true

if [ ! -x "$BUILD_SCRIPT" ]; then
    echo "Error: $BUILD_SCRIPT is missing or not executable."
    exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGN_IDENTITY\""; then
    if [ ! -x "$SIGNING_SETUP_SCRIPT" ]; then
        echo "Error: signing identity '$SIGN_IDENTITY' is missing and setup script was not found."
        exit 1
    fi
    echo "Signing identity '$SIGN_IDENTITY' is missing."
    echo "Running one-time Glance signing setup..."
    "$SIGNING_SETUP_SCRIPT"
fi

echo "Building $APP_NAME..."
"$BUILD_SCRIPT" "$@"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: build completed but $APP_PATH was not created."
    exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

echo "Launching $APP_PATH ..."
# -n forces a NEW instance of THIS bundle path (there are copies in DerivedData
# and the repo root; without -n, LaunchServices may reuse/registration-match the
# wrong one and nothing appears). -a targets the exact app we just built.
open -n -a "$APP_PATH"

echo "Tailing $LOG_FILE (Ctrl+C to stop)"
echo "---"
exec tail -F "$LOG_FILE"
