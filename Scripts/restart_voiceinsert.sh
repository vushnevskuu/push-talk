#!/bin/zsh
set -euo pipefail
INSTALL_DIR="${HOME}/Applications/VoiceInsert.app"
EXEC="${INSTALL_DIR}/Contents/MacOS/VoiceInsert"
if [[ ! -x "$EXEC" ]]; then
  echo "Not found or not executable: $EXEC — run ./Scripts/build_app.sh first." >&2
  exit 1
fi
pkill -f "$EXEC" >/dev/null 2>&1 || true
sleep 0.2
open "$INSTALL_DIR"
echo "Opened: $INSTALL_DIR"
