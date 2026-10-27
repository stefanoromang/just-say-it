#!/bin/zsh
# Created by Stefano Roman Gunness · MIT License
# Creates a local, self-signed code-signing identity in a private keychain.
# A stable identity lets macOS keep Microphone/Accessibility/Screen permissions across rebuilds.
set -e
KC="$HOME/Library/Keychains/justsayit-signing.keychain-db"
PW="justsayit"
NAME="Just Say It Local Signing"

if [ -f "$KC" ]; then
  security unlock-keychain -p "$PW" "$KC"
  exit 0
fi

TMP=$(mktemp -d)
cat > "$TMP/cfg" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cfg" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" -out "$TMP/id.p12" -passout pass:$PW 2>/dev/null

security create-keychain -p "$PW" "$KC"
security set-keychain-settings "$KC"
security unlock-keychain -p "$PW" "$KC"
security import "$TMP/id.p12" -k "$KC" -P "$PW" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$KC" >/dev/null
rm -rf "$TMP"
echo "Created signing identity: $NAME"
