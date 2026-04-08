#!/usr/bin/env bash
# Однократная установка MemPalace для MCP Cursor (локальный ChromaDB, без облака).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MP="$ROOT/tools/mempalace"
cd "$MP"
if [[ ! -f pyproject.toml ]]; then
  echo "Нет submodule: выполни git submodule update --init tools/mempalace" >&2
  exit 1
fi
# ChromaDB/hnswlib иногда капризны на самых новых Python; при ошибке сборки попробуй: /opt/homebrew/bin/python3.12 -m venv .venv
python3 -m venv .venv
"$MP/.venv/bin/pip" install -U pip
"$MP/.venv/bin/pip" install -e .
echo "Готово. Перезапусти Cursor, чтобы подхватить MCP mempalace."
echo "Дальше: mempalace init ~/путь/к/vault && mempalace mine ~/путь/к/vault --wing voiceinsert"
echo "(или см. PROJECT_CONTEXT.md → раздел MemPalace)"
