# Obsidian head-agent (optional, local)

Python/Telegram tooling that works **on top of** Markdown files in your vault. It is **not** part of the VoiceInsert app binary; keep it here for a single checkout directory on your machine.

## Layout

- `scripts/` — bots, routers, helpers
- `assets/` — config templates; **real** configs with tokens stay local and are **gitignored** (`*real*.json`, `*.state.json`)
- `references/` — playbooks and notes

## Run the Telegram bot (example)

1. `mkdir -p ~/.config/obsidian-head-agent` and add `telegram.env` with `TELEGRAM_BOT_TOKEN=...`
2. Copy `assets/telegram-bot-config.example.json` → `assets/telegram-bot-config.real-vault.json` and set vault paths.
3. From repo root:

```bash
./tools/obsidian-head-agent/scripts/run_real_vault_bot.sh
```

Paths inside the script are **relative to this folder**; moving the whole repo keeps it working.

## Git

Only the example config and code are safe to push. Do not commit real Telegram config or state files.
