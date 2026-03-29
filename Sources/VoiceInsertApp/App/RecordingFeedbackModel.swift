import Foundation

@MainActor
final class RecordingFeedbackModel: ObservableObject {
    @Published private(set) var audioLevel = 0.0
    @Published private(set) var audioLevelHistory = Array(repeating: 0.08, count: 20)

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
        let smoothedLevel = max(0.04, (audioLevel * 0.15) + (clampedLevel * 0.85))

        audioLevel = smoothedLevel
        audioLevelHistory.append(smoothedLevel)

        if audioLevelHistory.count > 28 {
            audioLevelHistory.removeFirst(audioLevelHistory.count - 28)
        }
    }

    func reset() {
        audioLevel = 0
        audioLevelHistory = Array(repeating: 0.08, count: 20)
    }
}
