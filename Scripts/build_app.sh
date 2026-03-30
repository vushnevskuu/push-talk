#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/Build"
APP_NAME="VoiceInsert"
HELPER_NAME="VoiceInsertInjector"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications/$APP_NAME.app"
MAIN_PLIST="$ROOT_DIR/Resources/Info.plist"
SIGNING_SCRIPT="$ROOT_DIR/Scripts/ensure_local_codesigning_identity.sh"

cd "$ROOT_DIR"
swift build -c release --product "$APP_NAME" --product "$HELPER_NAME"

# SPM may place binaries only under .build/<arch>-apple-macosx/release (no .build/release symlink).
REL_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
if [[ ! -x "$REL_DIR/$APP_NAME" ]]; then
  REL_DIR="$ROOT_DIR/.build/x86_64-apple-macosx/release"
fi
if [[ ! -x "$REL_DIR/$APP_NAME" ]]; then
  REL_DIR="$ROOT_DIR/.build/release"
fi
if [[ ! -x "$REL_DIR/$APP_NAME" ]]; then
  REL_DIR="$(dirname "$(find "$ROOT_DIR/.build" -type f \( -name "$APP_NAME" -path "*/release/*" \) -print -quit )")"
fi

EXECUTABLE_PATH="$REL_DIR/$APP_NAME"
HELPER_PATH="$REL_DIR/$HELPER_NAME"
if [[ ! -x "$EXECUTABLE_PATH" || ! -x "$HELPER_PATH" ]]; then
  echo "Could not find release binaries after swift build (expected $APP_NAME and $HELPER_NAME under .build/.../release)." >&2
  echo "Install Swift 6 / Xcode 16+ toolchain and run from the repo root." >&2
  exit 1
fi

if [[ ! -f "$MAIN_PLIST" ]]; then
  echo "Missing $MAIN_PLIST" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Helpers"

cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$HELPER_PATH" "$APP_DIR/Contents/Helpers/$HELPER_NAME"
chmod +x "$APP_DIR/Contents/Helpers/$HELPER_NAME"
cp "$MAIN_PLIST" "$APP_DIR/Contents/Info.plist"

if command -v codesign >/dev/null 2>&1; then
  # Default: ad-hoc signing works for everyone cloning from GitHub (no Homebrew OpenSSL / custom identity).
  if [[ "${VOICEINSERT_USE_LOCAL_IDENTITY:-}" == "1" && -x "$SIGNING_SCRIPT" ]]; then
    SIGNING_OUTPUT="$("$SIGNING_SCRIPT")"
    SIGNING_IDENTITY="${SIGNING_OUTPUT%%|*}"
    SIGNING_KEYCHAIN="${SIGNING_OUTPUT#*|}"
    codesign --force --sign "$SIGNING_IDENTITY" --keychain "$SIGNING_KEYCHAIN" --timestamp=none \
      "$APP_DIR/Contents/Helpers/$HELPER_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    rm -rf "$APP_DIR/Contents/_CodeSignature" 2>/dev/null || true
    codesign --force --deep --sign "$SIGNING_IDENTITY" --keychain "$SIGNING_KEYCHAIN" --timestamp=none "$APP_DIR" 2>/dev/null || true
  else
    codesign --force --sign - "$APP_DIR/Contents/Helpers/$HELPER_NAME"
    codesign --force --sign - "$APP_DIR/Contents/MacOS/$APP_NAME"
    rm -rf "$APP_DIR/Contents/_CodeSignature" 2>/dev/null || true
    codesign --force --deep --sign - "$APP_DIR"
  fi
fi

mkdir -p "$HOME/Applications"
pkill -f "$INSTALL_DIR/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true
rm -rf "$INSTALL_DIR"
cp -R "$APP_DIR" "$INSTALL_DIR"

echo "App bundle created at: $APP_DIR"
echo "Installed app at: $INSTALL_DIR"
