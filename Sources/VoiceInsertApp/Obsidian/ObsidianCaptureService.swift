import Foundation

struct ObsidianCaptureResult: Sendable {
    let categoryTitle: String
    let relativeFolderPath: String
    let relativeNotePath: String
    let noteURL: URL
    let cleanedText: String
}

enum ObsidianCaptureError: LocalizedError {
    case vaultNotConfigured
    case invalidVault
    case emptyCapture
    case failedToWrite

    var errorDescription: String? {
        switch self {
        case .vaultNotConfigured:
            return "Choose your Obsidian vault before using the Obsidian shortcut."
        case .invalidVault:
            return "That folder doesn't look like an Obsidian vault."
        case .emptyCapture:
            return "No speech was recognized for the Obsidian note."
        case .failedToWrite:
            return "VoiceInsert couldn't save that note into your Obsidian vault."
        }
    }
}

final class ObsidianCaptureService {
    static let baseFolderName = "Voice Captures"

    private let fileManager = FileManager.default

    func isValidVault(path: String?) -> Bool {
        guard let path,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        return isValidVault(url: URL(fileURLWithPath: path))
    }

    func isValidVault(url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }

        let markerURL = url.appendingPathComponent(".obsidian", isDirectory: true)
        return fileManager.fileExists(atPath: markerURL.path, isDirectory: &isDirectory)
    }

    func validateVault(url: URL) throws {
        guard isValidVault(url: url) else {
            throw ObsidianCaptureError.invalidVault
        }
    }

    func capture(transcript: String, vaultPath: String?) throws -> ObsidianCaptureResult {
        guard let vaultPath,
              !vaultPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ObsidianCaptureError.vaultNotConfigured
        }

        let vaultURL = URL(fileURLWithPath: vaultPath, isDirectory: true)
        try validateVault(url: vaultURL)
        return try capture(transcript: transcript, vaultURL: vaultURL)
    }

    private func capture(transcript: String, vaultURL: URL) throws -> ObsidianCaptureResult {
        let trimmedTranscript = transcript
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTranscript.isEmpty else {
            throw ObsidianCaptureError.emptyCapture
        }

        let classification = classifyTranscript(trimmedTranscript)
        let now = Date()
        let folderURL = vaultURL
            .appendingPathComponent(Self.baseFolderName, isDirectory: true)
            .appendingPathComponent(classification.category.folderName, isDirectory: true)

        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            throw ObsidianCaptureError.failedToWrite
        }

        let title = noteTitle(for: classification.category, createdAt: now)
        let noteStem = noteFileStem(for: classification.category, createdAt: now)
        let noteURL = uniqueNoteURL(in: folderURL, preferredStem: noteStem)
        let noteBody = noteMarkdown(
            title: title,
            transcript: classification.cleanedText
        )

        do {
            try noteBody.write(to: noteURL, atomically: true, encoding: .utf8)
        } catch {
            throw ObsidianCaptureError.failedToWrite
        }

        let relativeFolderPath = "\(Self.baseFolderName)/\(classification.category.folderName)"
        let relativeNotePath = "\(relativeFolderPath)/\(noteURL.lastPathComponent)"

        return ObsidianCaptureResult(
            categoryTitle: classification.category.displayTitle,
            relativeFolderPath: relativeFolderPath,
            relativeNotePath: relativeNotePath,
            noteURL: noteURL,
            cleanedText: classification.cleanedText
        )
    }

    private func classifyTranscript(_ transcript: String) -> TranscriptClassification {
        for category in categories {
            if let cleaned = cleanedTranscript(from: transcript, removing: category.prefixMarkers) {
                return TranscriptClassification(category: category, cleanedText: cleaned)
            }
        }

        let searchableTokens = Set(
            transcript
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )

        for category in categories {
            if category.detectionKeywords.contains(where: searchableTokens.contains) {
                return TranscriptClassification(category: category, cleanedText: transcript)
            }
        }

        return TranscriptClassification(category: inboxCategory, cleanedText: transcript)
    }

    private func cleanedTranscript(from transcript: String, removing markers: [String]) -> String? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()

        for marker in markers {
            let loweredMarker = marker.lowercased()
            guard lowered.hasPrefix(loweredMarker) else { continue }

            let markerEndIndex = trimmed.index(trimmed.startIndex, offsetBy: marker.count)
            let remainder = trimmed[markerEndIndex...]
                .trimmingCharacters(in: Self.leadingDelimiterCharacterSet)

            return remainder.isEmpty ? trimmed : String(remainder)
        }

        return nil
    }

    private func noteTitle(for category: VoiceCaptureCategory, createdAt: Date) -> String {
        "\(headingDateFormatter.string(from: createdAt)) · \(category.noteHeadingLabel)"
    }

    private func noteFileStem(for category: VoiceCaptureCategory, createdAt: Date) -> String {
        let dateHead = "\(fileHumanDateFormatter.string(from: createdAt))г."
        let timeHead = fileTimeOnlyFormatter.string(from: createdAt)
        return "\(dateHead), \(timeHead) \(sanitizedFileComponent(category.noteHeadingLabel))"
    }

    private func noteMarkdown(
        title: String,
        transcript: String
    ) -> String {
        return """
        # \(title)

        \(transcript)
        """
    }

    private func uniqueNoteURL(in folderURL: URL, preferredStem: String) -> URL {
        var suffix = 1
        var candidate = folderURL.appendingPathComponent("\(preferredStem).md")

        while fileManager.fileExists(atPath: candidate.path) {
            suffix += 1
            candidate = folderURL.appendingPathComponent("\(preferredStem) \(suffix).md")
        }

        return candidate
    }

    private func sanitizedFileComponent(_ text: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let scalars = text.unicodeScalars.map { scalar in
            invalidCharacters.contains(scalar) ? " " : String(scalar)
        }
        let collapsed = scalars.joined()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return collapsed.isEmpty ? "Voice Capture" : collapsed
    }

    /// Имя файла: «17 марта 2026г., 15-06-07 …» — день и месяц словами, без цифрового ISO в начале.
    private let fileHumanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.setLocalizedDateFormatFromTemplate("dMMMM yyyy")
        return formatter
    }()

    private let fileTimeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH-mm-ss"
        return formatter
    }()

    /// Visible in note body: e.g. "29 марта 2026" (day, month word, year).
    private let headingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.setLocalizedDateFormatFromTemplate("dMMMM yyyy")
        return formatter
    }()

    private static let leadingDelimiterCharacterSet = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)

    private let categories: [VoiceCaptureCategory] = [
        VoiceCaptureCategory(
            id: "idea",
            displayTitle: "Ideas",
            folderName: "Ideas",
            noteTitlePrefix: "Idea",
            noteHeadingLabel: "Идея",
            tags: ["voice-capture", "idea"],
            prefixMarkers: ["это идея", "эта идея", "идея", "idea", "this is an idea"],
            detectionKeywords: ["идея", "idea"]
        ),
        VoiceCaptureCategory(
            id: "task",
            displayTitle: "Tasks",
            folderName: "Tasks",
            noteTitlePrefix: "Task",
            noteHeadingLabel: "Задача",
            tags: ["voice-capture", "task"],
            prefixMarkers: ["это задача", "эта задача", "задача", "todo", "to do", "task", "напоминание"],
            detectionKeywords: ["задача", "todo", "task", "напоминание"]
        ),
        VoiceCaptureCategory(
            id: "meeting",
            displayTitle: "Meetings",
            folderName: "Meetings",
            noteTitlePrefix: "Meeting",
            noteHeadingLabel: "Встреча",
            tags: ["voice-capture", "meeting"],
            prefixMarkers: ["это встреча", "эта встреча", "встреча", "созвон", "митинг", "meeting"],
            detectionKeywords: ["встреча", "созвон", "митинг", "meeting"]
        ),
        VoiceCaptureCategory(
            id: "journal",
            displayTitle: "Journal",
            folderName: "Journal",
            noteTitlePrefix: "Journal Entry",
            noteHeadingLabel: "Дневник",
            tags: ["voice-capture", "journal"],
            prefixMarkers: ["это дневник", "эта запись", "дневник", "journal", "рефлексия"],
            detectionKeywords: ["дневник", "journal", "рефлексия"]
        ),
        VoiceCaptureCategory(
            id: "note",
            displayTitle: "Notes",
            folderName: "Notes",
            noteTitlePrefix: "Note",
            noteHeadingLabel: "Заметка",
            tags: ["voice-capture", "note"],
            prefixMarkers: ["это заметка", "эта заметка", "заметка", "мысль", "note", "thought"],
            detectionKeywords: ["заметка", "мысль", "note", "thought"]
        )
    ]

    private let inboxCategory = VoiceCaptureCategory(
        id: "inbox",
        displayTitle: "Inbox",
        folderName: "Inbox",
        noteTitlePrefix: "Inbox Capture",
        noteHeadingLabel: "Запись",
        tags: ["voice-capture", "inbox"],
        prefixMarkers: [],
        detectionKeywords: []
    )
}

private struct TranscriptClassification {
    let category: VoiceCaptureCategory
    let cleanedText: String
}

private struct VoiceCaptureCategory {
    let id: String
    let displayTitle: String
    let folderName: String
    let noteTitlePrefix: String
    let noteHeadingLabel: String
    let tags: [String]
    let prefixMarkers: [String]
    let detectionKeywords: [String]
}
