# Hold-to-Talk Dictation for macOS (VoiceInsert)

**What this is:** a complete macOS app for dictation into the **focused text field** (any app) and, separately, dictation into **Obsidian notes** as Markdown in your vault. Both flows work out of the box after permissions and shortcuts are set up.  
**What is not included:** “smart” post-processing of notes (agents, LLMs, bots, etc.)—you add that yourself on top of plain `.md` files; see [docs/obsidian-files.md](docs/obsidian-files.md).

---

## Repository status

This repo contains a working SwiftUI + AppKit MVP:

- Floating hold-to-talk button (mouse)
- Audio capture via `AVAudioEngine`
- Speech recognition via `Speech`
- Text insertion into the focused field via Accessibility API
- Fallback using `Cmd+V` and a temporary pasteboard
- `.app` packaging via `Scripts/build_app.sh`
- A separate shortcut and vault picker for **Obsidian** (notes under `Voice Captures/` inside the vault)

For vault layout and where responsibility ends, see **[docs/obsidian-files.md](docs/obsidian-files.md)**.

**Optional local tooling:** the folder [`tools/obsidian-head-agent/`](tools/obsidian-head-agent/) holds Obsidian-related scripts (e.g. Telegram bot) for your own machine. It is not required to build VoiceInsert. Real secrets in that tree are listed in `.gitignore` so they stay local. See [`tools/obsidian-head-agent/README.md`](tools/obsidian-head-agent/README.md).

### Quick start

1. Open Terminal at the project root.
2. Build the app:

```bash
./Scripts/build_app.sh
```

3. Output path:

```text
Build/VoiceInsert.app
```

4. Launch:

```bash
open Build/VoiceInsert.app
```

### Permissions

- Microphone
- Speech Recognition
- Accessibility

Without Accessibility, speech may still work but insertion into other apps’ fields is unreliable.

VoiceInsert is a lightweight menu bar utility: hold your shortcut, speak, release—the recognized text is inserted into the active field (dictation language is configurable in Settings). A second shortcut saves dictation into the configured Obsidian vault.

---

## Features

- Menu bar utility
- Two independent shortcuts: **insert into field** and **Obsidian capture** (after you choose a vault in Settings)
- Recording starts on key down, ends on key up
- Dictation language selectable in Settings (e.g. Russian / English)
- Inserts into the current focused text field
- Creates Markdown files under `Voice Captures/` in the vault—see [docs/obsidian-files.md](docs/obsidian-files.md)
- Clipboard-based fallback when direct Accessibility insertion fails
- Onboarding for system permissions

---

## Main flows

### Dictate into a field

1. Open any app with a text field.
2. Focus the field.
3. Hold the **field insert** shortcut.
4. Speak and release—the text appears in the field.

### Dictate into Obsidian

1. In Settings, choose your vault folder (must contain an `.obsidian` directory).
2. Hold the **Obsidian capture** shortcut, speak, release—a new `.md` appears under `Voice Captures/…` (category inferred from your phrase; details in [docs/obsidian-files.md](docs/obsidian-files.md)).

---

## Stack

- Swift
- SwiftUI
- AppKit
- AVFoundation / AVAudioEngine
- Speech framework
- Accessibility API
- CoreGraphics / global hotkey handling

---

## Requirements

- macOS 13+ recommended
- Xcode 15+ recommended
- Apple Silicon or Intel Mac
- Microphone access
- Speech Recognition permission
- Accessibility permission
- Input Monitoring may be required depending on global hotkey capture mode

---

## Privacy

- Audio is not persisted by default
- Transcripts are not sent to a first-party server
- Speech content should not be logged in production builds
- Debug logging is off by default

---

## Definition of Done (MVP)

- Stable behavior in typical text fields
- User can change the hotkey in Settings
- Speech-to-text in the chosen language yields usable text
- Insertion works at least in Safari text areas, Notes, and TextEdit
- On permission errors the app stays usable and explains next steps

---
