import SwiftUI

struct RecordingHUDView: View {
    @ObservedObject var model: RecordingFeedbackModel
    let style: RecordingHUDStyle

    var body: some View {
        Group {
            switch style {
            case .glassBar:
                glassBarHUD
            case .compactOrb:
                compactOrbHUD
            case .bareWaves:
                bareWavesHUD
            }
        }
        .animation(.linear(duration: 0.05), value: model.audioLevel)
        .animation(.linear(duration: 0.05), value: model.audioLevelHistory)
    }

    private var glassBarHUD: some View {
        let corner = RoundedRectangle(cornerRadius: 22, style: .continuous)

        return ZStack {
            VoiceWaveVisualizer(levels: model.visualizerLevels(), style: style)
                .frame(width: 184, height: 36)
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .background {
                    ZStack {
                        corner.fill(.ultraThinMaterial)
                        corner.stroke(Color.white.opacity(0.18), lineWidth: 1)
                    }
                }
                .compositingGroup()
                .clipShape(corner)
                // Rounded blur instead of `.shadow` — rectangular shadow bbox was visible on light backgrounds.
                .background {
                    corner
                        .fill(Color.black.opacity(0.28))
                        .blur(radius: 14)
                        .offset(y: 9)
                        .opacity(0.75)
                }
        }
        .frame(width: style.panelSize.width, height: style.panelSize.height)
    }

    private var compactOrbHUD: some View {
        ZStack {
            GlassDropletSurface()

            compactOrbWaveCluster(levels: model.visualizerLevels(barCount: 5))
        }
        .frame(width: style.panelSize.width, height: style.panelSize.height)
        .compositingGroup()
        .clipShape(GlassDropletShape())
    }

    private var bareWavesHUD: some View {
        let cap = Capsule(style: .continuous)

        return VoiceWaveVisualizer(levels: model.visualizerLevels(), style: style)
            .frame(width: style.panelSize.width, height: style.panelSize.height)
            .compositingGroup()
            .clipShape(cap)
            .background {
                cap
                    .fill(Color.black.opacity(0.2))
                    .blur(radius: 10)
                    .offset(y: 4)
                    .opacity(0.7)
            }
    }
}

struct VoiceWaveVisualizer: View {
    let levels: [Double]
    var style: RecordingHUDStyle = .glassBar

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: barColors(for: index),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: barWidth, height: barHeight(for: level))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func barHeight(for level: Double) -> CGFloat {
        switch style {
        case .glassBar:
            return 9 + (CGFloat(level) * 26)
        case .compactOrb:
            return 7 + (CGFloat(level) * 15)
        case .bareWaves:
            return 8 + (CGFloat(level) * 22)
        }
    }

    private var barWidth: CGFloat {
        switch style {
        case .glassBar:
            return 5
        case .compactOrb:
            return 3.1
        case .bareWaves:
            return 5
        }
    }

    private var barSpacing: CGFloat {
        switch style {
        case .glassBar:
            return 5
        case .compactOrb:
            return 2.3
        case .bareWaves:
            return 6
        }
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

extension RecordingHUDView {
    @ViewBuilder
    private func compactOrbWaveCluster(levels: [Double]) -> some View {
        let maskShape = GlassDropletShape()
            .scaleEffect(x: 0.965, y: 0.965, anchor: .center)

        ZStack {
            OrbWaveField(levels: levels)
                .frame(width: 70, height: 64)

            OrbWaveField(levels: levels)
                .frame(width: 70, height: 64)
                .blur(radius: 2.6)
                .opacity(0.24)
        }
        .offset(y: 0.5)
        .mask(maskShape)
    }
}

struct OrbWaveField: View {
    let levels: [Double]
    var compact = false

    var body: some View {
        let metrics = compact ? compactMetrics : regularMetrics

        HStack(alignment: .center, spacing: metrics.spacing) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: barColors(for: index),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(
                        width: barWidth(for: level, index: index, count: levels.count, metrics: metrics),
                        height: barHeight(for: level, index: index, count: levels.count, metrics: metrics)
                    )
                    .opacity(barOpacity(for: index, count: levels.count))
                    .offset(
                        x: horizontalOffset(for: level, index: index, count: levels.count, metrics: metrics),
                        y: verticalOffset(for: level, index: index, count: levels.count, metrics: metrics)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var regularMetrics: OrbMetrics {
        OrbMetrics(
            width: 8.6,
            spacing: 2.6,
            minHeight: 34,
            amplitude: 20,
            widthAmplitude: 6.2,
            spreadAmplitude: 4.0,
            liftAmplitude: 3.2
        )
    }

    private var compactMetrics: OrbMetrics {
        OrbMetrics(
            width: 5.2,
            spacing: 2.0,
            minHeight: 15,
            amplitude: 12,
            widthAmplitude: 2.8,
            spreadAmplitude: 1.6,
            liftAmplitude: 1.6
        )
    }

    private func barWidth(for level: Double, index: Int, count: Int, metrics: OrbMetrics) -> CGFloat {
        let position = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 0.5
        let normalized = (position * 2) - 1
        let centerBias = 0.82 + (sqrt(max(0, 1 - (normalized * normalized))) * 0.18)
        let energy = CGFloat(level) * metrics.widthAmplitude
        return metrics.width + (energy * centerBias)
    }

    private func barHeight(for level: Double, index: Int, count: Int, metrics: OrbMetrics) -> CGFloat {
        let position = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 0.5
        let normalized = (position * 2) - 1
        let envelope = 0.84 + (sqrt(max(0, 1 - (normalized * normalized))) * 0.16)
        let energy = metrics.minHeight + (CGFloat(level) * metrics.amplitude)
        return max(metrics.minHeight, energy * envelope)
    }

    private func horizontalOffset(for level: Double, index: Int, count: Int, metrics: OrbMetrics) -> CGFloat {
        let position = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 0.5
        let normalized = (position * 2) - 1
        let spread = CGFloat(level) * metrics.spreadAmplitude
        return normalized * spread
    }

    private func verticalOffset(for level: Double, index: Int, count: Int, metrics: OrbMetrics) -> CGFloat {
        let position = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 0.5
        let normalized = 1 - abs((position * 2) - 1)
        let lift = CGFloat(level) * metrics.liftAmplitude
        return -(lift * normalized)
    }

    private func barOpacity(for index: Int, count: Int) -> Double {
        let position = count > 1 ? Double(index) / Double(count - 1) : 0.5
        let normalized = abs((position * 2) - 1)
        return 0.78 + ((1 - normalized) * 0.16)
    }

    private func barColors(for index: Int) -> [Color] {
        if index.isMultiple(of: 4) {
            return [
                Color(red: 1.0, green: 0.73, blue: 0.36),
                Color(red: 0.98, green: 0.44, blue: 0.30)
            ]
        }

        return [
            Color(red: 0.99, green: 0.60, blue: 0.30),
            Color(red: 0.93, green: 0.33, blue: 0.26)
        ]
    }
}

struct OrbMetrics {
    let width: CGFloat
    let spacing: CGFloat
    let minHeight: CGFloat
    let amplitude: CGFloat
    let widthAmplitude: CGFloat
    let spreadAmplitude: CGFloat
    let liftAmplitude: CGFloat
}
