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

@MainActor
final class SpeechRecognitionService {
    private let audioEngine = AVAudioEngine()
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
    private var partialHandler: (@MainActor (String) -> Void)?
    private var sessionToken = UUID()

    func prewarm(locale: Locale) {
        _ = recognizer(for: locale)
    }

    func startSession(
        locale: Locale,
        addsPunctuation: Bool,
        partialHandler: @escaping @MainActor (String) -> Void,
        levelHandler: @escaping @MainActor (Double) -> Void
    ) throws {
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
        self.sessionToken = token
        persistDebugSnapshot(state: "session_started")
        self.recognitionTask = Self.makeRecognitionTask(
            recognizer: recognizer,
            request: request,
            owner: self,
            token: token
        )

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        if isTapInstalled {
            inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        Self.installInputTap(
            on: inputNode,
            format: format,
            request: request,
            levelHandler: { [weak self] level in
                self?.recordObservedAudioLevel(level)
                levelHandler(level)
            }
        )
        isTapInstalled = true

        audioEngine.prepare()

        do {
            try audioEngine.start()
            persistDebugSnapshot(state: "audio_engine_started")
        } catch {
            cleanupResources(cancelTask: true)
            persistDebugSnapshot(state: "audio_engine_start_failed", errorMessage: error.localizedDescription)
            throw SpeechRecognitionError.audioEngineBusy
        }
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
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
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

    nonisolated private static func installInputTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest,
        levelHandler: @escaping @MainActor (Double) -> Void
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 256, format: format) { buffer, _ in
            request.append(buffer)

            let level = normalizedAudioLevel(from: buffer)
            Task { @MainActor in
                levelHandler(level)
            }
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

    nonisolated private static func normalizedAudioLevel(from buffer: AVAudioPCMBuffer) -> Double {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        if let channelData = buffer.floatChannelData {
            let samples = channelData[0]
            var sum: Float = 0

            for index in 0..<frameLength {
                let sample = samples[index]
                sum += sample * sample
            }

            return normalizedLevel(fromRMS: sqrt(sum / Float(frameLength)))
        }

        if let channelData = buffer.int16ChannelData {
            let samples = channelData[0]
            var sum: Float = 0

            for index in 0..<frameLength {
                let sample = Float(samples[index]) / Float(Int16.max)
                sum += sample * sample
            }

            return normalizedLevel(fromRMS: sqrt(sum / Float(frameLength)))
        }

        return 0
    }

    nonisolated private static func normalizedLevel(fromRMS rms: Float) -> Double {
        let clampedRMS = max(rms, 0.000_01)
        let decibels = 20 * log10(clampedRMS)
        let normalized = (decibels + 52) / 52
        return Double(min(max(normalized, 0), 1))
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
