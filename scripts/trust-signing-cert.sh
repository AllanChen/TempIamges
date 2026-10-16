#!/bin/bash
set -e

# Trusts the "Glance Self-Signed" certificate for code signing and unlocks its
# private key for codesign. Run this ONCE, right after create-signing-cert.sh.
# It needs your Mac password (sudo + keychain), which is why it's a separate,
# interactive step.

CERT_NAME="${GLANCE_SIGN_IDENTITY:-Glance Self-Signed}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CERT_PEM="$(mktemp "${TMPDIR:-/tmp}/glance-cert.XXXXXX")"
trap 'rm -f "$CERT_PEM"' EXIT

echo "==> Exporting the current certificate..."
security find-certificate -c "$CERT_NAME" -p > "$CERT_PEM"

echo "==> Trusting '$CERT_NAME' for code signing (enter your Mac password)..."
sudo security add-trusted-cert -d -r trustRoot \
    -p codeSign \
    -k /Library/Keychains/System.keychain \
    "$CERT_PEM"

echo "==> Allowing codesign to use the private key without prompts..."
bash "$SCRIPT_DIR/configure-signing-key.sh"

echo ""
echo "==> Verifying the code-signing identity is now available:"
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    security find-identity -v -p codesigning | grep "$CERT_NAME"
    echo ""
    echo "Success. Now run ./Glance/build.sh — it will sign with this identity."
else
    echo "Still not listed. Open Keychain Access, find '$CERT_NAME', double-click it,"
    echo "expand Trust, and set 'Code Signing' to 'Always Trust'."
    exit 1
fi
