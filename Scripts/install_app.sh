#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_APP="$ROOT_DIR/Build/VoiceInsert.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/VoiceInsert.app"

if [[ ! -d "$BUILD_APP" ]]; then
  echo "Build app not found at: $BUILD_APP" >&2
  echo "Run ./Scripts/build_app.sh first." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP"
ditto "$BUILD_APP" "$INSTALLED_APP"

echo "Installed app at: $INSTALLED_APP"
