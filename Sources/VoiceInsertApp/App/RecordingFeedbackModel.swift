import Foundation

@MainActor
final class RecordingFeedbackModel: ObservableObject {
    @Published private(set) var audioLevel = 0.0
    @Published private(set) var audioLevelHistory = Array(repeating: 0.08, count: 20)
    private var samplesAfterReset = 0

    func visualizerLevels(barCount: Int = 18) -> [Double] {
        let baseline = Array(repeating: 0.08, count: barCount)
        guard !audioLevelHistory.isEmpty else { return baseline }

        if audioLevelHistory.count >= barCount {
            return Array(audioLevelHistory.suffix(barCount))
        }

        return Array(repeating: 0.08, count: max(0, barCount - audioLevelHistory.count)) + audioLevelHistory
    }

    func push(level: Double) {
        let clampedLevel = min(max(level, 0), 1)
        samplesAfterReset += 1
        // First frames after reset: react faster so the HUD doesn’t look “dead” while mic/Bluetooth ramps up.
        let inertia: Double = samplesAfterReset <= 12 ? 0.35 : 0.15
        let smoothedLevel = max(0.04, (audioLevel * inertia) + (clampedLevel * (1 - inertia)))

        audioLevel = smoothedLevel
        audioLevelHistory.append(smoothedLevel)

        if audioLevelHistory.count > 28 {
            audioLevelHistory.removeFirst(audioLevelHistory.count - 28)
        }
    }

    func reset() {
        audioLevel = 0
        samplesAfterReset = 0
        audioLevelHistory = Array(repeating: 0.08, count: 20)
    }
}
