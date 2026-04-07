import Foundation

/// Subscription enforcement is **off** when the plist value is missing or blank, or when
/// `VOICEINSERT_SKIP_ENTITLEMENT=1` is set in the environment (local dev / CI smoke tests).
enum EntitlementConfig {
    private static let plistKey = "VoiceInsertEntitlementBaseURL"

    static var isEnforcementEnabled: Bool {
        if ProcessInfo.processInfo.environment["VOICEINSERT_SKIP_ENTITLEMENT"] == "1" {
            return false
        }
        guard let raw = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String else {
            return false
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return false
        }
        return true
    }

    /// Normalized origin without trailing slash, e.g. `https://push-talk.vercel.app`
    static var baseURLString: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.trimmingSuffix("/")
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix), count >= suffix.count else { return self }
        return String(dropLast(suffix.count))
    }
}
