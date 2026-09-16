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
    if ! "$SIGNING_SETUP_SCRIPT"; then
        echo "Warning: signing setup failed; continuing with a local Debug ad-hoc build."
        echo "Stable Accessibility/Input Monitoring permissions require fixing the Keychain later."
        export GLANCE_ALLOW_ADHOC=1
    fi
fi

if [ "${GLANCE_ALLOW_ADHOC:-0}" = "1" ] && [ "${1:-Release}" != "Debug" ]; then
    echo "Using Debug configuration for the ad-hoc fallback."
    set -- Debug
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
# Pass the bundle path directly to LaunchServices. Using `open -a <path>` can
# resolve through the app registry and reuse another Glance.app copy (for
# example one in DerivedData or /Applications), which makes a successful build
# appear to have no UI changes. `-n <path>` always launches this exact bundle.
open -n "$APP_PATH"

echo "Tailing $LOG_FILE (Ctrl+C to stop)"
echo "---"
exec tail -F "$LOG_FILE"
