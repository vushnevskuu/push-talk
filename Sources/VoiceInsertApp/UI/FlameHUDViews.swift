import SwiftUI

// MARK: - Flame HUD (Canvas — layered tongues, smoother motion than stacked Shapes)

/// Shared geometry for main + side tongue; `bend` shifts the tip horizontally (–1…1 scale in path).
private enum FlameGeometry {
    static func mainPath(in rect: CGRect, bend: CGFloat) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let tipX = rect.midX + bend * w * 0.42
        let left = CGPoint(x: rect.minX + w * 0.10, y: rect.maxY)
        let right = CGPoint(x: rect.maxX - w * 0.10, y: rect.maxY)
        let tip = CGPoint(x: tipX, y: rect.minY + h * 0.03)

        path.move(to: left)
        path.addCurve(
            to: tip,
            control1: CGPoint(x: rect.minX - w * 0.12, y: rect.minY + h * 0.58),
            control2: CGPoint(x: tipX - w * 0.32, y: rect.minY + h * 0.20)
        )
        path.addCurve(
            to: right,
            control1: CGPoint(x: tipX + w * 0.32, y: rect.minY + h * 0.20),
            control2: CGPoint(x: rect.maxX + w * 0.12, y: rect.minY + h * 0.58)
        )
        path.closeSubpath()
        return path
    }

    /// Smaller lobe hugging one side (reads as turbulent fire).
    static func sideLobePath(in rect: CGRect, bend: CGFloat, flip: CGFloat) -> Path {
        let w = rect.width * 0.52
        let h = rect.height * 0.58
        let ox = rect.midX + flip * w * 0.55
        let oy = rect.maxY - h * 0.08
        let sub = CGRect(x: ox - w / 2, y: oy - h, width: w, height: h)
        return mainPath(in: sub, bend: bend * 0.8 + flip * 0.35)
    }
}

/// Columns of fire: mic levels set height; time drives organic sway + gentle flicker.
struct FlameWaveVisualizer: View {
    let levels: [Double]
    var compact: Bool = false

    private static let timelineStart = Date(timeIntervalSince1970: 0)

    var body: some View {
        TimelineView(.periodic(from: Self.timelineStart, by: 1.0 / 55.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                draw(in: &context, size: size, time: t)
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let count = max(levels.count, 1)
        let slot = size.width / CGFloat(count)
        let baseY = size.height - (compact ? 1.5 : 2.5)
        let minH: CGFloat = compact ? 6 : 8
        let maxExtra: CGFloat = compact ? 19 : 25

        for (index, rawLevel) in levels.enumerated() {
            let i = Double(index)
            let level = CGFloat(clamped(rawLevel))
            // Breathing: slow swell tied to level (less “nervous” than raw sine stack).
            let breath = 0.5 + 0.5 * sin(time * 2.1 + i * 0.4)
            let levelH = minH + level * maxExtra * CGFloat(0.82 + 0.18 * breath)

            let flicker = flickerOffset(index: i, time: time, compact: compact)
            let flameH = max(minH * 0.85, levelH + flicker)

            let bend = CGFloat(sin(time * 5.2 + i * 0.73) * 0.55 + sin(time * 9.1 + i * 1.05) * 0.22)
            let lobeFlip: CGFloat = index.isMultiple(of: 2) ? 1 : -1

            let colW = compact ? 6.2 : 8.4
            let cx = slot * (CGFloat(index) + 0.5)
            let rect = CGRect(
                x: cx - colW / 2,
                y: baseY - flameH,
                width: colW,
                height: flameH
            )

            // 1) Soft bloom (wide, transparent)
            let bloomRect = rect.insetBy(dx: -colW * 0.35, dy: -flameH * 0.06)
            let bloomPath = FlameGeometry.mainPath(in: bloomRect, bend: bend * 0.85)
            context.fill(
                bloomPath,
                with: .radialGradient(
                    Gradient(colors: [
                        Color(red: 1.0, green: 0.42, blue: 0.05).opacity(0.38 * Double(0.55 + level * 0.45)),
                        Color(red: 0.85, green: 0.1, blue: 0.02).opacity(0.06),
                        Color.clear
                    ]),
                    center: CGPoint(x: bloomRect.midX, y: bloomRect.maxY - flameH * 0.15),
                    startRadius: 1,
                    endRadius: max(bloomRect.width, bloomRect.height) * 0.95
                )
            )

            // 2) Side tongue (darker, behind main)
            let side = FlameGeometry.sideLobePath(in: rect, bend: bend, flip: lobeFlip)
            context.fill(
                side,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.5, green: 0.02, blue: 0.02),
                        Color(red: 0.92, green: 0.22, blue: 0.04).opacity(0.88),
                        Color(red: 1.0, green: 0.55, blue: 0.1).opacity(0.35)
                    ]),
                    startPoint: CGPoint(x: rect.midX, y: rect.maxY),
                    endPoint: CGPoint(x: rect.midX, y: rect.minY)
                )
            )
            context.blendMode = .plusLighter

            // 3) Main body
            let main = FlameGeometry.mainPath(in: rect, bend: bend)
            context.fill(
                main,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.22, green: 0.01, blue: 0.02),
                        Color(red: 0.72, green: 0.06, blue: 0.02),
                        Color(red: 0.98, green: 0.32, blue: 0.06),
                        Color(red: 1.0, green: 0.62, blue: 0.14),
                        Color(red: 1.0, green: 0.93, blue: 0.62)
                    ]),
                    startPoint: CGPoint(x: rect.midX, y: rect.maxY),
                    endPoint: CGPoint(x: rect.midX + bend * colW * 0.15, y: rect.minY)
                )
            )

            // 4) Hot core (narrow, screen-like punch)
            let coreRect = rect.insetBy(dx: colW * 0.28, dy: flameH * 0.12)
            let corePath = FlameGeometry.mainPath(in: coreRect, bend: bend * 0.75)
            context.fill(
                corePath,
                with: .linearGradient(
                    Gradient(colors: [
                        Color.orange.opacity(0),
                        Color(red: 1.0, green: 0.88, blue: 0.45).opacity(0.55),
                        Color(red: 1.0, green: 0.98, blue: 0.85).opacity(0.92)
                    ]),
                    startPoint: CGPoint(x: coreRect.midX, y: coreRect.minY + coreRect.height * 0.55),
                    endPoint: CGPoint(x: coreRect.midX + bend * 2, y: coreRect.minY)
                )
            )

            context.blendMode = .normal

            // 5) Ember base
            let emberW = colW * 1.2
            let emberH = compact ? 3.0 : 3.6
            let emberRect = CGRect(x: cx - emberW / 2, y: baseY - emberH * 0.35, width: emberW, height: emberH)
            let cap = Path(roundedRect: emberRect, cornerRadius: emberH / 2, style: .continuous)
            context.fill(
                cap,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.12, green: 0.01, blue: 0.01),
                        Color(red: 0.38, green: 0.05, blue: 0.02)
                    ]),
                    startPoint: CGPoint(x: emberRect.midX, y: emberRect.minY),
                    endPoint: CGPoint(x: emberRect.midX, y: emberRect.maxY)
                )
            )
        }
    }

    private func flickerOffset(index: Double, time: TimeInterval, compact: Bool) -> CGFloat {
        let amp: CGFloat = compact ? 1.35 : 1.85
        // Fewer high-frequency beats → calmer, still “alive”.
        let a = sin(time * 8.0 + index * 1.1)
        let b = sin(time * 13.5 + index * 1.7) * 0.45
        let c = sin(time * 21.0 + index * 0.35) * 0.22
        return CGFloat(a + b + c) * amp
    }

    private func clamped(_ x: Double) -> Double {
        min(1, max(0, x))
    }
}

// MARK: - Legacy shape (kept for SwiftUI previews / tooling that might reference it)

/// Teardrop flame; use `FlameWaveVisualizer` for the HUD.
struct FlameShape: Shape {
    var wiggle: CGFloat

    var animatableData: CGFloat {
        get { wiggle }
        set { wiggle = newValue }
    }

    func path(in rect: CGRect) -> Path {
        FlameGeometry.mainPath(in: rect, bend: wiggle)
    }
}
