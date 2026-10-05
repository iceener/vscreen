#!/bin/bash
# Sign a bundle or binary with vscreen's stable self-signed identity.
# The identity lives in a dedicated keychain under ~/Library/Application Support/vscreen/signing.
# It is created on first use. The login keychain and the keychain search list are left unchanged.
#
# Usage: scripts/sign.sh <path> [identifier]
set -euo pipefail

TARGET="${1:?usage: scripts/sign.sh <path> [identifier]}"
IDENT="${2:-}"
DIR="${VSCREEN_SIGNING_DIR:-$HOME/Library/Application Support/vscreen/signing}"
KC="$DIR/vscreen-signing.keychain-db"
PASS_FILE="$DIR/keychain-password"
CERT="$DIR/cert.pem"
CN="vscreen local code signing"
OPENSSL=/usr/bin/openssl

user_search_list() {
  security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//'
}

create_identity() {
  mkdir -p "$DIR"
  chmod 700 "$DIR"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  (umask 077 && "$OPENSSL" rand -hex 24 > "$PASS_FILE")
  local pass
  pass="$(cat "$PASS_FILE")"
  cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $CN
[ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
  "$OPENSSL" req -new -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/cert.cnf" 2>/dev/null
  "$OPENSSL" pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -out "$tmp/id.p12" -passout "pass:$pass"

  # create-keychain adds the new keychain to the user search list; put the list back.
  local saved=()
  while IFS= read -r line; do saved+=("$line"); done < <(user_search_list)
  security create-keychain -p "$pass" "$KC"
  security list-keychains -d user -s "${saved[@]}"

  security set-keychain-settings "$KC"
  security unlock-keychain -p "$pass" "$KC"
  security import "$tmp/id.p12" -k "$KC" -P "$pass" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$pass" "$KC" >/dev/null
  cp "$tmp/cert.pem" "$CERT"
  echo "created signing identity in $KC" >&2
}

[ -f "$KC" ] || create_identity

HASH="$("$OPENSSL" x509 -in "$CERT" -noout -fingerprint -sha1 | sed -e 's/.*=//' -e 's/://g')"
security unlock-keychain -p "$(cat "$PASS_FILE")" "$KC"

# codesign finds the identity only through the user search list, so add the signing
# keychain for this one call and restore the exact previous list afterwards.
SAVED=()
while IFS= read -r line; do SAVED+=("$line"); done < <(user_search_list)
restore_search_list() { security list-keychains -d user -s "${SAVED[@]}"; }
trap restore_search_list EXIT
security list-keychains -d user -s "${SAVED[@]}" "$KC"

args=(--force --sign "$HASH" --keychain "$KC" --timestamp=none)
[ -n "$IDENT" ] && args+=(--identifier "$IDENT")
codesign "${args[@]}" "$TARGET"
