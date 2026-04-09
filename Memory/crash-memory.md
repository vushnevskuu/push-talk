# Crash Memory

Append-only project memory for crash triage, fixes, and verification.

Use this file to preserve:
- what crashed
- where it crashed
- the suspected or confirmed root cause
- the code change that fixed it
- the verification run that proved the fix

## Incident 2026-03-19 12:13:36 +07

- Status: `verified`
- Report: `/Users/vishnevsky/Library/Logs/DiagnosticReports/VoiceInsert-2026-03-19-121336.ips`
- Symptom: app crashed around permission flow after initial setup.
- Suspected root cause: actor-isolation violation while handling Speech Recognition permission callback on a non-main executor.
- Affected area: `PermissionManager.requestSpeechPermission()`
- Fix: permission callbacks were moved into async helpers outside the `@MainActor` boundary so system callbacks no longer touched main-isolated state incorrectly.
- Verification: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-122718/report.json`

## Incident 2026-03-19 12:25:11 +07

- Status: `verified`
- Report: `/Users/vishnevsky/Library/Logs/DiagnosticReports/VoiceInsert-2026-03-19-122511.ips`
- Symptom: repeated crash after permissions dialog flow.
- Suspected root cause: same permission callback isolation bug path as the earlier 12:13 crash.
- Affected area: `PermissionManager.swift`
- Fix: same callback isolation fix stayed in place and later smoke tests stopped generating new crash reports for that path.
- Verification: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-122718/report.json`

## Incident 2026-03-19 13:17:08 +07

- Status: `verified`
- Report: `/Users/vishnevsky/Library/Logs/DiagnosticReports/VoiceInsert-2026-03-19-131708.ips`
- Faulting thread: `6`
- Top app frame: `VoiceInsert -> closure #1 in SpeechRecognitionService.startSession(locale:addsPunctuation:partialHandler:levelHandler:) +188`
- Symptom: app crashed during live microphone capture while holding to dictate.
- Confirmed root cause: realtime `AVAudioEngine.installTap` callback touched `@MainActor` state through `self?.recognitionRequest` / `self?.levelHandler` and hit `dispatch_assert_queue` / `swift_task_checkIsolatedSwift`.
- Affected area: `Sources/VoiceInsertApp/Transcription/SpeechRecognitionService.swift`
- Fix: tap callback now captures the request and main-actor sink explicitly, avoids touching actor-isolated service state from the realtime audio thread, and uses `nonisolated` audio-level helpers.
- Verification: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-131922/report.json`

## Incident 2026-03-19 13:17:28 +07

- Status: `verified`
- Report: `/Users/vishnevsky/Library/Logs/DiagnosticReports/VoiceInsert-2026-03-19-131728.ips`
- Faulting thread: `3`
- Top app frame: `VoiceInsert -> closure #1 in SpeechRecognitionService.startSession(locale:addsPunctuation:partialHandler:levelHandler:) +188`
- Symptom: second reproduction of the same live audio crash path.
- Confirmed root cause: same realtime audio tap isolation bug as the 13:17:08 incident.
- Affected area: `Sources/VoiceInsertApp/Transcription/SpeechRecognitionService.swift`
- Fix: same audio callback isolation fix.
- Verification: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-131922/report.json`

## Latest Verification 2026-03-19 13:19:22 +07

- Status: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-131922`
- New crash reports: `0`
- Remaining warning: `tcc_signature_risk`
- Meaning: crash path is currently closed in smoke testing, but ad-hoc signing can still make permission state unstable across rebuilds.

## Run 2026-03-19 13:26:15
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-132605`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 13:29:51
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-132941`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Incident 2026-03-19 13:21:47 +07 and 2026-03-19 13:26:55 +07

- Status: `smoke-verified, manual hold-to-talk retest pending`
- Reports:
  - `/Users/vishnevsky/Library/Logs/DiagnosticReports/VoiceInsert-2026-03-19-132151.ips`
  - `/Users/vishnevsky/Library/Logs/DiagnosticReports/VoiceInsert-2026-03-19-132659.ips`
- Faulting threads:
  - `3`
  - `12`
- Top app frame: `VoiceInsert -> closure #1 in SpeechRecognitionService.startSession(locale:addsPunctuation:partialHandler:levelHandler:) +196`
- Symptom: app still crashed immediately after starting live microphone capture, even after the earlier audio callback patch.
- Confirmed root cause: the tap and speech-recognition callbacks were still being created inside a `@MainActor` method, so the closures themselves retained actor isolation. On top of that, the recognition callback still tried to bridge non-sendable Speech framework objects across the main-actor hop.
- Affected area: `Sources/VoiceInsertApp/Transcription/SpeechRecognitionService.swift`
- Fix:
  - moved tap installation into a `nonisolated` helper
  - moved `recognitionTask` callback creation into a `nonisolated` helper
  - converted recognition callback payload to sendable primitives (`text`, `isFinal`, `errorMessage`) before hopping back to `@MainActor`
- Verification:
  - build/install succeeded
  - smoke test produced no new crash reports in `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-132941/report.json`
  - manual live dictation retest on the hold-to-talk path is still needed because the smoke test does not simulate real microphone capture

## Incident 2026-03-19 13:31:06 +07

- Status: `smoke-verified, manual hold-to-talk retest pending`
- Report: `/Users/vishnevsky/Library/Logs/DiagnosticReports/VoiceInsert-2026-03-19-133111.ips`
- Faulting thread: `0`
- Top app frame: `VoiceInsert -> closure #1 in VoiceInsertApp.body.getter +120`
- Symptom: after starting dictation, the app appeared not to hear the user and then crashed on the main thread.
- Suspected root cause: high-frequency `@Published` updates for live audio visualization were still flowing through the global `AppModel`, which forced repeated SwiftUI invalidation of the `MenuBarExtra` scene during recording and eventually crashed inside the app scene/body closure.
- Affected area:
  - `Sources/VoiceInsertApp/App/AppModel.swift`
  - `Sources/VoiceInsertApp/UI/RecordingHUDController.swift`
  - `Sources/VoiceInsertApp/UI/RecordingHUDView.swift`
  - `Sources/VoiceInsertApp/App/RecordingFeedbackModel.swift`
- Fix:
  - moved audio waveform state out of `AppModel` into a dedicated `RecordingFeedbackModel`
  - attached the top HUD directly to `RecordingFeedbackModel`
  - stopped publishing partial transcript text through the shared `AppModel` during recording
- Verification:
  - build/install succeeded
  - smoke test produced no new crash reports in `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-133439/report.json`
  - manual hold-to-talk retest is still required because the smoke test does not exercise real mic capture

## Run 2026-03-19 13:34:52
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-133439`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 13:40:41
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-134029`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 13:42:56
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-134244`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 13:54:22
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-135410`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 13:55:34
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-135519`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 13:58:04
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-135749`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 15:34:50
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-153434`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 15:48:45
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-154830`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 15:50:45
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-155032`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 15:52:54
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-155239`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 15:54:43
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-155427`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 15:57:24
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-155708`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 16:03:26
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-160311`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 16:25:16
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-162504`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 16:26:30
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-162619`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 16:36:29
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-163617`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 16:44:15
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-164403`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 16:56:58
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-165646`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 16:58:32
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-165821`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 17:05:01
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-170449`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 17:24:12
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-172400`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 17:32:54
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-173242`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 17:36:12
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-173556`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 21:31:35
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-213118`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 21:59:50
- Result: `fail`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-215930`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 22:00:35
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-220022`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 22:07:40
- Result: `fail`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-220725`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 22:10:25
- Result: `fail`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-221009`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 22:13:35
- Result: `fail`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-221322`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 22:22:19
- Result: `fail`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-222204`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 22:37:42
- Result: `fail`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-223728`
- New crash reports: `0`
- Warnings: `tcc_signature_risk`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 22:38:40
- Result: `fail`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-223826`
- New crash reports: `0`
- Warnings: `none`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 22:39:15
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-223902`
- New crash reports: `0`
- Warnings: `none`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 22:41:00
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-224047`
- New crash reports: `0`
- Warnings: `none`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 22:42:04
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-224151`
- New crash reports: `0`
- Warnings: `none`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 22:51:18
- Result: `pass`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-225104`
- New crash reports: `0`
- Warnings: `none`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 22:57:05
- Result: `pass`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-225651`
- New crash reports: `0`
- Warnings: `none`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 22:59:17
- Result: `pass`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-225903`
- New crash reports: `0`
- Warnings: `none`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 23:04:00
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-230339`
- New crash reports: `0`
- Warnings: `none`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 23:05:26
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-230506`
- New crash reports: `0`
- Warnings: `none`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-19 23:06:51
- Result: `pass`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260319-230633`
- New crash reports: `0`
- Warnings: `none`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-20 07:34:32
- Result: `pass`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260320-073413`
- New crash reports: `0`
- Warnings: `none`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-20 08:14:29
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260320-081412`
- New crash reports: `0`
- Warnings: `none`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-20 08:15:21
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260320-081505`
- New crash reports: `0`
- Warnings: `none`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-20 08:15:50
- Result: `pass`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260320-081534`
- New crash reports: `0`
- Warnings: `none`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-20 08:22:33
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260320-082212`
- New crash reports: `0`
- Warnings: `none`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-20 08:23:42
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260320-082320`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-20 08:29:56
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260320-082935`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-20 08:37:53
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260320-083731`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-20 08:40:52
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260320-084031`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-20 08:44:32
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260320-084411`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-20 12:07:14
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260320-120652`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-20 14:57:01
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260320-145639`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-20 15:13:22
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260320-151301`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 09:05:01
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-090440`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 09:10:46
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-091026`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 09:13:22
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-091302`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 09:15:52
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-091532`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 09:19:56
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-091936`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 09:24:11
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-092349`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 09:28:50
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-092830`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 09:42:44
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-094224`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 09:48:04
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-094744`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 09:53:52
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-095331`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 09:58:16
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-095756`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 10:02:32
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-100211`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 10:08:30
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-100809`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 10:10:43
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-101023`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 10:13:42
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-101317`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 10:26:01
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-102533`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 12:55:31
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-125503`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Incident 2026-03-21 12:52-12:53
- Reports:
  - `/Users/vishnevsky/Library/Logs/DiagnosticReports/VoiceInsert-2026-03-21-125247.ips`
  - `/Users/vishnevsky/Library/Logs/DiagnosticReports/VoiceInsert-2026-03-21-125310.ips`
- Additional repeat:
  - `/Users/vishnevsky/Library/Logs/DiagnosticReports/VoiceInsert-2026-03-21-125744.ips`
- Symptom: app crashed right after switching headphones / audio device.
- Signature: `EXC_BAD_ACCESS` on `com.apple.main-thread` in `VoiceInsertApp.body.getter`, inside `MenuBarExtra` content closure.
- Root cause: SwiftUI `MenuBarExtra` itself was the unstable path. It could re-render during system/menu-bar status churn around Bluetooth audio route changes, and the scene closure repeatedly crashed in `VoiceInsertApp.body`.
- Final fix: removed `MenuBarExtra` entirely and moved menu bar UI to AppKit `NSStatusItem` + `NSPopover`.
  - `/Users/vishnevsky/Desktop/голосовое управление/Sources/VoiceInsertApp/App/VoiceInsertApp.swift`
  - `/Users/vishnevsky/Desktop/голосовое управление/Sources/VoiceInsertApp/App/AppDelegate.swift`
  - `/Users/vishnevsky/Desktop/голосовое управление/Sources/VoiceInsertApp/App/AppRuntime.swift`
  - `/Users/vishnevsky/Desktop/голосовое управление/Sources/VoiceInsertApp/UI/MenuBarStatusItemController.swift`
- Verification:
  - the intermediate `MainActor.assumeIsolated` attempt did not fully fix the crash and the repeat report at `12:57:44 +07` confirmed that.
  - `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-125943` then reported `new_reports: []` after the AppKit status item rewrite.

## Run 2026-03-21 13:00:12
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-125943`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 13:03:12
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-130246`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Incident 2026-03-21 13:01
- Report:
  - `/Users/vishnevsky/Library/Logs/DiagnosticReports/VoiceInsert-2026-03-21-130129.ips`
- Symptom: first dictation worked, second dictation attempt crashed the app.
- Signature: `EXC_BAD_ACCESS` / `SIGBUS` on `com.apple.main-thread` in `closure #1 in TextInsertionService.installMouseTracking()`.
- Root cause: the global/local mouse monitor forwarded a live `NSEvent` into `Task { @MainActor ... }`. That event object was unsafe to carry across the async hop and could be invalid by the time the main-actor task touched it.
- Fix:
  - replaced the async handoff of `NSEvent` with a small sendable snapshot carrying only the click location
  - updated `/Users/vishnevsky/Desktop/голосовое управление/Sources/VoiceInsertApp/Insertion/TextInsertionService.swift`
- Verification:
  - `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-130246` reported `new_reports: []` after rebuild and install
  - remaining autotest failure in that run was the unrelated `voiceinsert_codex_insertion_failed` check, not a crash

## Incident 2026-03-21 13:04
- Report:
  - `/Users/vishnevsky/Library/Logs/DiagnosticReports/VoiceInsert-2026-03-21-130414.ips`
- Symptom: the same second-dictation crash reproduced again immediately after the first mouse-tracking patch.
- Signature: `EXC_BAD_ACCESS` / `SIGBUS` on `com.apple.main-thread` in `closure #1 in TextInsertionService.installMouseTracking()`.
- Refined root cause: even after replacing `NSEvent` with a sendable snapshot, the mouse-monitor callback path still inherited actor isolation because the intermediate sink closure was created inside the `@MainActor` service method and then re-used by the AppKit monitor factories.
- Final fix:
  - removed the intermediate sink closure created inside `installMouseTracking()`
  - moved the `Task { @MainActor ... }` hop directly into nonisolated static monitor factory closures
  - kept only a sendable `MouseDownSample` crossing the callback boundary
  - updated `/Users/vishnevsky/Desktop/голосовое управление/Sources/VoiceInsertApp/Insertion/TextInsertionService.swift`
- Verification:
  - `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-130832` reported `new_reports: []` after rebuild, install, and relaunch
  - remaining warning in that run was only `voiceinsert_hotkey_activation_inconclusive`, not a crash

## Run 2026-03-21 13:05:44
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-130518`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 13:08:57
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-130832`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 13:14:16
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-131349`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-21 13:20:44
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260321-132018`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 17:08:49
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-170556`
- New crash reports: `0`
- Warnings: `tcc_signature_risk, voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 18:39:18
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-183853`
- New crash reports: `0`
- Warnings: `tcc_signature_risk, voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 18:42:37
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-184216`
- New crash reports: `0`
- Warnings: `tcc_signature_risk, voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 18:46:07
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-184544`
- New crash reports: `0`
- Warnings: `tcc_signature_risk, voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 18:46:49
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-184627`
- New crash reports: `0`
- Warnings: `tcc_signature_risk, voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 18:48:02
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-184741`
- New crash reports: `0`
- Warnings: `tcc_signature_risk, voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 18:50:06
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-184944`
- New crash reports: `0`
- Warnings: `tcc_signature_risk, voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 18:50:54
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-185033`
- New crash reports: `0`
- Warnings: `tcc_signature_risk, voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 18:52:31
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-185210`
- New crash reports: `0`
- Warnings: `tcc_signature_risk, voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 18:54:51
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-185427`
- New crash reports: `0`
- Warnings: `tcc_signature_risk, voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 18:59:34
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-185913`
- New crash reports: `0`
- Warnings: `tcc_signature_risk, voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 19:00:31
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-190009`
- New crash reports: `0`
- Warnings: `tcc_signature_risk, voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 19:02:30
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-190207`
- New crash reports: `0`
- Warnings: `tcc_signature_risk, voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 19:13:07
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-191242`
- New crash reports: `0`
- Warnings: `tcc_signature_risk, voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 19:20:23
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-191959`
- New crash reports: `0`
- Warnings: `tcc_signature_risk, voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 19:22:44
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-192219`
- New crash reports: `0`
- Warnings: `tcc_signature_risk, voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 20:14:53
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-201408`
- New crash reports: `0`
- Warnings: `none`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 20:37:52
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-203723`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 21:04:08
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-210341`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-03-30 21:09:26
- Result: `fail`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260330-210900`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Incident 2026-04-07 17:43:34 +07

- Status: `verified` (see below — required two fixes)
- Report: `VoiceInsert-2026-04-07-174334.ips`, `VoiceInsert-2026-04-07-174559.ips`, …
- Faulting thread: `RealtimeMessenger.mServiceQueue` (audio tap)
- Top app frame: `closure #1 in SpeechRecognitionService.ensureUnifiedInputTapAndEngineStarted()`
- Symptom: immediate `EXC_BREAKPOINT` / `_dispatch_assert_queue_fail` → `_swift_task_checkIsolatedSwift` when buffers hit the tap.
- Confirmed root cause (full): (1) **`installTap`’s block** was a closure literal inside a `@MainActor` method, so it inherited MainActor isolation even though only `tapBridge.process` ran there. (2) Separately, the level sink must not be a MainActor closure stored for realtime invocation — use `@Sendable` + `Task { @MainActor … }`.
- Affected area: `Sources/VoiceInsertApp/Transcription/SpeechRecognitionService.swift`
- Fix: (1) `onLevel` as `@Sendable (Double) -> Void` with `{ @Sendable level in Task { @MainActor … } }`. (2) File-scope `voiceInsertInputTapBlock(bridge:)` returning `AVAudioNodeTapBlock` so the tap block is **not** formed inside the actor type.
- Verification: `Artifacts/macos-app-autotest/20260407-174715/report.json` — `crashes.new_reports`: `[]`, `issues`: `[]`; build via `./Scripts/build_app.sh`, test app `~/Applications/VoiceInsert.app`.

## Run 2026-04-07 17:47:48
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Applications/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260407-174715`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.

## Run 2026-04-08 15:19:26
- Result: `pass_with_warnings`
- App: `/Users/vishnevsky/Desktop/голосовое управление/Build/VoiceInsert.app`
- Artifacts: `/Users/vishnevsky/Desktop/голосовое управление/Artifacts/macos-app-autotest/20260408-151857`
- New crash reports: `0`
- Warnings: `voiceinsert_hotkey_activation_inconclusive`
- Crash triage: no new crash reports in this run.
- Follow-up: enrich this entry with root cause, fix commit/files, and post-fix verification before closing the incident.
