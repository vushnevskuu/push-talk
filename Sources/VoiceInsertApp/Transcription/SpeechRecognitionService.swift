import AVFoundation
import Foundation
import Speech

enum SpeechRecognitionError: LocalizedError {
    case recognizerUnavailable
    case audioEngineBusy

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition is unavailable for this language. Check System Settings → Keyboard → Dictation and download the language if needed."
        case .audioEngineBusy:
            return "Couldn't start microphone capture."
        }
    }
}

private struct RecognitionCallbackError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }
}

/// RMS → 0…1 meter level (shared by tap + any future call sites).
private enum TapAudioMath {
    nonisolated static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        if let channelData = buffer.floatChannelData {
            let samples = channelData[0]
            var sum: Float = 0
            for index in 0..<frameLength {
                let sample = samples[index]
                sum += sample * sample
            }
            return normalizedUnit(fromRMS: sqrt(sum / Float(frameLength)))
        }

        if let channelData = buffer.int16ChannelData {
            let samples = channelData[0]
            var sum: Float = 0
            for index in 0..<frameLength {
                let sample = Float(samples[index]) / Float(Int16.max)
                sum += sample * sample
            }
            return normalizedUnit(fromRMS: sqrt(sum / Float(frameLength)))
        }

        return 0
    }

    nonisolated private static func normalizedUnit(fromRMS rms: Float) -> Double {
        let clampedRMS = max(rms, 0.000_01)
        let decibels = 20 * log10(clampedRMS)
        let normalized = (decibels + 52) / 52
        return Double(min(max(normalized, 0), 1))
    }
}

/// Bridges real-time audio thread → optional recognition request without reinstalling `installTap`
/// (repeated remove/install caused Core Audio I/O glitches in other apps’ playback, e.g. Bluetooth).
private final class InputAudioTapBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    /// Must be `@Sendable`: `installTap` runs on a realtime queue — never store a `@MainActor` closure here (Swift 6 traps).
    private var onLevel: (@Sendable (Double) -> Void)?

    func setPipe(request: SFSpeechAudioBufferRecognitionRequest?, onLevel: (@Sendable (Double) -> Void)?) {
        lock.lock()
        self.request = request
        self.onLevel = onLevel
        lock.unlock()
    }

    func process(buffer: AVAudioPCMBuffer) {
        lock.lock()
        let req = request
        let handler = onLevel
        lock.unlock()

        if let req {
            req.append(buffer)
        }

        if let handler {
            let level = TapAudioMath.normalizedLevel(from: buffer)
            handler(level)
        }
    }
}

/// `AVAudioNode.installTap` invokes this from a **realtime** queue. Closures created inside `@MainActor` methods inherit
/// MainActor isolation and trap at runtime under Swift 6 (`_swift_task_checkIsolatedSwift`).
private func voiceInsertInputTapBlock(bridge: InputAudioTapBridge) -> AVAudioNodeTapBlock {
    { buffer, _ in
        bridge.process(buffer: buffer)
    }
}

@MainActor
final class SpeechRecognitionService {
    private let audioEngine = AVAudioEngine()
    private let tapBridge = InputAudioTapBridge()
    /// Keeps a single `installTap` across sessions (avoids BT/IO glitches on reinstall) but **does not** leave
    /// `AVAudioEngine` running while idle — that was grabbing the mic continuously and disturbed system playback.
    private let keepInputWarmBetweenSessions = true
    private var isTapInstalled = false
    private var cachedRecognizer: SFSpeechRecognizer?
    private var cachedLocaleIdentifier: String?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var finishContinuation: CheckedContinuation<String, Error>?
    private var finishTimeoutTask: Task<Void, Never>?
    private var deferredResult: Result<String, Error>?
    private var lastTranscript = ""
    private var lastRecognitionUpdateAt = Date.distantPast
    private var finishWaitStartedAt = Date.distantPast
    private var observedAudioSignal = false
    private var peakAudioLevel: Double = 0
    private var sessionStartedAt = Date.distantPast
    private var audioCaptureStartedAt = Date.distantPast
    private var recognitionTaskStartedAt = Date.distantPast
    private var firstObservedAudioSignalAt = Date.distantPast
    private var partialHandler: (@MainActor (String) -> Void)?
    private var sessionToken = UUID()
    /// Defers `audioEngine.stop()` so a quick second dictation reuses a running engine — fewer I/O route toggles
    /// (less “jumping” in other apps). Cancels whenever a new session starts.
    private var deferredEngineStopGeneration: UInt64 = 0
    private var deferredEngineStopTask: Task<Void, Never>?

    func prewarm(locale: Locale) {
        _ = recognizer(for: locale)
    }

    /// Cheap graph prep only — no input tap, no `start()`. Starting capture at launch kept the mic open and made
    /// other apps’ audio (Bluetooth especially) stutter or “jump”.
    func prepareInputGraphIfIdle() {
        guard recognitionRequest == nil, recognitionTask == nil else { return }
        audioEngine.prepare()
    }

    func startSession(
        locale: Locale,
        addsPunctuation: Bool,
        partialHandler: @escaping @MainActor (String) -> Void,
        levelHandler: @escaping @MainActor (Double) -> Void
    ) throws {
        cancelDeferredEngineStop()

        cancelSession()

        let recognizer = recognizer(for: locale)

        guard recognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        if #available(macOS 13.0, *) {
            request.addsPunctuation = addsPunctuation
        }

        let token = UUID()

        self.recognitionRequest = request
        self.partialHandler = partialHandler
        self.lastTranscript = ""
        self.deferredResult = nil
        self.lastRecognitionUpdateAt = Date.distantPast
        self.finishWaitStartedAt = Date.distantPast
        self.observedAudioSignal = false
        self.peakAudioLevel = 0
        self.sessionStartedAt = Date()
        self.audioCaptureStartedAt = Date.distantPast
        self.recognitionTaskStartedAt = Date.distantPast
        self.firstObservedAudioSignalAt = Date.distantPast
        self.sessionToken = token
        persistDebugSnapshot(state: "session_started")

        tapBridge.setPipe(request: request, onLevel: { @Sendable level in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recordObservedAudioLevel(level)
                levelHandler(level)
            }
        })

        audioEngine.prepare()
        let wasWarm = audioEngine.isRunning

        do {
            try ensureUnifiedInputTapAndEngineStarted()
            if !wasWarm {
                try audioEngine.start()
                audioCaptureStartedAt = Date()
                persistDebugSnapshot(state: "audio_engine_started")
            } else {
                audioCaptureStartedAt = sessionStartedAt
                persistDebugSnapshot(state: "audio_engine_reused_warm")
            }
        } catch {
            cleanupResources(cancelTask: true)
            persistDebugSnapshot(state: "audio_engine_start_failed", errorMessage: error.localizedDescription)
            throw SpeechRecognitionError.audioEngineBusy
        }

        recognitionTask = Self.makeRecognitionTask(
            recognizer: recognizer,
            request: request,
            owner: self,
            token: token
        )
        recognitionTaskStartedAt = Date()
        persistDebugSnapshot(state: "recognition_task_started")
    }

    func finishSession() async throws -> String {
        stopAudioCapture()
        recognitionRequest?.endAudio()
        try? await Task.sleep(for: .milliseconds(80))
        persistDebugSnapshot(state: "awaiting_recognition_result")

        if let deferredResult {
            self.deferredResult = nil
            cleanupResources(cancelTask: true)
            return try deferredResult.get()
        }

        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            finishWaitStartedAt = Date()
            scheduleFinishTimeout(for: sessionToken)
        }
    }

    func cancelSession() {
        finishTimeoutTask?.cancel()
        finishTimeoutTask = nil

        if let finishContinuation {
            self.finishContinuation = nil
            finishContinuation.resume(throwing: CancellationError())
        }

        cleanupResources(cancelTask: true)
        deferredResult = nil
        lastTranscript = ""
        lastRecognitionUpdateAt = Date.distantPast
        finishWaitStartedAt = Date.distantPast
        observedAudioSignal = false
        peakAudioLevel = 0
        sessionStartedAt = Date.distantPast
        audioCaptureStartedAt = Date.distantPast
        recognitionTaskStartedAt = Date.distantPast
        firstObservedAudioSignalAt = Date.distantPast
        persistDebugSnapshot(state: "session_cancelled")
    }

    private func processRecognitionText(_ text: String, isFinal: Bool) {
        lastRecognitionUpdateAt = Date()

        if !text.isEmpty {
            lastTranscript = text
        }

        partialHandler?(text)
        persistDebugSnapshot(
            state: isFinal ? "recognition_final" : "recognition_partial",
            transcriptPreview: text
        )

        if isFinal {
            resolveFinish(with: .success(text))
        }
    }

    private func processRecognitionFailure(message: String) {
        persistDebugSnapshot(state: "recognition_error", errorMessage: message)
        resolveFinish(with: .failure(RecognitionCallbackError(message: message)))
    }

    private func resolveFinish(with result: Result<String, Error>) {
        finishTimeoutTask?.cancel()
        finishTimeoutTask = nil
        cleanupResources(cancelTask: true)

        persistDebugSnapshot(
            state: {
                switch result {
                case .success:
                    return "session_resolved_success"
                case .failure:
                    return "session_resolved_error"
                }
            }(),
            transcriptPreview: {
                switch result {
                case .success(let text):
                    return text
                case .failure:
                    return nil
                }
            }(),
            errorMessage: {
                switch result {
                case .success:
                    return nil
                case .failure(let error):
                    return error.localizedDescription
                }
            }()
        )

        if let finishContinuation {
            self.finishContinuation = nil
            finishContinuation.resume(with: result)
        } else {
            deferredResult = result
        }
    }

    private func stopAudioCapture() {
        tapBridge.setPipe(request: nil, onLevel: nil)

        if keepInputWarmBetweenSessions {
            do {
                try ensureUnifiedInputTapAndEngineStarted()
            } catch {
                cancelDeferredEngineStop()
                teardownInputCapture()
                persistDebugSnapshot(state: "idle_warmup_restore_failed", errorMessage: error.localizedDescription)
                return
            }
            scheduleDeferredEngineStopIfRunning()
        } else {
            cancelDeferredEngineStop()
            teardownInputCapture()
        }
    }

    private func cancelDeferredEngineStop() {
        deferredEngineStopTask?.cancel()
        deferredEngineStopTask = nil
        deferredEngineStopGeneration &+= 1
    }

    private func scheduleDeferredEngineStopIfRunning() {
        guard audioEngine.isRunning else {
            persistDebugSnapshot(state: "capture_stopped_warm")
            return
        }
        deferredEngineStopTask?.cancel()
        let generation = deferredEngineStopGeneration
        deferredEngineStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard self.deferredEngineStopGeneration == generation else { return }
            guard self.recognitionRequest == nil, self.recognitionTask == nil else { return }
            if self.audioEngine.isRunning {
                self.audioEngine.stop()
            }
            self.persistDebugSnapshot(state: "capture_stopped_warm")
        }
        persistDebugSnapshot(state: "capture_stop_deferred")
    }

    private func cleanupResources(cancelTask: Bool) {
        stopAudioCapture()

        if cancelTask {
            recognitionTask?.cancel()
        }

        recognitionTask = nil
        recognitionRequest = nil
        partialHandler = nil
    }

    private func recordObservedAudioLevel(_ level: Double) {
        peakAudioLevel = max(peakAudioLevel, level)

        if level > 0.015 {
            observedAudioSignal = true
            if firstObservedAudioSignalAt == .distantPast {
                firstObservedAudioSignalAt = Date()
            }
        }
    }

    private func scheduleFinishTimeout(for token: UUID) {
        finishTimeoutTask?.cancel()
        finishTimeoutTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))

                guard self.sessionToken == token else { return }
                guard self.finishContinuation != nil else { return }

                let waited = Date().timeIntervalSince(self.finishWaitStartedAt)

                if !self.lastTranscript.isEmpty,
                   self.lastRecognitionUpdateAt != .distantPast,
                   Date().timeIntervalSince(self.lastRecognitionUpdateAt) >= 0.35 {
                    self.resolveFinish(
                        with: .success(
                            self.lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    )
                    return
                }

                let maxWait = self.observedAudioSignal ? 2.0 : 1.5
                if waited >= maxWait {
                    let text = self.lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty, !self.observedAudioSignal {
                        self.persistDebugSnapshot(state: "no_audio_detected")
                        self.resolveFinish(
                            with: .failure(
                                RecognitionCallbackError(
                                    message: "No microphone audio was detected. Check the active input device and try again."
                                )
                            )
                        )
                        return
                    }
                    self.persistDebugSnapshot(
                        state: "finish_timeout",
                        transcriptPreview: text.isEmpty ? nil : text
                    )
                    self.resolveFinish(with: .success(text))
                    return
                }
            }
        }
    }

    /// Single `installTap` for the process lifetime (when warm path is on) to avoid Core Audio I/O teardown
    /// that audibly glitches system playback on many devices. Callers decide when to `start()` / `stop()` the engine.
    private func ensureUnifiedInputTapAndEngineStarted() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        if !isTapInstalled {
            inputNode.installTap(
                onBus: 0,
                bufferSize: 512,
                format: format,
                block: voiceInsertInputTapBlock(bridge: tapBridge)
            )
            isTapInstalled = true
        }

        audioEngine.prepare()
    }

    private func teardownInputCapture() {
        cancelDeferredEngineStop()
        tapBridge.setPipe(request: nil, onLevel: nil)

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
    }

    nonisolated private static func makeRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        owner: SpeechRecognitionService,
        token: UUID
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { [weak owner] result, error in
            let hasResult = result != nil
            let text = result?.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isFinal = result?.isFinal ?? false
            let errorMessage = error.map { ($0 as NSError).localizedDescription }

            Task { @MainActor [weak owner] in
                guard let owner else { return }
                guard owner.sessionToken == token else { return }

                if hasResult {
                    owner.processRecognitionText(text, isFinal: isFinal)
                    if isFinal {
                        return
                    }
                }

                if let errorMessage {
                    owner.processRecognitionFailure(message: errorMessage)
                }
            }
        }
    }

    private func recognizer(for locale: Locale) -> SFSpeechRecognizer {
        if cachedLocaleIdentifier == locale.identifier, let cachedRecognizer {
            return cachedRecognizer
        }

        let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()!
        cachedRecognizer = recognizer
        cachedLocaleIdentifier = locale.identifier
        return recognizer
    }

    private func persistDebugSnapshot(
        state: String,
        transcriptPreview: String? = nil,
        errorMessage: String? = nil
    ) {
        var parts = [
            "state=\(state)",
            "peakAudioLevel=\(String(format: "%.3f", peakAudioLevel))",
            "observedAudioSignal=\(observedAudioSignal)"
        ]

        if lastRecognitionUpdateAt != .distantPast {
            parts.append(
                "secondsSinceLastRecognition=\(String(format: "%.2f", Date().timeIntervalSince(lastRecognitionUpdateAt)))"
            )
        }

        if sessionStartedAt != .distantPast {
            parts.append(
                "sessionAge=\(String(format: "%.2f", Date().timeIntervalSince(sessionStartedAt)))"
            )
        }

        if audioCaptureStartedAt != .distantPast, sessionStartedAt != .distantPast {
            parts.append(
                "audioStartDelayMs=\(Int(audioCaptureStartedAt.timeIntervalSince(sessionStartedAt) * 1000))"
            )
        }

        if recognitionTaskStartedAt != .distantPast, sessionStartedAt != .distantPast {
            parts.append(
                "recognitionTaskDelayMs=\(Int(recognitionTaskStartedAt.timeIntervalSince(sessionStartedAt) * 1000))"
            )
        }

        if firstObservedAudioSignalAt != .distantPast, sessionStartedAt != .distantPast {
            parts.append(
                "firstAudioSignalDelayMs=\(Int(firstObservedAudioSignalAt.timeIntervalSince(sessionStartedAt) * 1000))"
            )
        }

        if finishWaitStartedAt != .distantPast {
            parts.append(
                "finishWait=\(String(format: "%.2f", Date().timeIntervalSince(finishWaitStartedAt)))"
            )
        }

        if let transcriptPreview = transcriptPreview?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !transcriptPreview.isEmpty {
            parts.append("transcript=\(transcriptPreview.replacingOccurrences(of: "\n", with: " "))")
        }

        if let errorMessage = errorMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !errorMessage.isEmpty {
            parts.append("error=\(errorMessage.replacingOccurrences(of: "\n", with: " "))")
        }

        UserDefaults.standard.set(parts.joined(separator: ";"), forKey: SpeechDebugDefaults.lastSpeechDebug)
    }
}

private enum SpeechDebugDefaults {
    static let lastSpeechDebug = "voiceInsert.lastSpeechDebug"
}
