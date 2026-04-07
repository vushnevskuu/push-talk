import SwiftUI

// MARK: - Flame HUD (Canvas — одно пламя на весь объём; голос задаёт высоту и качку)

/// Shared geometry; `bend` сдвигает вершину по горизонтали (масштаб –1…1 внутри path).
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
}

/// Одно сплошное пламя на всю область `Canvas`: высота и «качка» от микрофона, без отдельных полос.
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
        guard size.width > 2, size.height > 2 else { return }

        let voice = voiceMetrics(from: levels)
        let baseY = size.height - (compact ? 1.5 : 2.5)

        // Тихий минимум — заметное тело; громко — почти вся высота области.
        let minFrac: CGFloat = compact ? 0.38 : 0.34
        let minH = max(6, size.height * minFrac)
        let maxH = size.height * 0.96
        let breath = 0.5 + 0.5 * sin(time * 2.0)
        let drive = CGFloat(voice.drive)
        let baseH = minH + (maxH - minH) * drive * CGFloat(0.78 + 0.22 * breath)

        let flickerAmp = (compact ? 1.1 : 1.5) * CGFloat(0.55 + 0.45 * drive)
        let flicker = flickerUnified(time: time, compact: compact) * flickerAmp
        let flameH = max(minH * 0.9, baseH + flicker)

        let marginX = size.width * 0.05
        let flameW = max(8, size.width - 2 * marginX)
        let rect = CGRect(
            x: (size.width - flameW) / 2,
            y: baseY - flameH,
            width: flameW,
            height: flameH
        )

        // Наклон: срез уровней слева/справа + плавное качание.
        let sway = CGFloat(sin(time * 4.8) * 0.35 + sin(time * 8.2) * 0.18)
        let bend = CGFloat(voice.asymmetry) * 0.85 + sway

        // 1) Bloom
        let bloomRect = rect.insetBy(dx: -flameW * 0.06, dy: -flameH * 0.05)
        let bloomPath = FlameGeometry.mainPath(in: bloomRect, bend: bend * 0.88)
        context.fill(
            bloomPath,
            with: .radialGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.42, blue: 0.05).opacity(0.42 * Double(0.5 + voice.drive * 0.5)),
                    Color(red: 0.85, green: 0.1, blue: 0.02).opacity(0.08),
                    Color.clear
                ]),
                center: CGPoint(x: bloomRect.midX, y: bloomRect.maxY - flameH * 0.12),
                startRadius: 1,
                endRadius: max(bloomRect.width, bloomRect.height) * 0.92
            )
        )

        context.blendMode = .plusLighter

        // 2) Основное тело
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
                endPoint: CGPoint(x: rect.midX + bend * flameW * 0.08, y: rect.minY)
            )
        )

        // 3) Яркое ядро
        let coreInsetX = flameW * 0.22
        let coreRect = rect.insetBy(dx: coreInsetX, dy: flameH * 0.1)
        let corePath = FlameGeometry.mainPath(in: coreRect, bend: bend * 0.78)
        context.fill(
            corePath,
            with: .linearGradient(
                Gradient(colors: [
                    Color.orange.opacity(0),
                    Color(red: 1.0, green: 0.88, blue: 0.45).opacity(0.55),
                    Color(red: 1.0, green: 0.98, blue: 0.85).opacity(0.92)
                ]),
                startPoint: CGPoint(x: coreRect.midX, y: coreRect.minY + coreRect.height * 0.52),
                endPoint: CGPoint(x: coreRect.midX + bend * 3, y: coreRect.minY)
            )
        )

        context.blendMode = .normal

        // 4) Подложка углей на всю ширину
        let emberH = compact ? 3.0 : 3.8
        let emberRect = CGRect(x: marginX * 0.85, y: baseY - emberH * 0.4, width: size.width - marginX * 1.7, height: emberH)
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

    /// Сводка по полосам визуализатора: общая «энергия» и перекос влево/вправо (без отрисовки полос).
    private func voiceMetrics(from levels: [Double]) -> (drive: Double, asymmetry: Double) {
        let vals = levels.map { clamped($0) }
        guard !vals.isEmpty else { return (0.12, 0) }

        let n = vals.count
        let sum = vals.reduce(0, +)
        let mean = sum / Double(n)
        let peak = vals.max() ?? mean

        let mid = n / 2
        let left = mid > 0 ? vals.prefix(mid).reduce(0, +) / Double(mid) : mean
        let right = n - mid > 0 ? vals.suffix(n - mid).reduce(0, +) / Double(n - mid) : mean
        let asym = (right - left) * 1.15

        let tail = min(6, n)
        let recent = vals.suffix(tail).reduce(0, +) / Double(tail)

        let drive = min(1, max(0, 0.38 * mean + 0.32 * peak + 0.30 * recent))
        let asymmetry = min(1, max(-1, asym))
        return (drive, asymmetry)
    }

    private func flickerUnified(time: TimeInterval, compact: Bool) -> CGFloat {
        let a = sin(time * 7.5)
        let b = sin(time * 12.4) * 0.42
        let c = sin(time * 19.0) * 0.2
        return CGFloat(a + b + c) * (compact ? 0.9 : 1.0)
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
