import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    private static let dictationLocale = Locale(identifier: "ru-RU")

    @Published var autoPunctuation = true
    @Published private(set) var keyboardShortcut = KeyboardShortcutStore.load()
    @Published private(set) var liveTranscript = ""
    @Published private(set) var statusMessage = AppModel.initialStatusMessage()
    @Published private(set) var phase: RecordingPhase = .idle
    @Published private(set) var permissions = PermissionSnapshot.current()
    @Published private(set) var hotkeyMonitorState = AppModel.loadHotkeyMonitorState()
    @Published private(set) var isPanelVisible = AppModel.loadPanelVisibility()
    @Published private(set) var requiresInitialSetup = AppModel.loadRequiresInitialSetup()
    @Published var isRecordingShortcut = false {
        didSet {
            hotkeyMonitor.setSuspended(isRecordingShortcut)
        }
    }

    let permissionManager = PermissionManager()
    let recordingFeedback = RecordingFeedbackModel()
    private let speechService = SpeechRecognitionService()
    private let insertionService = TextInsertionService()
    private let floatingPanelController = FloatingPanelController()
    private let recordingHUDController = RecordingHUDController()
    private let hotkeyMonitor = HotkeyMonitor()
    private var permissionRefreshTask: Task<Void, Never>?
    private var autotestTriggerTask: Task<Void, Never>?
    private var activeInsertionTarget: TextInsertionTarget?
    private var activeAutotestTriggerToken: String?
    private var lastObservedAutotestTriggerToken: String?
    private lazy var settingsWindowController = SettingsWindowController(model: self)

    init() {
        AutotestDefaults.clearStaleStateOnLaunch()
        lastObservedAutotestTriggerToken = AutotestDefaults.pendingTriggerToken()

        floatingPanelController.attach(to: self)
        recordingHUDController.attach(to: recordingFeedback)
        hotkeyMonitor.updateShortcut(keyboardShortcut)
        hotkeyMonitor.setHandlers(onPress: { [weak self] in
            self?.startHold()
        }, onRelease: { [weak self] in
            self?.endHold()
        })
        hotkeyMonitor.setStateHandler { [weak self] state in
            self?.hotkeyMonitorState = state
            UserDefaults.standard.set(state.rawValue, forKey: DefaultsKey.hotkeyMonitorState)
        }
        hotkeyMonitor.start()

        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
            self.applyPanelVisibility()

            if self.requiresInitialSetup {
                self.openSettings()
            }
        }

        Task {
            await refreshPermissions()
            await requestEssentialPermissionsIfNeeded()
            prewarmSpeechPipeline()
        }

        autotestTriggerTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                await self.processPendingAutotestTriggerIfNeeded()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    var titleText: String {
        switch phase {
        case .idle:
            return permissions.essentialsGranted ? "Hold to Dictate" : "Permissions Needed"
        case .recording:
            return "Listening..."
        case .transcribing:
            return "Transcribing..."
        }
    }

    var subtitleText: String {
        if !liveTranscript.isEmpty {
            return liveTranscript
        }

        switch phase {
        case .idle:
            if permissions.essentialsGranted {
                if permissions.inputMonitoring != .authorized {
                    return "Enable Input Monitoring so your shortcut works in other apps and the chosen key stops leaking into them."
                }

                if permissions.accessibility == .authorized {
                    return "Text will be inserted into the field that currently has focus."
                }

                return "VoiceInsert will paste into the active field. Accessibility can improve direct insertion in some apps."
            }

            return permissions.missingText
        case .recording:
            return "Keep holding for long messages. Release when you finish speaking."
        case .transcribing:
            return "Finishing recognition and inserting text."
        }
    }

    var shortcutDisplayText: String {
        keyboardShortcut.displayString
    }

    var statusDotColor: NSColor {
        switch phase {
        case .idle:
            return permissions.essentialsGranted ? .systemGreen : .systemOrange
        case .recording:
            return .systemRed
        case .transcribing:
            return .systemBlue
        }
    }

    var accessibilityHelpText: String {
        if permissions.accessibility == .authorized {
            return "Accessibility is active. VoiceInsert can use direct insertion in apps that support it."
        }

        return "Accessibility is optional. VoiceInsert is already ready to paste text into most focused fields without it. Turn it on only if a specific app resists pasted text and you want stronger direct insertion."
    }

    var inputMonitoringHelpText: String {
        if permissions.inputMonitoring == .authorized {
            switch hotkeyMonitorState {
            case .globalTap:
                return "Input Monitoring is active. The global shortcut is armed and VoiceInsert can suppress the chosen key while you hold it."
            case .localFallback, .inactive:
                return "Input Monitoring looks enabled, but the global shortcut is not armed yet. Use Refresh, or relaunch once if macOS granted access while VoiceInsert was already running."
            }
        }

        return "Input Monitoring is required for the global shortcut. Without it, the floating button can still work, but pressing the chosen key in other apps may do nothing or still reach that app."
    }

    var hotkeyMonitorStatusTitle: String {
        switch hotkeyMonitorState {
        case .globalTap:
            return "Global"
        case .localFallback:
            return "Local Only"
        case .inactive:
            return "Starting"
        }
    }

    func startHold() {
        guard phase == .idle else { return }

        refreshPermissionsImmediately()

        guard permissions.microphone == .authorized else {
            statusMessage = "Microphone access is required."
            Task { await requestPermissions() }
            return
        }

        guard permissions.speech == .authorized else {
            statusMessage = "Speech recognition access is required."
            Task { await requestPermissions() }
            return
        }

        do {
            liveTranscript = ""
            resetAudioVisualization()
            activeInsertionTarget = insertionService.captureTarget()
            phase = .recording
            statusMessage = "Listening..."
            recordingHUDController.show()

            try speechService.startSession(
                locale: Self.dictationLocale,
                addsPunctuation: autoPunctuation,
                partialHandler: { _ in },
                levelHandler: { [weak self] level in
                    self?.pushAudioLevel(level)
                }
            )
        } catch {
            recordingHUDController.hide()
            resetAudioVisualization()
            activeInsertionTarget = nil
            phase = .idle
            statusMessage = error.localizedDescription
        }
    }

    func endHold() {
        guard phase == .recording else { return }

        recordingHUDController.hide()
        resetAudioVisualization()
        phase = .transcribing
        statusMessage = "Finishing recognition..."

        Task {
            do {
                let transcript = try await speechService.finishSession()
                await finishTranscriptInsertion(transcript)
            } catch {
                phase = .idle
                activeInsertionTarget = nil
                statusMessage = error.localizedDescription
            }
        }
    }

    func cancelActiveSession() {
        speechService.cancelSession()
        recordingHUDController.hide()
        resetAudioVisualization()
        activeInsertionTarget = nil
        completeActiveAutotestTrigger(result: "cancelled")
        phase = .idle
        statusMessage = "Recording cancelled."
    }

    func requestPermissionsFromUI() {
        Task {
            await requestPermissions()
        }
    }

    func refreshPermissionsFromUI() {
        Task {
            await refreshPermissions()
        }
    }

    func openSystemSettings(for permission: SettingsPermission) {
        permissionManager.openSystemSettings(for: permission)
        schedulePermissionRefreshBurst()
    }

    func togglePanelVisibility() {
        setPanelVisibility(!isPanelVisible)
    }

    func setPanelVisibility(_ visible: Bool) {
        isPanelVisible = visible
        UserDefaults.standard.set(visible, forKey: DefaultsKey.panelVisible)
        applyPanelVisibility()
    }

    func completeInitialSetup() {
        requiresInitialSetup = false
        UserDefaults.standard.set(true, forKey: DefaultsKey.initialSetupCompleted)

        if permissions.essentialsGranted {
            statusMessage = "Setup complete. VoiceInsert is now running in the background."
        } else {
            statusMessage = "Setup saved. VoiceInsert is running in the background."
        }
    }

    func finishSettings() {
        if requiresInitialSetup {
            completeInitialSetup()
        }

        settingsWindowController.close()
    }

    func firstLaunchMessage() -> String {
        "Set your shortcut, grant microphone and speech recognition, then click OK. Accessibility is optional."
    }

    func backgroundModeMessage() -> String {
        "VoiceInsert is running in the background. Use your shortcut whenever you want to dictate."
    }

    private func applyPanelVisibility() {
        if isPanelVisible {
            floatingPanelController.show()
        } else {
            floatingPanelController.hide()
        }
    }

    func openSettings() {
        refreshPermissionsFromUI()
        settingsWindowController.show()
    }

    func startShortcutRecording() {
        isRecordingShortcut = true
        statusMessage = "Press the new shortcut in Settings."
        openSettings()
    }

    func cancelShortcutRecording() {
        isRecordingShortcut = false
        statusMessage = "Shortcut recording cancelled."
    }

    func updateKeyboardShortcut(_ shortcut: KeyboardShortcut) {
        keyboardShortcut = shortcut
        KeyboardShortcutStore.save(shortcut)
        hotkeyMonitor.updateShortcut(shortcut)
        isRecordingShortcut = false
        statusMessage = "Shortcut updated to \(shortcut.displayString)."
    }

    func quit() {
        permissionRefreshTask?.cancel()
        autotestTriggerTask?.cancel()
        recordingHUDController.hide()
        NSApp.terminate(nil)
    }

    func relaunch() {
        permissionRefreshTask?.cancel()
        autotestTriggerTask?.cancel()
        recordingHUDController.hide()
        floatingPanelController.hide()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    self.statusMessage = "Couldn't relaunch VoiceInsert: \(error.localizedDescription)"
                    return
                }

                NSApp.terminate(nil)
            }
        }
    }

    private func requestPermissions() async {
        _ = await permissionManager.requestMicrophonePermission()
        _ = await permissionManager.requestSpeechPermission()
        _ = permissionManager.requestInputMonitoringPermission()
        _ = permissionManager.promptForAccessibilityIfNeeded()
        schedulePermissionRefreshBurst()
        await refreshPermissions()
        prewarmSpeechPipeline()
    }

    private func refreshPermissions() async {
        refreshPermissionsImmediately()
    }

    private func refreshPermissionsImmediately() {
        hotkeyMonitor.start()
        permissions = PermissionSnapshot.current()
        UserDefaults.standard.set(
            "microphone=\(permissions.microphone.title);speech=\(permissions.speech.title);input=\(permissions.inputMonitoring.title);accessibility=\(permissions.accessibility.title)",
            forKey: DefaultsKey.permissionDebugSnapshot
        )
        updatePermissionStatusMessage()

        if permissions.microphone == .authorized, permissions.speech == .authorized {
            prewarmSpeechPipeline()
        }
    }

    private func requestEssentialPermissionsIfNeeded() async {
        guard permissions.microphone == .notDetermined || permissions.speech == .notDetermined else { return }
        await requestPermissions()
    }

    private func pushAudioLevel(_ level: Double) {
        recordingFeedback.push(level: level)
    }

    private func resetAudioVisualization() {
        recordingFeedback.reset()
    }

    private func prewarmSpeechPipeline() {
        speechService.prewarm(locale: Self.dictationLocale)
    }

    private func processPendingAutotestTriggerIfNeeded() async {
        guard let triggerToken = AutotestDefaults.pendingTriggerToken(),
              triggerToken != lastObservedAutotestTriggerToken else {
            return
        }

        lastObservedAutotestTriggerToken = triggerToken

        guard phase == .idle else {
            AutotestDefaults.recordCompletion(for: triggerToken, result: "busy")
            return
        }

        guard let transcript = AutotestDefaults.pendingTranscript() else {
            AutotestDefaults.recordCompletion(for: triggerToken, result: "missing_transcript")
            return
        }

        liveTranscript = ""
        resetAudioVisualization()
        activeInsertionTarget = insertionService.captureTarget()
        activeAutotestTriggerToken = triggerToken
        phase = .transcribing
        statusMessage = "Running insertion test..."
        await finishTranscriptInsertion(transcript)
    }

    private func finishTranscriptInsertion(_ transcript: String) async {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTranscript.isEmpty else {
            phase = .idle
            liveTranscript = ""
            activeInsertionTarget = nil
            completeActiveAutotestTrigger(result: "empty")
            statusMessage = "No speech was recognized. Try a slightly longer phrase."
            return
        }

        do {
            liveTranscript = trimmedTranscript
            try await insertionService.insert(text: trimmedTranscript, target: activeInsertionTarget)
            phase = .idle
            activeInsertionTarget = nil
            completeActiveAutotestTrigger(result: "success")
            statusMessage = "Text inserted."
        } catch {
            phase = .idle
            activeInsertionTarget = nil
            completeActiveAutotestTrigger(result: "error")
            statusMessage = error.localizedDescription
        }
    }

    private func completeActiveAutotestTrigger(result: String) {
        guard let triggerToken = activeAutotestTriggerToken else { return }
        AutotestDefaults.recordCompletion(for: triggerToken, result: result)
        activeAutotestTriggerToken = nil
    }

    private func updatePermissionStatusMessage() {
        guard phase == .idle else { return }

        if permissions.essentialsGranted {
            if hotkeyMonitorState != .globalTap {
                statusMessage = permissions.inputMonitoring == .authorized
                    ? "VoiceInsert is running, but the global shortcut is not armed yet."
                    : "Dictation is ready, but the global shortcut still needs Input Monitoring."
                return
            }

            if permissions.inputMonitoring != .authorized {
                statusMessage = "Dictation is ready, but the global shortcut still needs Input Monitoring."
                return
            }

            statusMessage = requiresInitialSetup
                ? "Permissions look good. Click OK when you're done with first-run setup."
                : permissions.accessibility == .authorized
                    ? "All permissions are granted. You're ready to dictate."
                    : "Required permissions are granted. You're ready to dictate."
            return
        }

        statusMessage = permissions.missingText
    }

    private func schedulePermissionRefreshBurst() {
        permissionRefreshTask?.cancel()
        permissionRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for _ in 0..<12 {
                if Task.isCancelled { return }
                await self.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private static func loadPanelVisibility() -> Bool {
        if UserDefaults.standard.object(forKey: DefaultsKey.panelVisible) == nil {
            return false
        }

        return UserDefaults.standard.bool(forKey: DefaultsKey.panelVisible)
    }

    private static func loadRequiresInitialSetup() -> Bool {
        !UserDefaults.standard.bool(forKey: DefaultsKey.initialSetupCompleted)
    }

    private static func loadHotkeyMonitorState() -> HotkeyMonitorState {
        guard let rawValue = UserDefaults.standard.string(forKey: DefaultsKey.hotkeyMonitorState),
              let state = HotkeyMonitorState(rawValue: rawValue) else {
            return .inactive
        }

        return state
    }

    private static func initialStatusMessage() -> String {
        loadRequiresInitialSetup()
            ? "Set your shortcut, grant permissions, then click OK. After that, VoiceInsert will stay in the background."
            : "VoiceInsert is running in the background. Use your shortcut whenever you want to dictate."
    }
}

enum RecordingPhase {
    case idle
    case recording
    case transcribing
}

private enum DefaultsKey {
    static let initialSetupCompleted = "voiceInsert.initialSetupCompleted"
    static let panelVisible = "voiceInsert.panelVisible"
    static let hotkeyMonitorState = "voiceInsert.hotkeyMonitorState"
    static let permissionDebugSnapshot = "voiceInsert.permissionDebugSnapshot"
}

private enum AutotestDefaults {
    static let transcript = "voiceInsert.autotestTranscript"
    static let triggerToken = "voiceInsert.autotestTriggerToken"
    static let lastCompletedTriggerToken = "voiceInsert.autotestLastTriggerToken"
    static let lastCompletedResult = "voiceInsert.autotestLastResult"

    static func pendingTranscript() -> String? {
        guard let transcript = UserDefaults.standard.string(forKey: transcript)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !transcript.isEmpty else {
            return nil
        }

        return transcript
    }

    static func pendingTriggerToken() -> String? {
        guard let token = UserDefaults.standard.string(forKey: triggerToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }

        return token
    }

    static func recordCompletion(for token: String, result: String) {
        UserDefaults.standard.set(token, forKey: lastCompletedTriggerToken)
        UserDefaults.standard.set(result, forKey: lastCompletedResult)
        UserDefaults.standard.removeObject(forKey: transcript)
        UserDefaults.standard.removeObject(forKey: triggerToken)
    }

    static func clearStaleStateOnLaunch() {
        let defaults = UserDefaults.standard
        let pendingToken = pendingTriggerToken()
        let completedToken = defaults.string(forKey: lastCompletedTriggerToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let transcriptValue = pendingTranscript()

        if pendingToken == nil || pendingToken == completedToken {
            defaults.removeObject(forKey: triggerToken)
            defaults.removeObject(forKey: transcript)
        }

        if transcriptValue == nil {
            defaults.removeObject(forKey: transcript)
        }
    }
}
