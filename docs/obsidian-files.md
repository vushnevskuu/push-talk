# Obsidian: where VoiceInsert writes files

VoiceInsert is a **complete product** on its own: dictation into the **focused field** in any app, plus separate dictation into **Obsidian notes** (dedicated shortcut in Settings).  
**Post-processing** of notes (tags, LLMs, bots, semantic reorganization, etc.) is **not** part of the app—you bring your own workflow: Obsidian plugins, scripts, or other tools. Files are plain **Markdown** in your vault.

---

## Choosing a vault

1. Open VoiceInsert Settings (menu bar menu or app UI).
2. Pick the **vault root folder**: the directory that contains an `.obsidian` folder (the app uses this to verify an Obsidian vault).
3. One active vault path is stored in app settings.

---

## Where files go

All voice captures are created inside the vault under:

```text
Voice Captures/
```

Then a subfolder for the **note category** (see below). The app **creates** missing folders as needed.

Full path pattern:

```text
<Vault>/Voice Captures/<Category>/<filename>.md
```

---

## Categories and routing

The category is chosen from **phrase prefixes** (markers) or **keywords** in the recognized text. If nothing matches, the note goes to **Inbox**.

| Folder     | Role (short)        |
| ---------- | ------------------- |
| `Ideas`    | Ideas               |
| `Tasks`    | Tasks               |
| `Meetings` | Meetings / calls    |
| `Journal`  | Journal / reflection|
| `Notes`    | General notes       |
| `Inbox`    | Everything else     |

Spoken markers include Russian and English cues (non-exhaustive; the code has the full list), e.g. phrases starting with idea/task/meeting/journal/note patterns, and words like `idea`, `task`, `meeting`, `journal`, `note`.  
If you say something like “idea go to the store” without a strict prefix, **keyword detection** in the transcript may still pick a category.

---

## Markdown file format

- Encoding: **UTF-8**
- Body: a level-1 heading `# …` using a **human-readable date** (day + month name + year, Russian locale, e.g. `29 марта 2026 · Идея`) followed by the **transcript text** (prefix markers may be stripped when classifying).
- Filename: starts with a **human-readable Russian date and time**, e.g. `17 марта 2026г., 15-06-07 Идея.md` (day + month name + year with «г.», then time with dashes so the name stays filesystem-safe), then the category label; on collisions, suffixes `2`, `3`, … are appended.

If you use the optional `tools/obsidian-head-agent` bot, **local intake** moves processed captures into `Voice Captures/_Processed/` using **only the file name** (no extra `Ideas/` / `Inbox/` mirror under `_Processed`), so the sidebar stays flatter.

Category **tags** from the internal model are **not** written into the file body—add tags with plugins or by hand if you need them.

---

## Limitations

- One configured vault path in the UI (not multiple vaults at once).
- Dictation language is set in app Settings (see current options there).
- You are responsible for vault content and backups; VoiceInsert only adds files under `Voice Captures/`.

---

## Further processing is up to you

Files work with any Obsidian workflow: templates, Dataview, Linter, custom scripts.  
VoiceInsert does **not** ship or configure Telegram bots, local LLMs, or agent stacks—it only writes predictable Markdown files in the locations above.
