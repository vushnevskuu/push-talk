import AVFoundation
import ApplicationServices
import AppKit
import Speech

enum PermissionState: Equatable {
    case authorized
    case denied
    case restricted
    case notDetermined

    var title: String {
        switch self {
        case .authorized:
            return "Allowed"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Requested"
        }
    }
}

struct PermissionSnapshot: Equatable {
    let microphone: PermissionState
    let speech: PermissionState
    let inputMonitoring: PermissionState
    let accessibility: PermissionState

    static func current() -> Self {
        Self(
            microphone: Self.mapMicrophone(AVCaptureDevice.authorizationStatus(for: .audio)),
            speech: Self.mapSpeech(SFSpeechRecognizer.authorizationStatus()),
            inputMonitoring: Self.currentInputMonitoringState(),
            accessibility: AXIsProcessTrusted() ? .authorized : .denied
        )
    }

    var allGranted: Bool {
        microphone == .authorized &&
        speech == .authorized &&
        inputMonitoring == .authorized &&
        accessibility == .authorized
    }

    var essentialsGranted: Bool {
        microphone == .authorized && speech == .authorized
    }

    var shortcutReady: Bool {
        essentialsGranted && inputMonitoring == .authorized
    }

    var missingText: String {
        let missing = [
            microphone == .authorized ? nil : "microphone",
            speech == .authorized ? nil : "speech recognition"
        ].compactMap { $0 }

        guard !missing.isEmpty else {
            if inputMonitoring != .authorized {
                return "Dictation permissions are active, but Input Monitoring is still missing. Enable it so the global shortcut works in other apps."
            }

            return accessibility == .authorized
                ? "All permissions are active."
                : "Microphone, speech recognition, and Input Monitoring are active. Turn on Accessibility for reliable typing and paste in other apps."
        }

        return "Missing required permissions: \(missing.joined(separator: ", "))."
    }

    private static func mapMicrophone(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    private static func mapSpeech(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    private static func currentInputMonitoringState() -> PermissionState {
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess() ? .authorized : .denied
        }

        return .authorized
    }
}

@MainActor
final class PermissionManager {
    func requestMicrophonePermission() async -> PermissionState {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard currentStatus == .notDetermined else {
            return PermissionSnapshot.current().microphone
        }

        let granted = await requestMicrophoneAccess()

        return granted ? .authorized : .denied
    }

    func requestSpeechPermission() async -> PermissionState {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        guard currentStatus == .notDetermined else {
            return PermissionSnapshot.current().speech
        }

        let status = await requestSpeechAuthorization()

        switch status {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    @discardableResult
    func promptForAccessibilityIfNeeded() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func requestInputMonitoringPermission() -> Bool {
        if #available(macOS 10.15, *) {
            guard !CGPreflightListenEventAccess() else { return true }
            return CGRequestListenEventAccess()
        }

        return true
    }

    func openSystemSettings(for permission: SettingsPermission) {
        guard let url = URL(string: permission.urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

private func requestMicrophoneAccess() async -> Bool {
    await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .audio) { allowed in
            continuation.resume(returning: allowed)
        }
    }
}

private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
    await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { authorizationStatus in
            continuation.resume(returning: authorizationStatus)
        }
    }
}

enum SettingsPermission {
    case microphone
    case speech
    case inputMonitoring
    case accessibility

    var urlString: String {
        switch self {
        case .microphone:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .speech:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        case .inputMonitoring:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .accessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
    }
}
