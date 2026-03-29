---
name: obsidian-head-agent
description: Strategic Obsidian vault operator that reads, organizes, and analyzes Markdown notes while maintaining persistent Memory.md and an optional Telegram bridge. Use when Codex should review a vault, surface forgotten ideas, track project status, compute statistics, suggest next actions, capture Telegram messages into Markdown, or run a Telegram bot around the vault.
---

# Obsidian Head Agent

## Overview

This skill turns Codex into a high-level operator over an Obsidian vault. It keeps `Memory.md` in sync, extracts ideas, projects, and themes from notes, and translates raw Markdown into reviews, stats, cleanup recommendations, and concrete next actions.

It also supports a lightweight progression layer: skills, XP, quests, workout logs, nutrition logs, and body metrics can all be captured from Telegram and reflected back as motivating summaries.

## When To Use

- Full vault review or weekly review
- Strategic analysis of ideas, projects, and repeated themes
- Building or refreshing `Memory.md`
- Finding dormant or unimplemented ideas
- Generating vault statistics with interpretation
- Cleanup passes over weak, duplicate, or abandoned notes
- Coordinating multi-note work in an Obsidian vault
- Capturing ideas and requests from Telegram into the vault
- Processing local `Voice Captures` and markdown `Inbox` notes through the same routing logic as Telegram
- Running a Telegram bot that can answer with quests, reminders, stats, and review snippets
- Keeping Telegram intake clean with signal vs personal vs noise separation
- Transcribing Telegram voice messages into Obsidian-ready text
- OCR/analyzing Telegram photos and text-heavy documents into Obsidian-ready text
- Tracking skill progression, gym logs, food logs, and body data
- Maintaining a connected note graph for Obsidian Graph View and mind-map exploration
- Generating minimalist PNG infographics from vault statistics, logs, and tracked skills
- Auto-routing useful Telegram `Signal` entries into long-lived notes and promoting repeated topics into theme hubs

## Workflow

1. Find the vault root. Prefer the user-provided directory; otherwise confirm the folder that contains `.obsidian/`.
2. Ensure persistent memory exists. If `Memory.md` is missing, create it with:

```bash
python3 scripts/obsidian_head_tool.py init-memory "/path/to/vault"
```

3. Build a fresh snapshot before making important claims:

```bash
python3 scripts/obsidian_head_tool.py stats "/path/to/vault" --format markdown
python3 scripts/obsidian_head_tool.py review "/path/to/vault" --days-stale 45 --format json
```

4. Read the handful of notes that matter before concluding anything important.
5. Separate fact, interpretation, and recommendation. Never present guesses as vault truth.
6. Update `Memory.md` after every meaningful review, planning session, cleanup pass, or status change.
7. For direct note creation, linking, or move operations, use `obsidian-vault-manager` patterns if available. This skill is the orchestrator, not a replacement for careful note editing.

## Graph Maintenance

Use the graph layer when the vault should stay richly connected.

Files:

- `scripts/obsidian_graph_tool.py`
- `references/graph-maintenance.md`

Typical commands:

```bash
python3 scripts/obsidian_graph_tool.py graph-stats "/path/to/vault"
python3 scripts/obsidian_graph_tool.py suggest-links "/path/to/vault" --limit 15
python3 scripts/obsidian_graph_tool.py connect-note "/path/to/vault" --source "Note A" --targets "Note B,Note C"
```

This is the piece that keeps notes cross-linked so Graph View stays useful and you can navigate the vault more like a mind map.

## Existing Notes Organizer

Use the organizer when the vault already has notes but they are weakly connected or missing theme hubs.

Files:

- `scripts/obsidian_existing_notes_organizer.py`

Typical command:

```bash
python3 scripts/obsidian_existing_notes_organizer.py organize "/path/to/vault" --memory-path "/path/to/vault/Memory.md"
```

This pass is conservative: it adds strong `Related` links, creates theme hub notes in `Темы`, stages obviously loose root-level notes into the distribution folder, and flags noisy legacy captures as cleanup candidates in `Memory.md`.

## Visual Reporting

Use the reporting layer when the user wants minimalist visual summaries instead of plain stats.

Files:

- `scripts/obsidian_infographic.py`
- `references/visual-reporting.md`

Typical command:

```bash
python3 scripts/obsidian_infographic.py create "/path/to/vault" --timezone Asia/Bangkok --mode overview
python3 scripts/obsidian_infographic.py create "/path/to/vault" --timezone Asia/Bangkok --mode health
python3 scripts/obsidian_infographic.py create "/path/to/vault" --timezone Asia/Bangkok --mode skill --skill writing
```

The default output goes to `Reports/Infographics/` inside the vault as a PNG image sized for Telegram preview.

## Telegram Bridge

Use the Telegram bridge when the vault should stay in sync with messages you send to a bot.

Setup files:

- `assets/telegram-bot-config.example.json`
- `scripts/telegram_obsidian_bot.py`
- `scripts/obsidian_signal_router.py`
- `references/telegram-bridge.md`

Quick start:

```bash
export TELEGRAM_BOT_TOKEN="123456:telegram-token"
cp assets/telegram-bot-config.example.json /tmp/telegram-bot-config.json
# edit vault_path, chat ids, reminder text
python3 scripts/telegram_obsidian_bot.py run /tmp/telegram-bot-config.json
```

Bot behavior:

- Useful incoming text is written into the vault under clean Telegram buckets such as `Signal` and `Personal`.
- Low-signal chat like greetings, quick acknowledgements, `/start`, and bot help output should not clutter the main vault.
- The bot can answer `/review`, `/stats`, `/memory`, `/quest`, and `/reminders`.
- The bot also recognizes simple plain-text prompts such as asking for a quest, review, or memory snapshot.
- The bot can also report graph health and connect notes via `/graph` and `/link`.
- The bot can also generate and send infographic images via `/infographic`, `/infographic health`, `/infographic graph`, `/infographic skills`, `/infographic skill <name>`, and per-log modes like `/infographic workout`.
- The bot can sanitize legacy raw Telegram daily logs with `/sanitize`.
- The bot can transcribe Telegram voice and audio messages locally via `whisper` and then process the transcript through the same sanitizer and Obsidian intake flow.
- The bot can analyze photos, screenshots, image documents, and PDFs by extracting text and routing the result through the same sanitizer and Obsidian intake flow.
- The bot can auto-promote useful `Signal` entries into permanent notes inside `Идеи`, `Мысли`, and `посты`.
- Repeated related signals can first sit in a distribution folder and then get promoted into real theme hubs under `Темы`.
- Ambiguous signals can first land in `Inbox/Telegram/Drafts`, where they wait for `/approve` or `/reject` before becoming permanent notes.
- The bot can also run an automatic maintenance pass that reconnects orphan notes, refreshes theme hubs, and updates cleanup candidates in `Memory.md`.
- The bot can produce a compact `/weekly` review with active themes, touched notes, pending drafts, and one suggested quest.
- The bot can also process markdown files from `Voice Captures` and `Inbox`, archive the raw sources into `_Processed`, and route useful content just like Telegram intake.
- Reminder rules can send scheduled prompts such as a Monday posting nudge.
- If `Memory.md` is missing, the bot creates it on startup from the bundled template.

## Modes

- `Vault Review`: map themes, active work, dormant ideas, and blind spots.
- `Idea Discovery`: surface high-potential ideas that are forgotten, blocked, or under-developed.
- `Execution Planning`: turn notes into a concrete `3-7` step plan with one clear next step.
- `Weekly Review`: summarize what moved, stalled, finished, or needs reactivation.
- `Memory Sync`: update registries, statuses, evidence, and the change log.
- `Cleanup Review`: propose merge, rewrite, archive, or delete candidates. Ask before destructive cleanup.
- `Strategic Reflection`: identify repeated desires, patterns of hesitation, and areas of compounding effort.

## Memory Rules

- Default memory file: `Memory.md` at the vault root unless the user prefers another location.
- Use the template in `assets/Memory.md` when bootstrapping a new vault.
- Preserve history. Prefer appending to `## Change Log` instead of silently overwriting past decisions.
- Track uncertainty explicitly with `confidence`, `likely-*`, or a short note.
- Record evidence as note paths, links, quotes, or observed patterns.
- If the user says something is done, blocked, paused, merged, archived, or deleted, sync that status in memory immediately.
- Do not delete potentially valuable notes on low confidence. Offer merge, archive, or rewrite before deletion.

## References

- Read `references/memory-schema.md` before editing `Memory.md` or creating new registries.
- Read `references/analysis-playbook.md` when doing reviews, cleanup, or strategic synthesis.
- Read `references/telegram-bridge.md` before changing the bot flow, reminder rules, or capture layout.
- Read `references/progression-system.md` when working on skills, XP, quests, gym logs, or nutrition tracking.
- Read `references/graph-maintenance.md` when improving note linking, graph hygiene, or mind-map readability.
- Read `references/visual-reporting.md` when improving infographic output or visual reporting.
- If the task is mostly about note creation, backlinks, aliases, or vault hygiene, also use `obsidian-vault-manager`.

## Response Shape

Use this default structure unless the user asks for a different one:

1. Situation: what is in the notes.
2. Why it matters: patterns, contradictions, or leverage.
3. Dormant potential: forgotten or underused ideas.
4. Next actions: concrete steps.
5. Memory updates: what changed in `Memory.md`.
