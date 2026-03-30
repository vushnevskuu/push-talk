#!/usr/bin/env bash
# Сборка release из репозитория и установка в ~/Applications/VoiceInsert.app
# с единообразной ad-hoc подписью (главный бинарник + VoiceInsertInjector + бандл).
#
# Использование:
#   ./scripts/install_voiceinsert_app.sh
#   RESET_TCC=1 ./scripts/install_voiceinsert_app.sh   — сброс разрешений TCC для bundle id (потом снова «Разрешить» в System Settings)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${VOICEINSERT_APP_PATH:-$HOME/Applications/VoiceInsert.app}"
MAIN_PLIST="$REPO_ROOT/Packaging/Info.plist"

cd "$REPO_ROOT"

if [[ ! -f "$MAIN_PLIST" ]]; then
  echo "Нет $MAIN_PLIST" >&2
  exit 1
fi

echo ">>> swift build -c release"
swift build -c release --product VoiceInsert --product VoiceInsertInjector

# Целевой каталог артефактов (Apple Silicon / универсальный toolchain)
REL_DIR="$REPO_ROOT/.build/arm64-apple-macosx/release"
if [[ ! -x "$REL_DIR/VoiceInsert" ]]; then
  REL_DIR="$REPO_ROOT/.build/release"
fi
if [[ ! -x "$REL_DIR/VoiceInsert" ]]; then
  REL_DIR="$(dirname "$(find "$REPO_ROOT/.build" -type f \( -name VoiceInsert -path "*/release/*" \) -print -quit)")"
fi

BIN_MAIN="$REL_DIR/VoiceInsert"
BIN_INJ="$REL_DIR/VoiceInsertInjector"
if [[ ! -x "$BIN_MAIN" || ! -x "$BIN_INJ" ]]; then
  echo "Не найдены release-бинарники после сборки (ожидались VoiceInsert и VoiceInsertInjector)." >&2
  exit 1
fi

echo ">>> остановка текущего процесса"
pkill -x VoiceInsert 2>/dev/null || true
sleep 0.4

echo ">>> установка в $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$MAIN_PLIST" "$APP/Contents/Info.plist"
cp "$BIN_MAIN" "$APP/Contents/MacOS/VoiceInsert"
chmod +x "$APP/Contents/MacOS/VoiceInsert"
cp "$BIN_INJ" "$APP/Contents/Helpers/VoiceInsertInjector"
chmod +x "$APP/Contents/Helpers/VoiceInsertInjector"

# Убрать устаревшие бэкапы в MacOS (мешают не мешают — подчистим *.bak*)
rm -f "$APP/Contents/MacOS/"*.bak* 2>/dev/null || true

echo ">>> codesign (adhoc)"
codesign --force --sign - "$APP/Contents/Helpers/VoiceInsertInjector"
codesign --force --sign - "$APP/Contents/MacOS/VoiceInsert"
rm -rf "$APP/Contents/_CodeSignature" 2>/dev/null || true
codesign --force --deep --sign - "$APP"

if codesign --verify --verbose=4 "$APP" 2>&1; then
  echo ">>> подпись бандла OK"
else
  echo "!!! verify вернул ошибку — приложение всё равно можно попробовать открыть" >&2
fi

if [[ "${RESET_TCC:-}" == "1" ]]; then
  echo ">>> tccutil reset All local.codex.voiceinsert"
  tccutil reset All local.codex.voiceinsert || true
fi

echo ">>> открытие приложения"
open "$APP"
echo "Готово: $APP"
echo "Если RESET_TCC=1 не ставил: при проблемах с микрофоном выполни: RESET_TCC=1 $0"
