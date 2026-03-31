# Hold-to-Talk Dictation for macOS (VoiceInsert)

**What this is:** a complete macOS app for dictation into the **focused text field** (any app) and, separately, dictation into **Obsidian notes** as Markdown in your vault. Both flows work out of the box after permissions and shortcuts are set up.  
**What is not included:** “smart” post-processing of notes (agents, LLMs, bots, etc.)—you add that yourself on top of plain `.md` files; see [docs/obsidian-files.md](docs/obsidian-files.md).

---

## Repository status

**CI:** each push/PR runs [VoiceInsert build](.github/workflows/voiceinsert-build.yml) on GitHub (`swift build` + `Scripts/build_app.sh`) so broken installs are caught before users clone.

**Landing page:** static site in [`docs/index.html`](docs/index.html) (teal/dark one-pager). Enable **GitHub Pages** → branch `main` → folder **`/docs`**. For this repository, the site URL will be `https://vushnevskuu.github.io/push-talk/`, and the download button points at the latest GitHub Release ZIP.

**Releases:** pushing a git tag matching `v*` (e.g. `v1.0.0`) runs [Release](.github/workflows/release.yml) and attaches **`VoiceInsert-macos.zip`** (and a `.sha256` checksum) to a GitHub Release for that tag.

### Install from GitHub (no Xcode required)

1. Open the **Releases** page for this repository and download **`VoiceInsert-macos.zip`**.
2. Unzip it. You should see `VoiceInsert.app`.
3. Drag **`VoiceInsert.app`** into **Applications** (or `~/Applications`).
4. **First launch:** macOS may block apps that are not Developer ID–signed and notarized. Control-click the app → **Open** → confirm, or allow it under **System Settings → Privacy & Security**. If the app was quarantined by your browser, you can clear the quarantine flag (only if you trust this download):

   ```bash
   xattr -dr com.apple.quarantine /Applications/VoiceInsert.app
   ```

5. Grant **Microphone**, **Speech Recognition**, **Accessibility**, and **Input Monitoring** when prompted (see [Permissions](#permissions) below).

**Trust and signing:** Release ZIPs from CI are **ad hoc**–signed (`codesign -`), same as a local `./Scripts/build_app.sh` build. They are suitable for manual distribution; for the fewest Gatekeeper prompts, a future step is **Apple Developer Program** + **Developer ID** signing + **notarization** (not automated in this repo yet).

**Binary architecture:** Release ZIPs are built on GitHub Actions with `runs-on: macos-latest` (see [`.github/workflows/release.yml`](.github/workflows/release.yml)). The architecture of the downloaded app matches whatever that runner image produces for `swift build` (documented by GitHub for the current `macos-latest` image). If you need **Intel (`x86_64`)** binaries, build locally with `./Scripts/build_app.sh` on an Intel Mac or using a toolchain that targets `x86_64`.

---

This repo contains a working SwiftUI + AppKit MVP:

- Floating hold-to-talk button (mouse)
- Audio capture via `AVAudioEngine`
- Speech recognition via `Speech`
- Text insertion into the focused field via Accessibility API
- Fallback using `Cmd+V` and a temporary pasteboard
- `.app` packaging via `Scripts/build_app.sh` or `Scripts/install_voiceinsert_app.sh` (installs to `~/Applications` with ad-hoc codesign)
- A separate shortcut and vault picker for **Obsidian** (notes under `Voice Captures/` inside the vault)

For vault layout and where responsibility ends, see **[docs/obsidian-files.md](docs/obsidian-files.md)**.

**Optional local tooling:** the folder [`tools/obsidian-head-agent/`](tools/obsidian-head-agent/) holds Obsidian-related scripts (e.g. Telegram bot) for your own machine. It is not required to build VoiceInsert. Real secrets in that tree are listed in `.gitignore` so they stay local. See [`tools/obsidian-head-agent/README.md`](tools/obsidian-head-agent/README.md).

### Quick start

1. Open Terminal at the project root.
2. Install a **Swift 6** toolchain (e.g. Xcode 16+ or matching Command Line Tools) — the package uses `swift-tools-version: 6.0`.
3. Build and install:

```bash
./Scripts/build_app.sh
```

This resolves release binaries under `.build/…/release` (Apple Silicon and Intel). On machines that already have the bundled `VoiceInsert Local Signing` identity, `build_app.sh` now uses it automatically so macOS privacy grants keep sticking across rebuilds. Fresh clones still fall back to **ad hoc** signing (`codesign -`) so you do **not** need Homebrew OpenSSL or a custom signing identity. To force the local identity + keychain path explicitly:

```bash
VOICEINSERT_USE_LOCAL_IDENTITY=1 ./Scripts/build_app.sh
```

Alternative (same layout as manual QA builds):

```bash
./Scripts/install_voiceinsert_app.sh
```

4. Output path from `build_app.sh`:

```text
Build/VoiceInsert.app
```

Also copies to `~/Applications/VoiceInsert.app`.

5. Launch:

```bash
open Build/VoiceInsert.app
# or
open ~/Applications/VoiceInsert.app
```

**If `./Scripts/build_app.sh` fails** with “Could not find release binaries”, run `swift build -c release` once and check that `.build/arm64-apple-macosx/release/VoiceInsert` (or `x86_64-…`) exists — then upgrade Swift/Xcode if the toolchain is too old.

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
- Xcode 16+ (or Swift 6 toolchain) recommended for `swift-tools-version: 6.0`
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
