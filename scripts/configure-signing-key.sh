#!/bin/bash
# Run explicitly during signing setup, never on every build.
set +x
set -euo pipefail

CERT_NAME="${GLANCE_SIGN_IDENTITY:-Glance Self-Signed}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if ! { exec 3<>/dev/tty; } 2>/dev/null; then
    echo "Error: open a local terminal and run bash scripts/configure-signing-key.sh." >&2
    exit 1
fi

KEYCHAIN_PASSWORD=""
trap 'unset KEYCHAIN_PASSWORD; exec 3>&-' EXIT
printf 'Login keychain password (hidden; used only for local signing setup): ' >&3
IFS= read -r -s KEYCHAIN_PASSWORD <&3
printf '\n' >&3

if ! security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Error: could not unlock the login keychain. Signing access was not configured." >&2
    exit 1
fi

# Scope the change to Glance signing private keys, not every key in login.
# Never hide a failed configuration behind a success message.
if ! security set-key-partition-list -l "$CERT_NAME" -t private -s \
    -S apple-tool:,apple:,codesign: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Error: could not authorize the '$CERT_NAME' private key. Check its label in Keychain Access." >&2
    exit 1
fi
unset KEYCHAIN_PASSWORD
echo "Configured codesign access for '$CERT_NAME'."
