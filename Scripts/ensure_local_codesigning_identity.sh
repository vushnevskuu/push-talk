#!/bin/zsh

set -euo pipefail

SIGNING_DIR="${VOICEINSERT_SIGNING_DIR:-$HOME/.voiceinsert-signing}"
KEYCHAIN_PATH="$SIGNING_DIR/voiceinsert-signing.keychain-db"
KEYCHAIN_PASSWORD="voiceinsert-local-signing"
IDENTITY_NAME="VoiceInsert Local Signing"
P12_PASSWORD="voiceinsert-p12"

mkdir -p "$SIGNING_DIR"

ensure_keychain() {
  if [[ ! -f "$KEYCHAIN_PATH" ]]; then
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
  fi

  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
  security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH" >/dev/null

  local existing_keychains=()
  local line
  while IFS= read -r line; do
    line="${line//\"/}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [[ -n "$line" ]] || continue
    [[ "$line" == /* ]] || continue
    [[ "$line" == "$KEYCHAIN_PATH" ]] && continue
    [[ -e "$line" ]] || continue

    if (( ${existing_keychains[(Ie)$line]} == 0 )); then
      existing_keychains+=("$line")
    fi
  done < <(security list-keychains -d user 2>/dev/null || true)

  local login_keychain="$HOME/Library/Keychains/login.keychain-db"
  if [[ -e "$login_keychain" && ${existing_keychains[(Ie)$login_keychain]} == 0 ]]; then
    existing_keychains+=("$login_keychain")
  fi

  security list-keychains -d user -s "$KEYCHAIN_PATH" "${existing_keychains[@]}" >/dev/null
}

identity_exists() {
  security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null | grep -Fq "\"$IDENTITY_NAME\""
}

resolve_openssl() {
  if [[ -n "${OPENSSL:-}" && -x "$OPENSSL" ]]; then
    printf '%s' "$OPENSSL"
    return 0
  fi
  for candidate in /opt/homebrew/bin/openssl /usr/local/opt/openssl/bin/openssl /usr/bin/openssl; do
    if [[ -x "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

create_identity() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  local openssl_bin
  openssl_bin="$(resolve_openssl)" || {
    echo "openssl not found (install Xcode CLT or Homebrew openssl); set OPENSSL=/path/to/openssl" >&2
    exit 1
  }

  "$openssl_bin" req \
    -x509 \
    -newkey rsa:2048 \
    -keyout "$tmpdir/key.pem" \
    -out "$tmpdir/cert.pem" \
    -days 3650 \
    -nodes \
    -subj "/CN=$IDENTITY_NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" >/dev/null 2>&1

  "$openssl_bin" pkcs12 \
    -export \
    -legacy \
    -inkey "$tmpdir/key.pem" \
    -in "$tmpdir/cert.pem" \
    -out "$tmpdir/identity.p12" \
    -passout pass:"$P12_PASSWORD" >/dev/null 2>&1

  security import "$tmpdir/identity.p12" -k "$KEYCHAIN_PATH" -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null
  security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN_PATH" "$tmpdir/cert.pem" >/dev/null 2>&1 || true
  security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
  rm -rf "$tmpdir"
}

ensure_keychain

if ! identity_exists; then
  create_identity
fi

printf '%s|%s\n' "$IDENTITY_NAME" "$KEYCHAIN_PATH"
