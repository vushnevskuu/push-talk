#!/bin/zsh
set -eu

# Repo-local agent tree: tools/obsidian-head-agent/
AGENT_ROOT="${0:A:h}/.."
AGENT_ROOT="${AGENT_ROOT:A}"

ENV_FILE="${HOME}/.config/obsidian-head-agent/telegram.env"
CONFIG="${AGENT_ROOT}/assets/telegram-bot-config.real-vault.json"
SCRIPT="${AGENT_ROOT}/scripts/telegram_obsidian_bot.py"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

if [ ! -f "$CONFIG" ]; then
  echo "Missing config: $CONFIG" >&2
  echo "Copy assets/telegram-bot-config.example.json to telegram-bot-config.real-vault.json and edit paths." >&2
  exit 1
fi

source "$ENV_FILE"
exec python3 "$SCRIPT" run "$CONFIG"
