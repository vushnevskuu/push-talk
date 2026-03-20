import SwiftUI

struct FloatingPanelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 20, y: 8)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(nsColor: model.statusDotColor).opacity(0.18))
                            .frame(width: 42, height: 42)

                        Image(systemName: model.phase == .recording ? "waveform.circle.fill" : "mic.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(model.phase == .recording ? .red : .primary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.titleText)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(model.statusMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    Button {
                        model.openSettings()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Text(model.subtitleText)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.88))
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Capsule()
                            .fill(model.phase == .recording ? Color.red : Color.blue.opacity(0.2))
                            .frame(width: 10, height: 10)

                        Text(model.phase == .recording ? "Recording in progress. Keep holding." : "Hold the button below or use your shortcut.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Text("Shortcut")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(model.shortcutDisplayText)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.14), in: Capsule())

                        Spacer(minLength: 0)
                    }

                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(model.phase == .recording ? Color.red.opacity(0.16) : Color.blue.opacity(0.12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(model.phase == .recording ? Color.red.opacity(0.35) : Color.blue.opacity(0.18), lineWidth: 1)
                            }

                        VStack(spacing: 6) {
                            Text(model.phase == .recording ? "Release to Insert" : "Hold to Talk")
                                .font(.system(size: 14, weight: .semibold))

                            Text("Mouse hold works here without stealing focus from the target field.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        HoldEventOverlay(
                            onPress: model.startHold,
                            onRelease: model.endHold
                        )
                    }
                    .frame(height: 62)
                }
            }
            .padding(18)
        }
        .frame(width: 360, height: 220)
        .animation(.spring(response: 0.22, dampingFraction: 0.90), value: model.phase)
        .animation(.spring(response: 0.22, dampingFraction: 0.90), value: model.liveTranscript)
    }
}
