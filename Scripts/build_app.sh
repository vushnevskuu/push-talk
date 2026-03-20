#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/Build"
APP_NAME="VoiceInsert"
HELPER_NAME="VoiceInsertInjector"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications/$APP_NAME.app"
EXECUTABLE_PATH="$ROOT_DIR/.build/release/$APP_NAME"
HELPER_PATH="$ROOT_DIR/.build/release/$HELPER_NAME"
SIGNING_SCRIPT="$ROOT_DIR/Scripts/ensure_local_codesigning_identity.sh"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Helpers"

cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$HELPER_PATH" "$APP_DIR/Contents/Helpers/$HELPER_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

if [[ -x "$SIGNING_SCRIPT" ]] && command -v codesign >/dev/null 2>&1; then
  SIGNING_OUTPUT="$("$SIGNING_SCRIPT")"
  SIGNING_IDENTITY="${SIGNING_OUTPUT%%|*}"
  SIGNING_KEYCHAIN="${SIGNING_OUTPUT#*|}"
  codesign \
    --force \
    --deep \
    --sign "$SIGNING_IDENTITY" \
    --keychain "$SIGNING_KEYCHAIN" \
    --timestamp=none \
    "$APP_DIR" >/dev/null 2>&1
elif command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

mkdir -p "$HOME/Applications"
pkill -f "$INSTALL_DIR/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true
rm -rf "$INSTALL_DIR"
cp -R "$APP_DIR" "$INSTALL_DIR"

echo "App bundle created at: $APP_DIR"
echo "Installed app at: $INSTALL_DIR"
