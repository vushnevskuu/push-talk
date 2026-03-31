# VoiceInsert Project Context

This is the plain root-level project context for Cursor agents.

If Cursor fails to resolve hidden paths like `.cursor/project-context.md`, use this file instead.

## Product summary

VoiceInsert is a macOS menu bar app for:

- hold-to-talk dictation into the currently focused text field
- hold-to-talk dictation into an Obsidian vault as Markdown notes

Main runtime pieces:

- `VoiceInsert.app` — main menu bar app
- `VoiceInsertInjector` — helper used for reliable event injection / typing / paste fallback

## Main source layout

### App source

`Sources/VoiceInsertApp/`

- `App/`
  - lifecycle, app model, runtime state, integration glue
  - key files:
    - `AppModel.swift`
    - `EventInjectorMode.swift`
    - `AppDelegate.swift`
    - `VoiceInsertApp.swift`
- `Hotkey/`
  - shortcut capture
  - key files:
    - `HotkeyMonitor.swift`
    - `KeyboardShortcut.swift`
- `Transcription/`
  - mic capture and speech recognition
  - key file:
    - `SpeechRecognitionService.swift`
- `Insertion/`
  - focused-field targeting and insertion logic
  - key file:
    - `TextInsertionService.swift`
- `Permissions/`
  - microphone, speech, input monitoring, accessibility
  - key file:
    - `PermissionManager.swift`
- `UI/`
  - SwiftUI and AppKit UI
  - key files:
    - `SettingsView.swift`
    - `MenuBarMenuView.swift`
    - `FloatingPanelView.swift`
    - `RecordingHUD*`
- `Obsidian/`
  - vault capture flow
  - key file:
    - `ObsidianCaptureService.swift`

### Helper app

`Sources/VoiceInsertInjector/main.swift`

- keep behavior aligned with `Sources/VoiceInsertApp/App/EventInjectorMode.swift`

### Packaging and install

- `Resources/Info.plist`
- `Packaging/Info.plist`
- `Scripts/build_app.sh`
- `Scripts/ensure_local_codesigning_identity.sh`
- `Scripts/install_voiceinsert_app.sh`
- `Scripts/install_app.sh` (copies existing `Build/VoiceInsert.app` to `~/Applications`)

### CI and docs

- `.github/workflows/voiceinsert-build.yml` — PR/push build
- `.github/workflows/release.yml` — tag `v*` → GitHub Release + `VoiceInsert-macos.zip`
- `README.md`
- `docs/index.html` — public landing (GitHub Pages from `/docs`) wired to `vushnevskuu/push-talk` releases
- `docs/`
- `LICENSE` — MIT (distribution)

### Agent / meta docs

- Root [`agent.md`](agent.md) — optional notes
- [`.agent/agents/`](.agent/agents/) — Cursor-style agent prompts (e.g. [`devops-engineer.md`](.agent/agents/devops-engineer.md), [`backend-specialist.md`](.agent/agents/backend-specialist.md)); **not** part of the shipped app — ignore for runtime unless the task is agent infra.

## Files requiring caution

- `Sources/VoiceInsertApp/App/AppModel.swift`
  - central integration point
- `Sources/VoiceInsertApp/Insertion/TextInsertionService.swift`
  - sensitive insertion behavior across apps
- `Sources/VoiceInsertApp/Hotkey/HotkeyMonitor.swift`
  - can break global shortcuts
- `Sources/VoiceInsertApp/Transcription/SpeechRecognitionService.swift`
  - affects startup latency, mic behavior, recognition quality
- `Memory/crash-memory.md`
  - update only for crash/postmortem work

## Architecture flow

1. `HotkeyMonitor.swift`
2. `AppModel.startHold(...)`
3. `SpeechRecognitionService.startSession(...)`
4. user releases shortcut
5. `AppModel.endHold(...)`
6. `SpeechRecognitionService.finishSession()`
7. result goes to:
   - `TextInsertionService.insert(...)`
   - or `ObsidianCaptureService.capture(...)`

## Agent write scopes

### Backend / core-runtime agent

Primary targets:

- `Sources/VoiceInsertApp/App/`
- `Sources/VoiceInsertApp/Transcription/`
- `Sources/VoiceInsertApp/Insertion/`
- `Sources/VoiceInsertApp/Permissions/`
- `Sources/VoiceInsertApp/Obsidian/`
- `Sources/VoiceInsertInjector/main.swift`

Avoid UI-only edits unless required for wiring.

### DevOps / release agent

Primary targets:

- `Scripts/build_app.sh`
- `Scripts/ensure_local_codesigning_identity.sh`
- `Resources/Info.plist`
- `.github/workflows/voiceinsert-build.yml`
- `.github/workflows/release.yml`
- `README.md`

Avoid product logic edits unless the task explicitly requires them.

### UI agent

Primary targets:

- `Sources/VoiceInsertApp/UI/`
- `Sources/VoiceInsertApp/App/AppModel.swift` only when UI state wiring is needed

## Directories usually ignored

- `.build/`
- `Build/`
- `Artifacts/`
- `.git/`
- `.cursor/debug-*.log`

## Preferred commands

Build and install:

```bash
./Scripts/build_app.sh
```

Install alternate flow:

```bash
./Scripts/install_voiceinsert_app.sh
```

Swift package build only:

```bash
swift build -c release --product VoiceInsert --product VoiceInsertInjector
```

Search:

```bash
rg "pattern" Sources Scripts Resources
```

## Runtime facts

- installed app path: `~/Applications/VoiceInsert.app`
- app type: menu bar app (`LSUIElement = true`)
- important permissions:
  - Microphone
  - Speech Recognition
  - Input Monitoring
  - Accessibility

## Public release reality

**Done in-repo:** GitHub Actions [`.github/workflows/release.yml`](.github/workflows/release.yml) publishes **`VoiceInsert-macos.zip`** (+ SHA-256) on tag push `v*`. See `README.md` for end-user install steps.

**Still optional for “best” macOS trust:**

- Public / stable **bundle identifier** (currently `local.codex.voiceinsert` in `Resources/Info.plist` — fine for ad hoc; change when using Developer ID)
- **Developer ID** signing + **notarization** (requires Apple Developer Program; secrets in repo settings)
- Universal binary or explicit **Intel** CI job if you must support x86_64 without local builds

## Safe default instructions for Cursor agents

- read this file first
- then read only the subsystem files relevant to the task
- avoid broad unrelated refactors
- if changing injection logic, review app + helper together
- do not edit generated folders
- do not stage unrelated local changes
