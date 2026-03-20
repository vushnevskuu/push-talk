import SwiftUI

struct RecordingHUDView: View {
    @ObservedObject var model: RecordingFeedbackModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.14), radius: 18, y: 10)

            HStack {
                Spacer(minLength: 0)
                VoiceWaveVisualizer(levels: model.visualizerLevels())
                    .frame(width: 184, height: 36)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .frame(width: 248, height: 72)
        .animation(.easeOut(duration: 0.12), value: model.audioLevel)
        .animation(.easeOut(duration: 0.12), value: model.audioLevelHistory)
    }
}

struct VoiceWaveVisualizer: View {
    let levels: [Double]

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: barColors(for: index),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 5, height: barHeight(for: level))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func barHeight(for level: Double) -> CGFloat {
        9 + (CGFloat(level) * 26)
    }

    private func barColors(for index: Int) -> [Color] {
        if index.isMultiple(of: 3) {
            return [
                Color(red: 0.95, green: 0.36, blue: 0.28),
                Color(red: 0.99, green: 0.62, blue: 0.28)
            ]
        }

        return [
            Color(red: 0.92, green: 0.29, blue: 0.25),
            Color(red: 0.98, green: 0.51, blue: 0.28)
        ]
    }
}
