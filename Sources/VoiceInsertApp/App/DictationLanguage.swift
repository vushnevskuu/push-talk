import Foundation

enum DictationLanguage: String, CaseIterable, Sendable {
    case russian
    case english

    /// Подпись в переключателе (русский интерфейс + понятный English).
    var title: String {
        switch self {
        case .russian:
            return "Русский"
        case .english:
            return "English"
        }
    }

    /// Locale passed to `SFSpeechRecognizer`.
    var speechLocale: Locale {
        switch self {
        case .russian:
            return Locale(identifier: "ru-RU")
        case .english:
            return Locale(identifier: "en-US")
        }
    }
}
