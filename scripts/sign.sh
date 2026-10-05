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
  # EXIT, not RETURN: a RETURN trap does not run when errexit ends the script, and $tmp holds the key.
  trap "rm -rf '$tmp'" EXIT
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
  # ${a[@]+...}: bash 3.2 under set -u treats an empty array as unbound.
  security list-keychains -d user -s ${saved[@]+"${saved[@]}"}

  security set-keychain-settings "$KC"
  security unlock-keychain -p "$pass" "$KC"
  security import "$tmp/id.p12" -k "$KC" -P "$pass" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$pass" "$KC" >/dev/null
  cp "$tmp/cert.pem" "$CERT"
  rm -rf "$tmp"
  trap - EXIT
  echo "created signing identity in $KC" >&2
}

[ -f "$KC" ] || create_identity

# A run that stopped after create-keychain leaves no cert.pem; read it back from the keychain
# instead of failing on every later run.
if [ ! -f "$CERT" ]; then
  security find-certificate -c "$CN" -p "$KC" > "$CERT.tmp" 2>/dev/null && [ -s "$CERT.tmp" ] || {
    rm -f "$CERT.tmp"
    echo "sign.sh: $KC has no '$CN' certificate; move $DIR away and run again (permissions must then be granted again)" >&2
    exit 1
  }
  mv "$CERT.tmp" "$CERT"
  echo "recovered $CERT from $KC" >&2
fi

HASH="$("$OPENSSL" x509 -in "$CERT" -noout -fingerprint -sha1 | sed -e 's/.*=//' -e 's/://g')"
security unlock-keychain -p "$(cat "$PASS_FILE")" "$KC"

# codesign finds the identity only through the user search list, so add the signing
# keychain for this one call and restore the exact previous list afterwards.
SAVED=()
while IFS= read -r line; do SAVED+=("$line"); done < <(user_search_list)
restore_search_list() { security list-keychains -d user -s ${SAVED[@]+"${SAVED[@]}"}; }
trap restore_search_list EXIT
security list-keychains -d user -s ${SAVED[@]+"${SAVED[@]}"} "$KC"

# Hardened runtime: without the audio-input entitlement, tccd denies ScreenCaptureKit's microphone
# queries for vscreen outright instead of leaving them undetermined (a possible prompt).
# It also blocks DYLD_* injection into the identity that holds the Accessibility and Screen Recording grants.
args=(--force --sign "$HASH" --keychain "$KC" --timestamp=none --options runtime)
[ -n "$IDENT" ] && args+=(--identifier "$IDENT")
codesign "${args[@]}" "$TARGET"
