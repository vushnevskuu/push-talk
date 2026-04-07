#!/bin/zsh
# Сборка + smoke-тест VoiceInsert. Нужен `--app-path`, т.к. build_app.sh удаляет Build/*.app после копирования в ~/Applications.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SMOKE="${MACOS_APP_SMOKE_SCRIPT:-$HOME/.codex/skills/macos-app-autotest/scripts/run_macos_app_smoke.py}"
exec python3 "$SMOKE" --workspace "$ROOT" --app-path "$HOME/Applications/VoiceInsert.app" "$@"
