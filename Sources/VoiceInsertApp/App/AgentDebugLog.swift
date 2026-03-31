import Foundation

/// Сессионные логи для отладки (NDJSON). Не логировать секреты/PII.
enum AgentDebugLog {
    private static let sessionId = "06a7fa"
    private static let logPath = "/Users/vishnevsky/Desktop/голосовое управление/.cursor/debug-06a7fa.log"

    static func append(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String] = [:]
    ) {
        // #region agent log
        var payload: [String: Any] = [
            "sessionId": sessionId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        if !data.isEmpty {
            payload["data"] = data
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let json = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: json, encoding: .utf8) else {
            return
        }
        line.append("\n")
        guard let bytes = line.data(using: .utf8) else { return }
        let parent = (logPath as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: parent) {
            try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: bytes, attributes: nil)
            return
        }
        guard let handle = FileHandle(forWritingAtPath: logPath) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: bytes)
        } catch {}
        // #endregion
    }
}
