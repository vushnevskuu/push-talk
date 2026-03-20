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
