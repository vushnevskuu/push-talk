import SwiftUI

// MARK: - Premium black-glass fire chamber: прозрачная центральная камера, дым только у кромок, глянцевый чёрный корпус.

private enum FireChamberPalette {
    static let piano = Color(red: 0.008, green: 0.008, blue: 0.012)
    static let rimCool = Color(red: 0.12, green: 0.13, blue: 0.16)
    static let edgeSmoke = Color(red: 0.06, green: 0.065, blue: 0.08)
    static let edgeSmokeDeep = Color(red: 0.02, green: 0.022, blue: 0.03)
    static let spec = Color(red: 0.92, green: 0.93, blue: 0.97)
    static let specCool = Color(red: 0.65, green: 0.72, blue: 0.88)
    static let amberLow = Color(red: 1.0, green: 0.48, blue: 0.12)
    static let amberSoft = Color(red: 1.0, green: 0.68, blue: 0.35)
    static let prism = Color(red: 0.45, green: 0.52, blue: 0.72)
}

/// Панорамная камера: середину не заливаем — виден фон и пламя; оптика и дым только по ребру и оболочке.
struct FlameHUDChromeBackground: View {
    var cornerRadius: CGFloat
    var emberPulse: CGFloat
    var reducedMotion: Bool

    private var pulse: CGFloat {
        let t = min(1, max(0, emberPulse))
        let amp: CGFloat = reducedMotion ? 0.10 : 0.28
        return t * amp + 0.26
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        GeometryReader { geo in
            let diag = max(44, hypot(geo.size.width, geo.size.height))

            ZStack {
                // Копчёный тон только от периметра к центру (ядро остаётся прозрачным).
                shape.fill(
                    RadialGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.34),
                            .init(color: FireChamberPalette.edgeSmoke.opacity(0.42), location: 0.72),
                            .init(color: FireChamberPalette.edgeSmokeDeep.opacity(0.62), location: 1)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: diag * 0.5
                    )
                )

                // Боковые 14% — усиление «толщины» стекла; центр по горизонтали не трогаем.
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: FireChamberPalette.edgeSmokeDeep.opacity(0.38), location: 0),
                            .init(color: .clear, location: 0.14),
                            .init(color: .clear, location: 0.86),
                            .init(color: FireChamberPalette.edgeSmokeDeep.opacity(0.38), location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                // Верх/низ: узкие полосы блика и лёгкой тени; 0.08–0.92 по вертикали — полностью прозрачно.
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: FireChamberPalette.spec.opacity(0.14), location: 0),
                            .init(color: .clear, location: 0.07),
                            .init(color: .clear, location: 0.93),
                            .init(color: FireChamberPalette.piano.opacity(0.18), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Янтарь только у нижней внутренней кромки (огонь за стеклом), без полосы через всю высоту.
                shape.fill(
                    RadialGradient(
                        colors: [
                            FireChamberPalette.amberSoft.opacity(0.20 * pulse),
                            FireChamberPalette.amberLow.opacity(0.12 * pulse),
                            .clear
                        ],
                        center: UnitPoint(x: 0.5, y: 1.02),
                        startRadius: 0,
                        endRadius: diag * 0.34
                    )
                )

                // Тонкая диагональ — внутреннее отражение, не молочный туман.
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: FireChamberPalette.prism.opacity(0.045), location: 0),
                            .init(color: .clear, location: 0.35)
                        ],
                        startPoint: .topTrailing,
                        endPoint: UnitPoint(x: 0.35, y: 0.55)
                    )
                )

                // Внешняя оболочка: почти чёрный глянец + холодный микроблик.
                shape.strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: FireChamberPalette.piano.opacity(1.0), location: 0),
                            .init(color: Color(red: 0.03, green: 0.03, blue: 0.038).opacity(0.98), location: 0.35),
                            .init(color: Color(red: 0.06, green: 0.06, blue: 0.075).opacity(0.92), location: 0.62),
                            .init(color: FireChamberPalette.amberLow.opacity(0.22 * (0.55 + pulse * 0.45)), location: 0.88),
                            .init(color: FireChamberPalette.rimCool.opacity(0.55), location: 1)
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    lineWidth: 2.35
                )

                // Внутренний фаска-блик: сверху свет, снизу глубина; середина обрыва в прозрачный.
                shape
                    .inset(by: 2.85)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: FireChamberPalette.spec.opacity(0.38), location: 0),
                                .init(color: FireChamberPalette.specCool.opacity(0.12), location: 0.18),
                                .init(color: .clear, location: 0.42),
                                .init(color: .clear, location: 0.58),
                                .init(color: FireChamberPalette.amberSoft.opacity(0.14 * pulse), location: 0.88),
                                .init(color: FireChamberPalette.piano.opacity(0.35), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.85
                    )
            }
        }
    }
}

struct FlameHUDDropShadow: View {
    var cornerRadius: CGFloat
    var emberPulse: CGFloat
    var reducedMotion: Bool

    private var glow: CGFloat {
        let t = min(1, max(0, emberPulse))
        let amp: CGFloat = reducedMotion ? 0.06 : 0.14
        return t * amp + 0.22
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            shape
                .fill(
                    RadialGradient(
                        colors: [
                            Color.black.opacity(0.58),
                            Color.black.opacity(0.24),
                            .clear
                        ],
                        center: UnitPoint(x: 0.5, y: 0.88),
                        startRadius: 4,
                        endRadius: 68
                    )
                )
                .blur(radius: 14)
                .offset(y: 4)

            shape
                .fill(
                    RadialGradient(
                        colors: [
                            FireChamberPalette.amberLow.opacity(0.18 * glow),
                            FireChamberPalette.amberSoft.opacity(0.08 * glow),
                            .clear
                        ],
                        center: UnitPoint(x: 0.5, y: 0.98),
                        startRadius: 6,
                        endRadius: 78
                    )
                )
                .blur(radius: 18)
                .offset(y: 3)
        }
        .opacity(0.9)
    }
}

private struct FlameMetalSoftEdgeMask: View {
    var cornerRadius: CGFloat
    var blur: CGFloat
    var spread: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white)
            .blur(radius: blur)
            .padding(-spread)
    }
}

extension View {
    func flameMetalSoftEdges(cornerRadius: CGFloat = 14, blur: CGFloat = 5.5, spread: CGFloat = 5.5) -> some View {
        mask {
            FlameMetalSoftEdgeMask(cornerRadius: cornerRadius, blur: blur, spread: spread)
        }
    }
}
