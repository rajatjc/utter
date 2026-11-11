#!/bin/bash
# Creates a self-signed code-signing certificate named "Utter Dev" in your login
# keychain. build.sh signs with it automatically when it exists, which keeps the
# Accessibility permission across rebuilds (ad-hoc signatures change every build).
#
# macOS will show one or two password dialogs while this runs: approve them.
# The first time you build afterwards, codesign may ask to use the key: choose
# "Always Allow".
set -euo pipefail

NAME="${1:-Utter Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
    echo "Certificate \"$NAME\" already exists."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
subjectKeyIdentifier = hash
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout pass:utter -name "$NAME"

# Import the key + cert, letting codesign use the key.
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P utter -T /usr/bin/codesign -T /usr/bin/security >/dev/null
# Trust it for code signing (this is the step that asks for your password).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
    echo "Created \"$NAME\". build.sh will now sign with it."
else
    echo "The certificate was imported but isn't showing as a valid signing identity yet."
    echo "Open Keychain Access, find \"$NAME\" under My Certificates, and set Code Signing to Always Trust."
    exit 1
fi
