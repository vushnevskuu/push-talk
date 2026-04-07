import Foundation

/// JSON from `GET /api/entitlement` (Bearer token).
private struct EntitlementResponseBody: Decodable {
    let ok: Bool?
    let error: String?
    let status: String?
    let trialEndsAt: String?
    let currentPeriodEnd: String?
    let email: String?
}

enum EntitlementCheckResult: Equatable {
    /// Server said subscription is active (trial or paid period).
    case allowed(summary: String)
    /// Explicit denial (invalid token, canceled, unpaid, etc.).
    case denied(message: String)
    /// Network / decode / unexpected response — caller may apply offline grace.
    case transportFailure(description: String)
}

enum EntitlementAPI {
    static func check(baseURL: String, rawToken: String) async -> EntitlementCheckResult {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return .denied(message: "No access token saved.")
        }

        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingSuffix("/")
        guard let url = URL(string: base + "/api/entitlement") else {
            return .transportFailure(description: "Invalid entitlement URL in app configuration.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 25

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return .transportFailure(description: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            return .transportFailure(description: "No HTTP response.")
        }

        let decoded: EntitlementResponseBody
        do {
            decoded = try JSONDecoder().decode(EntitlementResponseBody.self, from: data)
        } catch {
            return .transportFailure(description: "Unexpected server response.")
        }

        if http.statusCode == 401 {
            let err = decoded.error ?? "invalid_token"
            return .denied(message: humanMessage(forServerError: err))
        }

        guard http.statusCode == 200 else {
            if let err = decoded.error, !err.isEmpty {
                return .denied(message: humanMessage(forServerError: err))
            }
            return .transportFailure(description: "Server error (HTTP \(http.statusCode)).")
        }

        if decoded.ok == true {
            let summary = buildSummary(status: decoded.status, trialEndsAt: decoded.trialEndsAt, periodEnd: decoded.currentPeriodEnd)
            return .allowed(summary: summary)
        }

        let err = decoded.error ?? "inactive"
        return .denied(message: humanMessage(forServerError: err))
    }

    private static func humanMessage(forServerError code: String) -> String {
        switch code {
        case "missing_bearer":
            return "No access token sent. Save your token in Settings → Subscription."
        case "invalid_token":
            return "Access token is invalid or revoked. Generate a new one on the website after signing in."
        case "no_subscription":
            return "No active subscription found. Complete checkout or renew your plan on the website."
        default:
            return "Subscription check failed (\(code))."
        }
    }

    private static func buildSummary(status: String?, trialEndsAt: String?, periodEnd: String?) -> String {
        let st = (status ?? "ACTIVE").uppercased()
        if st == "IN_TRIAL", let end = parseDate(trialEndsAt) {
            let f = Self.dateFormatter
            return "Trial active until \(f.string(from: end))."
        }
        if let end = parseDate(periodEnd) {
            let f = Self.dateFormatter
            return "Subscription active; current period ends \(f.string(from: end))."
        }
        if st == "IN_TRIAL" {
            return "Trial active."
        }
        return "Subscription active."
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale.autoupdatingCurrent
        return f
    }()

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) {
            return d
        }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix), count >= suffix.count else { return self }
        return String(dropLast(suffix.count))
    }
}
