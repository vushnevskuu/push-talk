import SwiftUI

enum GlassDropletGeometry {
    static func cgPath(in rect: CGRect) -> CGPath {
        let size = min(rect.width, rect.height)
        let centered = CGRect(
            x: rect.midX - (size / 2),
            y: rect.midY - (size / 2),
            width: size,
            height: size
        ).insetBy(dx: 0.5, dy: 0.5)

        return CGPath(ellipseIn: centered, transform: nil)
    }
}

struct GlassDropletShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(GlassDropletGeometry.cgPath(in: rect))
    }
}

struct GlassDropletSurface: View {
    var body: some View {
        let shape = GlassDropletShape()

        return ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.88, green: 0.94, blue: 1.0).opacity(0.18),
                            Color.white.opacity(0.10),
                            Color(red: 0.84, green: 0.90, blue: 0.98).opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            shape
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            Color(red: 0.86, green: 0.92, blue: 1.0).opacity(0.10),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: 34
                    )
                )
                .scaleEffect(x: 0.78, y: 0.58, anchor: .topLeading)
                .offset(x: -1, y: -1)
                .blur(radius: 1.0)
                .mask(shape)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.30),
                            Color.white.opacity(0.10),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 42, height: 18)
                .offset(y: -15)
                .blur(radius: 4.2)
                .mask(shape)

            shape
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.70, green: 0.80, blue: 0.94).opacity(0.10),
                            Color.clear
                        ],
                        center: .bottomTrailing,
                        startRadius: 4,
                        endRadius: 26
                    )
                )
                .scaleEffect(0.82)
                .blur(radius: 3.0)
                .mask(shape)

            shape
                .stroke(Color.white.opacity(0.34), lineWidth: 0.9)

            shape
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color(red: 0.72, green: 0.79, blue: 0.90).opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2.4
                )
                .blur(radius: 1.2)
                .mask(shape)

            shape
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.black.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.2
                )
                .mask(shape)
        }
        .compositingGroup()
        .clipShape(shape)
        .shadow(color: .black.opacity(0.14), radius: 10, y: 6)
    }
}
