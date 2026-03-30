# Telegram Bridge

## Goal

Connect a Telegram bot to the Obsidian vault so that:

- useful incoming Telegram messages are captured in Markdown,
- the bot can answer with vault-aware summaries,
- voice and audio messages can be transcribed into text before intake,
- photos, screenshots, and text-heavy documents can be OCR'd before intake,
- scheduled reminders can nudge the user about recurring actions,
- and `Memory.md` stays available as the durable strategic state.

## Config Model

The bot reads a JSON config file.

Important fields:

- `bot_token` or `bot_token_env`: Telegram bot token or the environment variable that stores it
- `vault_path`: absolute path to the Obsidian vault
- `default_chat_id`: chat that receives scheduled reminders
- `allowed_chat_ids`: optional allowlist for private use
- `timezone`: default timezone for timestamps and reminder evaluation
- `memory_path`: relative path to `Memory.md`
- `capture.directory`: relative vault folder where Telegram logs are written
- `capture.signal_directory`: where useful note-worthy messages go
- `capture.personal_directory`: where reflective or personal entries go
- `capture.noise_directory`: optional bucket for low-signal chat, usually disabled
- `capture.archive_directory`: where legacy raw Telegram logs are moved after sanitizing
- `capture.capture_noise`: whether to keep low-signal chat at all
- `capture.capture_bot_messages`: whether to store bot replies in the vault
- `capture.capture_commands`: whether slash commands like `/start` should be stored
- `capture.noise_acknowledgement`: response used when a message is intentionally not written to the vault
- `voice.enabled`: whether Telegram voice/audio transcription is enabled
- `voice.model`: local whisper model name, such as `tiny` or `small`
- `voice.language`: optional whisper language hint like `ru`; `null` means auto-detect
- `vision.enabled`: whether Telegram photo/document analysis is enabled
- `vision.recognition_languages`: preferred macOS Vision OCR languages, such as `["ru-RU", "en-US"]`
- `vision.tesseract_lang`: fallback tesseract language code when Vision OCR fails
- `routing.enabled`: whether useful `Signal` items should also become permanent notes automatically
- `routing.idea_directory`, `routing.thought_directory`, `routing.post_directory`: long-lived note folders for promoted signal content
- `routing.draft_directory`: folder for ambiguous signals that need manual approval before publishing
- `routing.enable_drafts`: whether uncertain new signals should pause as drafts instead of publishing immediately
- `routing.distribution_directory`: staging folder for topic candidates that are not yet strong enough to become themes
- `routing.themes_directory`: folder for promoted theme hubs
- `routing.minimum_theme_mentions`: how many related signals are needed before a staged topic becomes a theme
- `local_intake.enabled`: whether local markdown files from `Voice Captures` and `Inbox` should be processed automatically
- `local_intake.scan_interval_seconds`: how often the bot checks local markdown sources for new files
- `local_intake.sources`: folders that should be treated like local intake queues
- `local_intake.exclude`: subfolders that should never be reprocessed
- `local_intake.personal_directory`: destination for local personal notes that should stay separate from knowledge notes
- `maintenance.enabled`: whether the bot should periodically run an organizer pass over existing notes
- `maintenance.interval_minutes`: maximum idle time before the organizer runs again
- `maintenance.min_new_signals`: organizer also runs after this many newly routed signals
- `maintenance.notify_chat`: optionally post organizer summaries back into Telegram
- `maintenance.organizer.*`: organizer thresholds and folder scopes for linking orphan notes, staging loose root notes into distribution, and building theme hubs
- `review.days_stale` and `review.limit`: defaults for `/review`
- `reminders[]`: recurring reminder rules

## Reminder Rules

Each reminder supports:

- `id`
- `enabled`
- `days`: array such as `["monday"]`
- `time`: `HH:MM`
- `timezone`
- `chat_id`: optional override, otherwise `default_chat_id`
- `message`

`message` may use placeholders:

- `{date}`
- `{quest}`

This makes it easy to create reminders like a Monday post prompt:

```json
{
  "id": "monday_vibe_code",
  "enabled": true,
  "days": ["monday"],
  "time": "09:00",
  "timezone": "Asia/Bangkok",
  "message": "Today is Monday. Quest: {quest}\n\nPost your vibe code update."
}
```

## Commands

- `/start`: intro and command list
- `/help`: short help
- `/review`: compact review based on the vault snapshot
- `/stats`: compact vault stats
- `/memory`: show current priorities and open questions from `Memory.md`
- `/quest`: suggest one focused action
- `/profile`: show level, XP, top skills, and current momentum
- `/skills`: show skill progression
- `/health`: show workout and nutrition snapshot
- `/graph`: show note graph health
- `/infographic`: generate and send a minimalist overview image
- `/infographic graph|health|skills`: send a focused report image
- `/infographic skill <name>`: send an image for one tracked skill
- `/infographic workout|nutrition|body`: send an image for one tracking log
- `/link`: connect notes bidirectionally from Telegram
- `/log`: deterministic logging command for skill, workout, food, and body data
- `/sanitize`: clean legacy noisy Telegram daily logs into cleaner buckets
- `/organize`: explicitly run the organizer and orphan-note curation pass
- `/intake`: process local `Voice Captures` and `Inbox` markdown files immediately
- `/drafts`: list pending drafts
- `/approve <draft_id>`: publish a pending draft
- `/reject <draft_id>`: archive a pending draft without publishing
- `/weekly`: compact weekly review with themes, recent notes, drafts, and one quest
- `/reminders`: list active reminder rules

Not every non-command text should become a note. The bot should separate:

- `Signal`: ideas, tasks, plans, meaningful prompts, note-worthy fragments
- `Personal`: reflective or diary-like messages that belong in a separate bucket
- `Noise`: greetings, quick acknowledgements, tests, social chatter, and bot queries

Noise should usually not be written into the main vault at all.

The bot also supports simple natural-language triggers. Messages like "дай квест", "what should I do", "show memory", or "что по vault" are routed to the matching summary without requiring a slash command.

The bot also understands lightweight tracking messages and writes them into markdown logs:

- `gym: bench 80x5x3`
- `food: 2200 kcal 160 protein`
- `skill: writing | drafted article`
- `weight 82.4`
- `sleep 7.5`

Voice messages are supported too. The bot downloads the audio from Telegram, transcribes it locally with `whisper`, and then routes the transcript through the same rules:

- useful voice notes -> `Signal`
- personal reflective voice notes -> `Personal`
- low-signal chatter -> ignored
- voice logs like workout or nutrition updates -> `Logs/Tracking`

Photos and text documents are supported too. The bot can:

- read Telegram `photo` messages
- read image files sent as documents
- read PDF documents with selectable text
- OCR screenshots, whiteboards, and photographed documents

The extracted text is then routed through the same rules:

- useful document/photo content -> `Signal`
- personal reflective content -> `Personal`
- logs embedded in screenshots or documents -> `Logs/Tracking`
- low-signal images with no usable text -> ignored unless the caption provides the context

Useful `Signal` entries can also be promoted automatically into long-lived notes:

- product or build-like signals -> `Идеи`
- reflective signals -> `Мысли`
- publishable angles or content fragments -> `посты`

If the bot sees a possible recurring topic but does not yet trust it as a real theme, it creates a staging note in `routing.distribution_directory`. When similar signals repeat enough times, that staging note is promoted into a real theme hub inside `routing.themes_directory`.

If the bot sees a useful signal but does not yet trust the permanent note kind or destination, it creates a draft in `routing.draft_directory`. The user can then confirm it with `/approve <draft_id>` or archive it with `/reject <draft_id>`.

Local markdown files can go through a similar intake flow too:

- source folders like `Voice Captures/Inbox`, `Voice Captures/Ideas`, and `Inbox` are scanned automatically
- low-signal notes are archived into `_Processed`
- useful notes are routed into permanent notes, themes, or drafts via the same `Signal` router
- personal notes can be moved into `Inbox/Personal`
- original markdown sources are archived into `Voice Captures/_Processed/` (or `Inbox/_Processed/`, etc.) **by filename only**—no duplicate `Ideas/` / `Inbox/` tree under `_Processed`, so the vault sidebar stays simpler

The bot can also run a maintenance pass automatically over existing vault notes:

- weakly connected notes receive stronger `Related` links
- folder-level hubs such as ideas, thoughts, posts, and personal-path notes can get stable theme hubs
- legacy noisy voice captures get registered as cleanup candidates in `Memory.md`
- the pass can run on a timer and also after enough new `Signal` captures have accumulated

## Capture Layout

Default layout:

- `Inbox/Telegram/Signal/YYYY-MM-DD.md`
- `Inbox/Telegram/Personal/YYYY-MM-DD.md`
- `Inbox/Telegram/_Archive/YYYY-MM-DD.raw.md`

Each entry stores:

- timestamp
- direction: `incoming` or `bot`
- chat id
- sender
- message text

Voice entries may also store:

- `source: voice`
- `duration_sec`
- `transcript_model`

Photo/document entries may also store:

- `source: photo|image-document|pdf-document`
- `mime_type`
- `analysis_model`

Legacy append-only daily logs can be sanitized and archived when the user asks for cleanup or when the vault is already cluttered.

## Practical Notes

- Prefer Telegram long polling via `getUpdates` for local setups.
- Use `allowed_chat_ids` for private bots so strangers cannot write into the vault.
- Store the secret in an environment variable with `bot_token_env` when possible.
- If you later switch to webhooks, keep the capture and command semantics the same.
