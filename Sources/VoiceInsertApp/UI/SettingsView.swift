import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 920

            ZStack {
                SettingsBackground()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            heroSection
                            contentSections(isCompact: isCompact)
                        }
                        .padding(28)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    footerBar
                        .padding(.horizontal, 28)
                        .padding(.vertical, 18)
                        .background(.ultraThinMaterial)
                        .overlay(alignment: .top) {
                            Divider()
                        }
                }
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.92), value: model.permissions)
        .animation(.spring(response: 0.22, dampingFraction: 0.92), value: model.isRecordingShortcut)
        .animation(.spring(response: 0.22, dampingFraction: 0.92), value: model.requiresInitialSetup)
        .onAppear {
            model.refreshPermissionsFromUI()
        }
    }

    private var heroSection: some View {
        SettingsSurface(padding: 26) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.09, green: 0.42, blue: 0.94),
                                        Color(red: 0.06, green: 0.69, blue: 0.78)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 62, height: 62)

                        Image(systemName: "waveform.badge.mic")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text(model.requiresInitialSetup ? "Set Up VoiceInsert" : "VoiceInsert Settings")
                                .font(.system(size: 30, weight: .bold, design: .rounded))

                            StatusPill(
                                title: model.permissions.essentialsGranted ? "Ready" : "Needs Setup",
                                tint: model.permissions.essentialsGranted ? .green : .orange
                            )
                        }

                        Text(
                            model.requiresInitialSetup
                            ? "Choose a shortcut, grant microphone and speech recognition, then click OK. Accessibility is optional and improves insertion in some apps."
                            : "VoiceInsert runs quietly in the menu bar. Hold your shortcut to dictate into the field that already has focus."
                        )
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 12) {
                    HeroMetric(
                        title: "Shortcut",
                        value: model.shortcutDisplayText,
                        detail: "Hold to talk"
                    )

                    HeroMetric(
                        title: "Permissions",
                        value: "\(requiredPermissionCount)/3",
                        detail: model.permissions.shortcutReady ? "Shortcut ready" : "Shortcut setup"
                    )

                    HeroMetric(
                        title: "Feedback",
                        value: "Top Indicator",
                        detail: "Appears while recording"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func contentSections(isCompact: Bool) -> some View {
        if isCompact {
            VStack(alignment: .leading, spacing: 20) {
                primaryColumn
                secondaryColumn
            }
        } else {
            HStack(alignment: .top, spacing: 20) {
                primaryColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                secondaryColumn
                    .frame(width: 296, alignment: .topLeading)
            }
        }
    }

    private var primaryColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            shortcutCard
            permissionsCard
        }
    }

    private var secondaryColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            behaviorCard
            feedbackCard
        }
    }

    private var shortcutCard: some View {
        SettingsSurface {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(
                    icon: "command.circle.fill",
                    iconTint: Color(red: 0.11, green: 0.46, blue: 0.92),
                    title: "Shortcut",
                    subtitle: "Choose the key combination you will hold to start dictation without moving focus away from the current text field."
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Current shortcut")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(model.shortcutDisplayText)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())

                    ShortcutRecorderView(
                        shortcut: model.keyboardShortcut,
                        isRecording: $model.isRecordingShortcut,
                        onCapture: model.updateKeyboardShortcut,
                        onCancel: model.cancelShortcutRecording
                    )
                }

                InlineNotice(
                    icon: "info.circle",
                    text: "Shortcut engine: \(model.hotkeyMonitorStatusTitle). VoiceInsert suppresses the chosen shortcut globally only when the engine is in Global mode."
                )

                if model.isRecordingShortcut {
                    InlineNotice(
                        icon: "keyboard.badge.ellipsis",
                        text: "Recording a new shortcut now. Press Escape to cancel."
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var permissionsCard: some View {
        SettingsSurface {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(
                    icon: "checkmark.shield.fill",
                    iconTint: Color(red: 0.13, green: 0.61, blue: 0.41),
                    title: "Permissions",
                    subtitle: "VoiceInsert needs microphone, speech recognition, and Input Monitoring for the global shortcut. Accessibility is optional and improves direct insertion in some apps."
                )

                VStack(spacing: 12) {
                    PermissionStatusRow(
                        icon: "mic.fill",
                        title: "Microphone",
                        detail: "Captures your voice in real time.",
                        state: model.permissions.microphone,
                        actionTitle: "Open",
                        action: { model.openSystemSettings(for: .microphone) }
                    )

                    PermissionStatusRow(
                        icon: "waveform",
                        title: "Speech Recognition",
                        detail: "Turns speech into text while you talk.",
                        state: model.permissions.speech,
                        actionTitle: "Open",
                        action: { model.openSystemSettings(for: .speech) }
                    )

                    PermissionStatusRow(
                        icon: "keyboard.badge.eye",
                        title: "Input Monitoring",
                        detail: "Lets VoiceInsert capture and suppress your shortcut in other apps.",
                        state: model.permissions.inputMonitoring,
                        actionTitle: "Open",
                        action: { model.openSystemSettings(for: .inputMonitoring) }
                    )

                    PermissionStatusRow(
                        icon: "cursorarrow.rays",
                        title: "Accessibility",
                        detail: "Optional: improves direct insertion in apps that do not accept paste cleanly.",
                        state: model.permissions.accessibility,
                        statusTitle: model.permissions.accessibility == .authorized ? "Enabled" : "Optional",
                        statusTint: model.permissions.accessibility == .authorized
                            ? .green
                            : Color(red: 0.26, green: 0.46, blue: 0.78),
                        actionTitle: "Open",
                        action: { model.openSystemSettings(for: .accessibility) }
                    )
                }

                HStack(spacing: 10) {
                    Button("Request Essentials") {
                        model.requestPermissionsFromUI()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Refresh Status") {
                        model.refreshPermissionsFromUI()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                InlineNotice(
                    icon: "hand.raised.square.on.square",
                    text: model.inputMonitoringHelpText
                )

                InlineNotice(
                    icon: "cursorarrow.motionlines",
                    text: model.accessibilityHelpText
                )
            }
        }
    }

    private var behaviorCard: some View {
        SettingsSurface {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(
                    icon: "slider.horizontal.3",
                    iconTint: Color(red: 0.49, green: 0.38, blue: 0.90),
                    title: "Behavior",
                    subtitle: "Keep the app calm in the background, with only the controls and feedback you want to see."
                )

                SettingToggleRow(
                    title: "Automatic punctuation",
                    detail: "Adds sentence punctuation when the system recognizer supports it.",
                    isOn: $model.autoPunctuation
                )

                SettingToggleRow(
                    title: "Show floating button",
                    detail: "Keeps the hold-to-talk mouse button visible on screen in addition to the global shortcut.",
                    isOn: Binding(
                        get: { model.isPanelVisible },
                        set: { model.setPanelVisibility($0) }
                    )
                )

                InlineNotice(
                    icon: "mic.badge.plus",
                    text: "While you hold the shortcut or floating button, VoiceInsert now shows a small live waveform at the top center of the screen."
                )
            }
        }
    }

    private var feedbackCard: some View {
        SettingsSurface {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(
                    icon: "waveform.path.ecg.rectangle.fill",
                    iconTint: Color(red: 0.91, green: 0.29, blue: 0.24),
                    title: "Live Feedback",
                    subtitle: "A compact recording indicator appears at the top center while you are holding to dictate, then disappears immediately on release."
                )

                VoiceWavePreview()

                VStack(alignment: .leading, spacing: 8) {
                    FeedbackBullet(text: "Shows that the microphone is actively listening.")
                    FeedbackBullet(text: "Visualizes your voice energy in real time.")
                    FeedbackBullet(text: "Stays out of the way and vanishes as soon as you stop talking.")
                }
            }
        }
    }

    private var footerBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.requiresInitialSetup ? "First launch setup" : "Background utility")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(
                    model.permissions.essentialsGranted
                    ? "Everything is ready. You can dictate right away."
                    : "You can finish now and come back later from the menu bar if needed."
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(model.requiresInitialSetup ? "OK" : "Done") {
                model.finishSettings()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var requiredPermissionCount: Int {
        [
            model.permissions.microphone,
            model.permissions.speech,
            model.permissions.inputMonitoring
        ]
        .filter { $0 == .authorized }
        .count
    }
}

private struct SettingsBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.96, blue: 0.99),
                Color(red: 0.92, green: 0.95, blue: 0.99)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.white.opacity(0.38))
                .frame(width: 320, height: 320)
                .blur(radius: 28)
                .offset(x: 90, y: -120)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(Color(red: 0.09, green: 0.42, blue: 0.94).opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 34)
                .offset(x: -110, y: 120)
        }
    }
}

private struct SettingsSurface<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.90))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 24, y: 10)
            )
    }
}

private struct SectionHeader: View {
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 38, height: 38)
                .background(iconTint.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct HeroMetric: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))

            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.035))
        )
    }
}

private struct StatusPill: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

private struct InlineNotice: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.035))
        )
    }
}

private struct PermissionStatusRow: View {
    let icon: String
    let title: String
    let detail: String
    let state: PermissionState
    let statusTitle: String?
    let statusTint: Color?
    let actionTitle: String
    let action: () -> Void

    init(
        icon: String,
        title: String,
        detail: String,
        state: PermissionState,
        statusTitle: String? = nil,
        statusTint: Color? = nil,
        actionTitle: String,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.state = state
        self.statusTitle = statusTitle
        self.statusTint = statusTint
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            StatusPill(title: statusTitle ?? state.title, tint: statusTint ?? color)

            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.75))
        )
    }

    private var color: Color {
        switch state {
        case .authorized:
            return .green
        case .denied:
            return .red
        case .restricted:
            return .orange
        case .notDetermined:
            return .gray
        }
    }
}

private struct SettingToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
    }
}

private struct VoiceWavePreview: View {
    private let previewLevels: [Double] = [0.16, 0.24, 0.52, 0.78, 0.44, 0.30, 0.72, 0.90, 0.58, 0.28, 0.48, 0.22]

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 42, height: 42)

                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.red)
            }

            VoiceWaveVisualizer(levels: previewLevels)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.74),
                            Color(red: 0.98, green: 0.95, blue: 0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }
}

private struct FeedbackBullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(red: 0.91, green: 0.29, blue: 0.24))
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
