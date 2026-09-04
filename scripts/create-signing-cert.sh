#!/bin/bash
set -e

# Creates a *stable* self-signed code-signing certificate for Glance and imports
# it into the login keychain. Run this ONCE. After that, build.sh signs every
# build with this fixed identity, so macOS keeps remembering the Accessibility /
# Input Monitoring permissions across rebuilds instead of asking every time.
#
# Why this fixes the re-authorization pain:
#   TCC (the permissions database) keys grants on the app's *code signature
#   identity*. Ad-hoc signing (CODE_SIGN_IDENTITY "-") mints a new identity on
#   every build, so macOS treats each build as a brand-new app and wipes the
#   grant. A persistent certificate keeps the identity constant.

CERT_NAME="Glance Self-Signed"

echo "==> Checking for an existing '$CERT_NAME' identity..."
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "    Already present. Nothing to do."
    security find-identity -v -p codesigning | grep "$CERT_NAME"
    exit 0
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

KEY="$WORKDIR/glance.key"
CRT="$WORKDIR/glance.crt"
P12="$WORKDIR/glance.p12"
CONFIG="$WORKDIR/glance.cnf"
# Random throwaway password for the intermediate .p12 (only used to move the
# key+cert into the keychain in one atomic import).
P12_PASS="$(openssl rand -hex 12)"

# x509 v3 config: the codeSigning EKU is what makes codesign accept the identity.
cat > "$CONFIG" <<EOF
[ req ]
distinguished_name = dn
x509_extensions    = v3
prompt             = no

[ dn ]
CN = $CERT_NAME

[ v3 ]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
EOF

echo "==> Generating self-signed certificate (valid 10 years)..."
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$KEY" -out "$CRT" \
    -days 3650 -sha256 \
    -config "$CONFIG" >/dev/null 2>&1

# -legacy makes OpenSSL 3.x emit a PKCS#12 that macOS's Security framework can
# fully parse (private key included). Without it, `security import` may drop the
# key and you get a certificate with no matching identity.
openssl pkcs12 -export -legacy \
    -inkey "$KEY" -in "$CRT" \
    -out "$P12" -name "$CERT_NAME" \
    -passout "pass:$P12_PASS" >/dev/null 2>&1 \
  || openssl pkcs12 -export \
    -inkey "$KEY" -in "$CRT" \
    -out "$P12" -name "$CERT_NAME" \
    -passout "pass:$P12_PASS" >/dev/null 2>&1

echo "==> Importing into the login keychain (key + certificate)..."
# -T /usr/bin/codesign lets codesign use the key without an interactive prompt.
security import "$P12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$P12_PASS" \
    -T /usr/bin/codesign \
    -T /usr/bin/security

# Trust the cert for code signing so codesign/Gatekeeper accept it locally.
echo "==> Adding the certificate to the trust store (may prompt for your password)..."
sudo security add-trusted-cert -d -r trustRoot \
    -p codeSign \
    -k /Library/Keychains/System.keychain \
    "$CRT" >/dev/null 2>&1 || \
    echo "    (Trust step skipped/failed — local signing still works for TCC persistence.)"

# Allow codesign to access the private key without a keychain prompt on each use.
security set-key-partition-list \
    -S apple-tool:,apple: \
    -k "" \
    "$HOME/Library/Keychains/login.keychain-db" \
    >/dev/null 2>&1 || true

echo ""
echo "Done. Available signing identity:"
security find-identity -v -p codesigning | grep "$CERT_NAME" || {
    echo "ERROR: identity not found after import." >&2
    exit 1
}
echo ""
echo "Next: run ./Glance/build.sh — it will sign with '$CERT_NAME'."
echo "You'll grant Accessibility/Input Monitoring ONE more time, then it sticks."
