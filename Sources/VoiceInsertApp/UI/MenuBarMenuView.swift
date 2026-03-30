import SwiftUI

struct MenuBarMenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VoiceInsert")
                            .font(.system(size: 16, weight: .bold, design: .rounded))

                        Text(
                            model.permissions.shortcutReady
                            ? (model.obsidianVaultLinked
                                ? "Insert mode and Obsidian capture are ready."
                                : "Background dictation is ready.")
                            : model.permissions.essentialsGranted
                                ? "Enable Input Monitoring so your shortcut works everywhere."
                                : "Finish setup to dictate into other apps."
                        )
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    MiniStatusBadge(
                        title: model.permissions.shortcutReady ? "Ready" : "Setup",
                        color: model.permissions.shortcutReady ? .green : .orange
                    )
                }

                HStack(spacing: 8) {
                    MenuInfoChip(label: "Insert", value: model.shortcutDisplayText)
                    MenuInfoChip(label: "Notes", value: model.obsidianShortcutDisplayText)
                    MenuInfoChip(label: "Permissions", value: permissionCountText)
                }

                Text(model.statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)

                if model.phase != .idle {
                    Button("Cancel dictation") {
                        model.cancelActiveSession()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Button(model.requiresInitialSetup ? "Open Setup" : "Open Settings") {
                    model.openSettings()
                }
                .buttonStyle(.borderedProminent)

                Button("Record New Shortcut") {
                    model.startShortcutRecording()
                }
                .buttonStyle(.bordered)

                Button("Record Obsidian Shortcut") {
                    model.startObsidianShortcutRecording()
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 8) {
                PermissionRow(title: "Microphone", state: model.permissions.microphone)
                PermissionRow(title: "Speech Recognition", state: model.permissions.speech)
                PermissionRow(title: "Input Monitoring", state: model.permissions.inputMonitoring)
                PermissionRow(
                    title: "Accessibility",
                    state: model.permissions.accessibility,
                    statusTitle: model.permissions.accessibility == .authorized ? "Enabled" : "Optional",
                    statusColor: model.permissions.accessibility == .authorized
                        ? .green
                        : Color(red: 0.26, green: 0.46, blue: 0.78)
                    )
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Obsidian Capture")
                            .font(.system(size: 13, weight: .semibold))

                        Text(model.obsidianVaultLinked ? model.obsidianVaultDisplayText : "No vault selected yet")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    MiniStatusBadge(
                        title: model.obsidianCaptureReady ? "Ready" : (model.obsidianVaultLinked ? "Link OK" : "Needs Vault"),
                        color: model.obsidianCaptureReady ? .green : .orange
                    )
                }

                Text(model.obsidianCaptureHelpText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("Choose Vault") {
                        model.chooseObsidianVault()
                    }
                    .buttonStyle(.borderedProminent)

                    if model.obsidianVaultLinked {
                        Button("Reveal Vault") {
                            model.revealObsidianVault()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if !model.permissions.shortcutReady {
                Text(model.inputMonitoringHelpText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.permissions.accessibility != .authorized {
                Text(model.accessibilityHelpText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Language")
                        .font(.system(size: 13, weight: .medium))

                    Spacer(minLength: 8)

                    Picker("Language", selection: Binding(
                        get: { model.dictationLanguage },
                        set: { model.updateDictationLanguage($0) }
                    )) {
                        ForEach(DictationLanguage.allCases, id: \.self) { lang in
                            Text(lang.title).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(maxWidth: 220)
                }
                .disabled(model.phase != .idle)

                Toggle("Automatic punctuation", isOn: $model.autoPunctuation)
                Toggle(
                    "Show floating button",
                    isOn: Binding(
                        get: { model.isPanelVisible },
                        set: { model.setPanelVisibility($0) }
                    )
                )
            }

            HStack(spacing: 10) {
                Button("Request Essentials") {
                    model.requestPermissionsFromUI()
                }
                .buttonStyle(.bordered)

                Button("Refresh") {
                    model.refreshPermissionsFromUI()
                }
                .buttonStyle(.bordered)
            }

            Divider()

            Button("Quit") {
                model.quit()
            }
        }
        .padding(14)
        .frame(width: 340)
        .animation(.spring(response: 0.22, dampingFraction: 0.92), value: model.permissions)
        .animation(.spring(response: 0.22, dampingFraction: 0.92), value: model.isPanelVisible)
        .animation(.spring(response: 0.22, dampingFraction: 0.92), value: model.phase)
        .animation(.spring(response: 0.22, dampingFraction: 0.92), value: model.dictationLanguage)
        .onAppear {
            model.refreshPermissionsFromUI()
        }
    }

    private var permissionCountText: String {
        let requiredCount = [
            model.permissions.microphone,
            model.permissions.speech,
            model.permissions.inputMonitoring
        ]
        .filter { $0 == .authorized }
        .count

        if requiredCount == 3 {
            return model.permissions.accessibility == .authorized ? "3/3 + Direct" : "3/3 Ready"
        }

        return "\(requiredCount)/3 Required"
    }
}

private struct PermissionRow: View {
    let title: String
    let state: PermissionState
    let statusTitle: String?
    let statusColor: Color?

    init(
        title: String,
        state: PermissionState,
        statusTitle: String? = nil,
        statusColor: Color? = nil
    ) {
        self.title = title
        self.state = state
        self.statusTitle = statusTitle
        self.statusColor = statusColor
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor ?? color)
                .frame(width: 9, height: 9)

            Text(title)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            Text(statusTitle ?? state.title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
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

private struct MenuInfoChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

private struct MiniStatusBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14), in: Capsule())
    }
}
