import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var autoPunctuation = true
    @Published private(set) var keyboardShortcut = KeyboardShortcutStore.load(.fieldInsert)
    @Published private(set) var obsidianShortcut = KeyboardShortcutStore.load(.obsidianCapture)
    @Published private(set) var liveTranscript = ""
    @Published private(set) var statusMessage = AppModel.initialStatusMessage()
    @Published private(set) var phase: RecordingPhase = .idle
    @Published private(set) var permissions = PermissionSnapshot.current()
    @Published private(set) var hotkeyMonitorState = AppModel.loadHotkeyMonitorState(for: .fieldInsert)
    @Published private(set) var obsidianHotkeyMonitorState = AppModel.loadHotkeyMonitorState(for: .obsidianCapture)
    @Published private(set) var isPanelVisible = AppModel.loadPanelVisibility()
    @Published private(set) var recordingHUDStyle = AppModel.loadRecordingHUDStyle()
    @Published private(set) var dictationLanguage = AppModel.loadDictationLanguage()
    @Published private(set) var requiresInitialSetup = AppModel.loadRequiresInitialSetup()
    @Published private(set) var obsidianVaultPath = AppModel.loadObsidianVaultPath()
    @Published var isRecordingShortcut = false {
        didSet {
            synchronizeRecorderState(changed: .fieldInsert)
        }
    }
    @Published var isRecordingObsidianShortcut = false {
        didSet {
            synchronizeRecorderState(changed: .obsidianCapture)
        }
    }

    let permissionManager = PermissionManager()
    let recordingFeedback = RecordingFeedbackModel()
    private let speechService = SpeechRecognitionService()
    private let insertionService = TextInsertionService()
    private let obsidianCaptureService = ObsidianCaptureService()
    private let floatingPanelController = FloatingPanelController()
    private let recordingHUDController = RecordingHUDController()
    private let hotkeyMonitor = HotkeyMonitor()
    private let obsidianHotkeyMonitor = HotkeyMonitor()
    private var permissionRefreshTask: Task<Void, Never>?
    private var autotestTriggerTask: Task<Void, Never>?
    private var activeInsertionTarget: TextInsertionTarget?
    private var activeCaptureDestination: CaptureDestination?
    private var activeAutotestTriggerToken: String?
    private var activeObsidianAutotestTriggerToken: String?
    private var lastObservedAutotestTriggerToken: String?
    private var lastObservedObsidianAutotestTriggerToken: String?
    private var isSynchronizingRecorderState = false
    /// Invalidates in-flight `finishSession` work when the user cancels from the menu or floating panel.
    private var captureSessionGeneration: UInt64 = 0
    private lazy var settingsWindowController = SettingsWindowController(model: self)

    init() {
        AutotestDefaults.clearStaleStateOnLaunch()
        lastObservedAutotestTriggerToken = AutotestDefaults.pendingTriggerToken()
        lastObservedObsidianAutotestTriggerToken = AutotestDefaults.pendingObsidianTriggerToken()

        floatingPanelController.attach(to: self)
        recordingHUDController.attach(to: recordingFeedback, style: recordingHUDStyle)
        hotkeyMonitor.updateShortcut(keyboardShortcut)
        obsidianHotkeyMonitor.updateShortcut(obsidianShortcut)
        hotkeyMonitor.setHandlers(onPress: { [weak self] in
            self?.startHold(for: .fieldInsert)
        }, onRelease: { [weak self] in
            self?.endHold(for: .fieldInsert)
        })
        obsidianHotkeyMonitor.setHandlers(onPress: { [weak self] in
            self?.startHold(for: .obsidianVault)
        }, onRelease: { [weak self] in
            self?.endHold(for: .obsidianVault)
        })
        hotkeyMonitor.setStateHandler { [weak self] state in
            self?.hotkeyMonitorState = state
            UserDefaults.standard.set(state.rawValue, forKey: DefaultsKey.hotkeyMonitorStateInsert)
        }
        obsidianHotkeyMonitor.setStateHandler { [weak self] state in
            self?.obsidianHotkeyMonitorState = state
            UserDefaults.standard.set(state.rawValue, forKey: DefaultsKey.hotkeyMonitorStateObsidian)
        }
        hotkeyMonitor.start()
        obsidianHotkeyMonitor.start()

        speechService.cancelSession()
        recordingHUDController.hide()

        persistRuntimeDebugState()

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
            return activeCaptureDestination == .obsidianVault ? "Listening for Obsidian..." : "Listening..."
        case .transcribing:
            return activeCaptureDestination == .obsidianVault ? "Saving to Obsidian..." : "Transcribing..."
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

                if obsidianVaultURL != nil {
                    return "Use \(shortcutDisplayText) to dictate into focused fields, or \(obsidianShortcutDisplayText) to file a note into Obsidian."
                }

                if permissions.accessibility == .authorized {
                    return "Text will be inserted into the field that currently has focus."
                }

                return "VoiceInsert will paste into the active field. Accessibility can improve direct insertion in some apps."
            }

            return permissions.missingText
        case .recording:
            return activeCaptureDestination == .obsidianVault
                ? "Keep holding while you speak. Release to file the note into your Obsidian vault."
                : "Keep holding for long messages. Release when you finish speaking."
        case .transcribing:
            return activeCaptureDestination == .obsidianVault
                ? "Sorting the note into your Obsidian folders."
                : "Finishing recognition and inserting text."
        }
    }

    var shortcutDisplayText: String {
        keyboardShortcut.displayString
    }

    var obsidianShortcutDisplayText: String {
        obsidianShortcut.displayString
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

    var obsidianHotkeyStatusTitle: String {
        switch obsidianHotkeyMonitorState {
        case .globalTap:
            return "Global"
        case .localFallback:
            return "Local Only"
        case .inactive:
            return "Starting"
        }
    }

    var obsidianVaultDisplayText: String {
        guard let obsidianVaultPath else {
            return "Choose Vault"
        }

        return URL(fileURLWithPath: obsidianVaultPath).lastPathComponent
    }

    var obsidianVaultDetailText: String {
        guard let obsidianVaultPath else {
            return "Pick the folder that contains your .obsidian directory."
        }

        return obsidianVaultPath
    }

    var obsidianVaultLinked: Bool {
        obsidianVaultURL != nil
    }

    var obsidianCaptureReady: Bool {
        permissions.shortcutReady && obsidianVaultLinked
    }

    var obsidianCaptureHelpText: String {
        guard obsidianVaultLinked else {
            return "Choose your Obsidian vault first. VoiceInsert will create Voice Captures/Ideas, Tasks, Notes, Meetings, Journal, and Inbox inside that vault."
        }

        guard permissions.shortcutReady else {
            return "Obsidian capture uses the same microphone, speech, and Input Monitoring pipeline as field insertion. Finish those permissions and this shortcut will work too."
        }

        return "Hold \(obsidianShortcutDisplayText) and say things like “эта идея ...”, “задача ...”, or “заметка ...”. VoiceInsert will sort the note into the matching Obsidian folder."
    }

    func startHold() {
        startHold(for: .fieldInsert)
    }

    func startHold(for destination: CaptureDestination) {
        guard phase == .idle else { return }

        if permissions.microphone != .authorized || permissions.speech != .authorized {
            refreshPermissionsImmediately()
        }

        guard permissions.microphone == .authorized else {
            statusMessage = "Microphone access is required."
            NSSound.beep()
            Task { await requestPermissions() }
            return
        }

        guard permissions.speech == .authorized else {
            statusMessage = "Speech recognition access is required."
            NSSound.beep()
            Task { await requestPermissions() }
            return
        }

        if destination == .obsidianVault, obsidianVaultURL == nil {
            statusMessage = "Choose your Obsidian vault before using the Obsidian shortcut."
            NSSound.beep()
            openSettings()
            return
        }

        do {
            liveTranscript = ""
            resetAudioVisualization()
            activeCaptureDestination = destination
            activeInsertionTarget = destination == .fieldInsert
                ? insertionService.captureTarget(includeFocusedElement: false)
                : nil
            phase = .recording
            recordHotkeyActivation(for: destination)
            persistRuntimeDebugState()
            statusMessage = destination == .obsidianVault ? "Listening for Obsidian..." : "Listening..."
            recordingHUDController.show()

            try speechService.startSession(
                locale: dictationLocale,
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
        endHold(for: .fieldInsert)
    }

    func endHold(for destination: CaptureDestination) {
        guard phase == .recording, activeCaptureDestination == destination else { return }

        recordingHUDController.hide()
        resetAudioVisualization()
        phase = .transcribing
        persistRuntimeDebugState()
        statusMessage = destination == .obsidianVault ? "Saving to Obsidian..." : "Finishing recognition..."

        captureSessionGeneration += 1
        let generation = captureSessionGeneration

        Task { @MainActor in
            do {
                let transcript = try await speechService.finishSession()
                guard generation == captureSessionGeneration else { return }
                await finishCapture(transcript, destination: destination)
            } catch {
                guard generation == captureSessionGeneration else { return }
                phase = .idle
                activeInsertionTarget = nil
                activeCaptureDestination = nil
                persistRuntimeDebugState()
                statusMessage = error.localizedDescription
            }
        }
    }

    func cancelActiveSession() {
        captureSessionGeneration += 1
        speechService.cancelSession()
        recordingHUDController.hide()
        resetAudioVisualization()
        activeInsertionTarget = nil
        activeCaptureDestination = nil
        completeActiveAutotestTrigger(result: "cancelled")
        completeActiveObsidianAutotestTrigger(result: "cancelled")
        phase = .idle
        persistRuntimeDebugState()
        statusMessage = "Dictation cancelled."
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

    func updateRecordingHUDStyle(_ style: RecordingHUDStyle) {
        guard recordingHUDStyle != style else { return }

        recordingHUDStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: DefaultsKey.recordingHUDStyle)
        recordingHUDController.updateStyle(style)
    }

    func updateDictationLanguage(_ language: DictationLanguage) {
        guard dictationLanguage != language else { return }

        guard phase == .idle else {
            statusMessage = "Finish or cancel dictation before changing the dictation language."
            NSSound.beep()
            return
        }

        dictationLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: DefaultsKey.dictationLanguage)
        speechService.cancelSession()
        prewarmSpeechPipeline()
        scheduleMicrophoneRoutePrewarmFromIdleState()
        statusMessage = "Язык распознавания: \(language.title) (\(language.speechLocale.identifier))."
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

    func startObsidianShortcutRecording() {
        isRecordingObsidianShortcut = true
        statusMessage = "Press the new Obsidian shortcut in Settings."
        openSettings()
    }

    func cancelShortcutRecording() {
        isRecordingShortcut = false
        statusMessage = "Shortcut recording cancelled."
    }

    func cancelObsidianShortcutRecording() {
        isRecordingObsidianShortcut = false
        statusMessage = "Obsidian shortcut recording cancelled."
    }

    func updateKeyboardShortcut(_ shortcut: KeyboardShortcut) {
        guard validateShortcutUniqueness(shortcut, for: .fieldInsert) else { return }
        keyboardShortcut = shortcut
        KeyboardShortcutStore.save(shortcut, kind: .fieldInsert)
        hotkeyMonitor.updateShortcut(shortcut)
        isRecordingShortcut = false
        statusMessage = "Shortcut updated to \(shortcut.displayString)."
    }

    func updateObsidianShortcut(_ shortcut: KeyboardShortcut) {
        guard validateShortcutUniqueness(shortcut, for: .obsidianCapture) else { return }
        obsidianShortcut = shortcut
        KeyboardShortcutStore.save(shortcut, kind: .obsidianCapture)
        obsidianHotkeyMonitor.updateShortcut(shortcut)
        isRecordingObsidianShortcut = false
        statusMessage = "Obsidian shortcut updated to \(shortcut.displayString)."
    }

    func chooseObsidianVault() {
        let panel = NSOpenPanel()
        panel.title = "Choose Obsidian Vault"
        panel.message = "Select the folder that contains your .obsidian directory."
        panel.prompt = "Choose Vault"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false

        if let obsidianVaultPath {
            panel.directoryURL = URL(fileURLWithPath: obsidianVaultPath, isDirectory: true)
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try obsidianCaptureService.validateVault(url: url)
            obsidianVaultPath = url.path
            UserDefaults.standard.set(url.path, forKey: DefaultsKey.obsidianVaultPath)
            statusMessage = "Obsidian vault linked to \(url.lastPathComponent)."
        } catch {
            statusMessage = error.localizedDescription
            NSSound.beep()
        }
    }

    func revealObsidianVault() {
        guard let obsidianVaultPath else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: obsidianVaultPath)
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
        obsidianHotkeyMonitor.start()
        permissions = PermissionSnapshot.current()
        UserDefaults.standard.set(
            "microphone=\(permissions.microphone.title);speech=\(permissions.speech.title);input=\(permissions.inputMonitoring.title);accessibility=\(permissions.accessibility.title)",
            forKey: DefaultsKey.permissionDebugSnapshot
        )
        updatePermissionStatusMessage()

        if permissions.microphone == .authorized, permissions.speech == .authorized {
            prewarmSpeechPipeline()
            scheduleMicrophoneRoutePrewarmFromIdleState()
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
        speechService.prewarm(locale: dictationLocale)
    }

    private func scheduleMicrophoneRoutePrewarmFromIdleState() {
        guard phase == .idle else { return }
        speechService.scheduleMicrophoneRoutePrewarmIfNeeded()
    }

    private var dictationLocale: Locale {
        dictationLanguage.speechLocale
    }

    private func processPendingAutotestTriggerIfNeeded() async {
        guard let triggerToken = AutotestDefaults.pendingTriggerToken(),
              triggerToken != lastObservedAutotestTriggerToken else {
            await processPendingObsidianAutotestTriggerIfNeeded()
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
            activeCaptureDestination = .fieldInsert
            activeInsertionTarget = insertionService.captureTarget()
            activeAutotestTriggerToken = triggerToken
            phase = .transcribing
            persistRuntimeDebugState()
            statusMessage = "Running insertion test..."
            await finishCapture(transcript, destination: .fieldInsert)
        await processPendingObsidianAutotestTriggerIfNeeded()
    }

    private func processPendingObsidianAutotestTriggerIfNeeded() async {
        guard let triggerToken = AutotestDefaults.pendingObsidianTriggerToken(),
              triggerToken != lastObservedObsidianAutotestTriggerToken else {
            return
        }

        lastObservedObsidianAutotestTriggerToken = triggerToken

        guard phase == .idle else {
            AutotestDefaults.recordObsidianCompletion(for: triggerToken, result: "busy")
            return
        }

        guard let transcript = AutotestDefaults.pendingTranscript() else {
            AutotestDefaults.recordObsidianCompletion(for: triggerToken, result: "missing_transcript")
            return
        }

        guard let vaultPath = AutotestDefaults.pendingObsidianVaultPath() else {
            AutotestDefaults.recordObsidianCompletion(for: triggerToken, result: "missing_vault")
            return
        }

        liveTranscript = ""
        resetAudioVisualization()
        activeCaptureDestination = .obsidianVault
        activeInsertionTarget = nil
        activeObsidianAutotestTriggerToken = triggerToken
        obsidianVaultPath = vaultPath
        phase = .transcribing
        persistRuntimeDebugState()
        statusMessage = "Running Obsidian capture test..."
        await finishCapture(transcript, destination: .obsidianVault)
    }

    private func finishCapture(_ transcript: String, destination: CaptureDestination) async {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTranscript.isEmpty else {
            phase = .idle
            liveTranscript = ""
            activeInsertionTarget = nil
            activeCaptureDestination = nil
            persistRuntimeDebugState()
            if destination == .fieldInsert {
                completeActiveAutotestTrigger(result: "empty")
            } else {
                completeActiveObsidianAutotestTrigger(result: "empty")
            }
            statusMessage = "No speech was recognized. Try a slightly longer phrase."
            return
        }

        do {
            liveTranscript = trimmedTranscript
            switch destination {
            case .fieldInsert:
                try await insertionService.insert(text: trimmedTranscript, target: activeInsertionTarget)
            case .obsidianVault:
                let result = try obsidianCaptureService.capture(
                    transcript: trimmedTranscript,
                    vaultPath: obsidianVaultPath
                )
                completeActiveObsidianAutotestTrigger(
                    result: "success",
                    notePath: result.noteURL.path
                )
                statusMessage = "Saved to Obsidian → \(result.relativeFolderPath)."
            }
            phase = .idle
            activeInsertionTarget = nil
            activeCaptureDestination = nil
            persistRuntimeDebugState()
            if destination == .fieldInsert {
                completeActiveAutotestTrigger(result: "success")
                statusMessage = "Text inserted."
            }
        } catch {
            phase = .idle
            activeInsertionTarget = nil
            activeCaptureDestination = nil
            persistRuntimeDebugState()
            if destination == .fieldInsert {
                completeActiveAutotestTrigger(result: "error")
            } else {
                completeActiveObsidianAutotestTrigger(result: "error")
            }
            statusMessage = error.localizedDescription
        }
    }

    private func completeActiveAutotestTrigger(result: String) {
        guard let triggerToken = activeAutotestTriggerToken else { return }
        AutotestDefaults.recordCompletion(for: triggerToken, result: result)
        activeAutotestTriggerToken = nil
    }

    private func completeActiveObsidianAutotestTrigger(result: String, notePath: String? = nil) {
        guard let triggerToken = activeObsidianAutotestTriggerToken else { return }
        AutotestDefaults.recordObsidianCompletion(for: triggerToken, result: result, notePath: notePath)
        activeObsidianAutotestTriggerToken = nil
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

    private static func loadRecordingHUDStyle() -> RecordingHUDStyle {
        guard let rawValue = UserDefaults.standard.string(forKey: DefaultsKey.recordingHUDStyle),
              let style = RecordingHUDStyle(rawValue: rawValue) else {
            return .glassBar
        }

        return style
    }

    private static func loadDictationLanguage() -> DictationLanguage {
        if let rawValue = UserDefaults.standard.string(forKey: DefaultsKey.dictationLanguage),
           let language = DictationLanguage(rawValue: rawValue) {
            return language
        }
        if let first = Locale.preferredLanguages.first,
           first.hasPrefix("en") {
            return .english
        }
        return .russian
    }

    private static func loadRequiresInitialSetup() -> Bool {
        !UserDefaults.standard.bool(forKey: DefaultsKey.initialSetupCompleted)
    }

    private static func loadObsidianVaultPath() -> String? {
        guard let path = UserDefaults.standard.string(forKey: DefaultsKey.obsidianVaultPath)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }

        return path
    }

    private static func loadHotkeyMonitorState(for kind: ShortcutKind) -> HotkeyMonitorState {
        let defaultsKey: String

        switch kind {
        case .fieldInsert:
            defaultsKey = DefaultsKey.hotkeyMonitorStateInsert
        case .obsidianCapture:
            defaultsKey = DefaultsKey.hotkeyMonitorStateObsidian
        }

        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
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

    private func synchronizeRecorderState(changed kind: ShortcutKind) {
        guard !isSynchronizingRecorderState else { return }

        isSynchronizingRecorderState = true
        defer { isSynchronizingRecorderState = false }

        switch kind {
        case .fieldInsert:
            if isRecordingShortcut {
                isRecordingObsidianShortcut = false
            }
        case .obsidianCapture:
            if isRecordingObsidianShortcut {
                isRecordingShortcut = false
            }
        }

        let suspended = isRecordingShortcut || isRecordingObsidianShortcut
        hotkeyMonitor.setSuspended(suspended)
        obsidianHotkeyMonitor.setSuspended(suspended)
    }

    private func validateShortcutUniqueness(_ shortcut: KeyboardShortcut, for kind: ShortcutKind) -> Bool {
        let conflictingShortcut = kind == .fieldInsert ? obsidianShortcut : keyboardShortcut

        guard shortcut != conflictingShortcut else {
            statusMessage = "\(kind.displayTitle) needs a different shortcut than the other mode."
            NSSound.beep()
            return false
        }

        return true
    }

    private var obsidianVaultURL: URL? {
        guard obsidianCaptureService.isValidVault(path: obsidianVaultPath),
              let obsidianVaultPath else {
            return nil
        }

        return URL(fileURLWithPath: obsidianVaultPath, isDirectory: true)
    }

    private func persistRuntimeDebugState() {
        UserDefaults.standard.set(phase.debugValue, forKey: DefaultsKey.debugPhase)
        UserDefaults.standard.set(activeCaptureDestination?.debugValue ?? "none", forKey: DefaultsKey.debugCaptureDestination)
    }

    private func recordHotkeyActivation(for destination: CaptureDestination) {
        UserDefaults.standard.set(destination.debugValue, forKey: DefaultsKey.debugLastStartedDestination)
    }
}

enum RecordingPhase {
    case idle
    case recording
    case transcribing

    var debugValue: String {
        switch self {
        case .idle:
            return "idle"
        case .recording:
            return "recording"
        case .transcribing:
            return "transcribing"
        }
    }
}

private enum DefaultsKey {
    static let initialSetupCompleted = "voiceInsert.initialSetupCompleted"
    static let panelVisible = "voiceInsert.panelVisible"
    static let recordingHUDStyle = "voiceInsert.recordingHUDStyle"
    static let dictationLanguage = "voiceInsert.dictationLanguage"
    static let hotkeyMonitorStateInsert = "voiceInsert.hotkeyMonitorState"
    static let hotkeyMonitorStateObsidian = "voiceInsert.obsidianHotkeyMonitorState"
    static let permissionDebugSnapshot = "voiceInsert.permissionDebugSnapshot"
    static let obsidianVaultPath = "voiceInsert.obsidianVaultPath"
    static let debugPhase = "voiceInsert.debugPhase"
    static let debugCaptureDestination = "voiceInsert.debugCaptureDestination"
    static let debugLastStartedDestination = "voiceInsert.debugLastStartedDestination"
}

enum CaptureDestination {
    case fieldInsert
    case obsidianVault

    var debugValue: String {
        switch self {
        case .fieldInsert:
            return "fieldInsert"
        case .obsidianVault:
            return "obsidianVault"
        }
    }
}

private enum AutotestDefaults {
    static let transcript = "voiceInsert.autotestTranscript"
    static let triggerToken = "voiceInsert.autotestTriggerToken"
    static let lastCompletedTriggerToken = "voiceInsert.autotestLastTriggerToken"
    static let lastCompletedResult = "voiceInsert.autotestLastResult"
    static let obsidianVaultPath = "voiceInsert.autotestObsidianVaultPath"
    static let obsidianTriggerToken = "voiceInsert.autotestObsidianTriggerToken"
    static let obsidianLastCompletedTriggerToken = "voiceInsert.autotestObsidianLastTriggerToken"
    static let obsidianLastCompletedResult = "voiceInsert.autotestObsidianLastResult"
    static let obsidianLastNotePath = "voiceInsert.autotestObsidianLastNotePath"

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

    static func pendingObsidianTriggerToken() -> String? {
        guard let token = UserDefaults.standard.string(forKey: obsidianTriggerToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }

        return token
    }

    static func pendingObsidianVaultPath() -> String? {
        guard let path = UserDefaults.standard.string(forKey: obsidianVaultPath)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }

        return path
    }

    static func recordCompletion(for token: String, result: String) {
        UserDefaults.standard.set(token, forKey: lastCompletedTriggerToken)
        UserDefaults.standard.set(result, forKey: lastCompletedResult)
        UserDefaults.standard.removeObject(forKey: transcript)
        UserDefaults.standard.removeObject(forKey: triggerToken)
    }

    static func recordObsidianCompletion(for token: String, result: String, notePath: String? = nil) {
        UserDefaults.standard.set(token, forKey: obsidianLastCompletedTriggerToken)
        UserDefaults.standard.set(result, forKey: obsidianLastCompletedResult)
        if let notePath {
            UserDefaults.standard.set(notePath, forKey: obsidianLastNotePath)
        } else {
            UserDefaults.standard.removeObject(forKey: obsidianLastNotePath)
        }
        UserDefaults.standard.removeObject(forKey: transcript)
        UserDefaults.standard.removeObject(forKey: obsidianTriggerToken)
        UserDefaults.standard.removeObject(forKey: obsidianVaultPath)
    }

    static func clearStaleStateOnLaunch() {
        let defaults = UserDefaults.standard
        let pendingToken = pendingTriggerToken()
        let completedToken = defaults.string(forKey: lastCompletedTriggerToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pendingObsidianToken = pendingObsidianTriggerToken()
        let completedObsidianToken = defaults.string(forKey: obsidianLastCompletedTriggerToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let transcriptValue = pendingTranscript()

        if pendingToken == nil || pendingToken == completedToken {
            defaults.removeObject(forKey: triggerToken)
        }

        if pendingObsidianToken == nil || pendingObsidianToken == completedObsidianToken {
            defaults.removeObject(forKey: obsidianTriggerToken)
            defaults.removeObject(forKey: obsidianVaultPath)
        }

        if transcriptValue == nil || (pendingToken == nil && pendingObsidianToken == nil) {
            defaults.removeObject(forKey: transcript)
        }
    }
}
