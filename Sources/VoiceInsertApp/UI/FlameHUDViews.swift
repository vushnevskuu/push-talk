import SwiftUI

// MARK: - Flame tongue (replaces capsule bars for the “flameBar” HUD style)

/// Teardrop flame silhouette; `wiggle` skews the tip for organic motion.
struct FlameShape: Shape {
    var wiggle: CGFloat

    var animatableData: CGFloat {
        get { wiggle }
        set { wiggle = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let tipX = rect.midX + wiggle * w * 0.35
        let leftBase = CGPoint(x: rect.minX + w * 0.12, y: rect.maxY)
        let rightBase = CGPoint(x: rect.maxX - w * 0.12, y: rect.maxY)
        let tip = CGPoint(x: tipX, y: rect.minY + h * 0.02)

        path.move(to: leftBase)
        path.addCurve(
            to: tip,
            control1: CGPoint(x: rect.minX - w * 0.08, y: rect.minY + h * 0.62),
            control2: CGPoint(x: tipX - w * 0.28, y: rect.minY + h * 0.22)
        )
        path.addCurve(
            to: rightBase,
            control1: CGPoint(x: tipX + w * 0.28, y: rect.minY + h * 0.22),
            control2: CGPoint(x: rect.maxX + w * 0.08, y: rect.minY + h * 0.62)
        )
        path.closeSubpath()
        return path
    }
}

/// Columns of fire driven by mic levels + continuous flicker (TimelineView).
struct FlameWaveVisualizer: View {
    let levels: [Double]
    var compact: Bool = false

    var body: some View {
        // macOS 13: use periodic schedule (`.animation` schedule is newer).
        TimelineView(.periodic(from: Date(timeIntervalSince1970: 0), by: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: compact ? 3.2 : 4.6) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    flameColumn(level: level, index: index, time: t)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    @ViewBuilder
    private func flameColumn(level: Double, index: Int, time: TimeInterval) -> some View {
        let w = compact ? 3.6 : 5.0
        let minH: CGFloat = compact ? 5.5 : 7.0
        let maxExtra = compact ? 20.0 : 26.0
        let i = Double(index)
        let flicker =
            sin(time * 10.5 + i * 0.95) * 2.8
                + sin(time * 16.2 + i * 1.4) * 1.4
                + sin(time * 23.0 + i * 0.3) * 0.7
        let h = minH + CGFloat(level) * maxExtra + CGFloat(flicker)
        let wiggle =
            CGFloat(
                sin(time * 6.8 + i * 0.65) * 0.55
                    + sin(time * 12.4 + i * 1.1) * 0.22
            )

        let outerW = w * 2.0
        let columnHeight = max(h * 1.08 + (compact ? 6 : 8), compact ? 30 : 38)

        ZStack(alignment: .bottom) {
            // Glow bed (reads as heat / gas)
            FlameShape(wiggle: wiggle)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.55),
                            Color(red: 0.9, green: 0.12, blue: 0.02).opacity(0.08),
                            Color.clear
                        ],
                        center: .init(x: 0.5, y: 0.82),
                        startRadius: 1,
                        endRadius: outerW * 1.2
                    )
                )
                .frame(width: outerW, height: h * 1.12)
                .blur(radius: compact ? 2.4 : 3.8)
                .offset(y: compact ? 2 : 3)
                .opacity(0.75 + Double(level) * 0.2)

            // Main flame body
            FlameShape(wiggle: wiggle)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.35, green: 0.02, blue: 0.02),
                            Color(red: 0.75, green: 0.08, blue: 0.02),
                            Color(red: 0.98, green: 0.28, blue: 0.05),
                            Color(red: 1.0, green: 0.58, blue: 0.12),
                            Color(red: 1.0, green: 0.92, blue: 0.55)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: w, height: h)
                .overlay {
                    // Hot core
                    FlameShape(wiggle: wiggle * 0.85)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.orange.opacity(0),
                                    Color(red: 1.0, green: 0.95, blue: 0.55).opacity(0.92)
                                ],
                                startPoint: UnitPoint(x: 0.5, y: 0.72),
                                endPoint: .top
                            )
                        )
                        .frame(width: w * 0.5, height: h * 0.72)
                        .blendMode(.screen)
                }

            // Ember coals at base
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.02, blue: 0.01),
                            Color(red: 0.42, green: 0.06, blue: 0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: w * 1.15, height: compact ? 3.2 : 3.8)
                .offset(y: 1)
                .opacity(0.88)
        }
        .frame(width: outerW, height: columnHeight, alignment: .bottom)
    }
}
