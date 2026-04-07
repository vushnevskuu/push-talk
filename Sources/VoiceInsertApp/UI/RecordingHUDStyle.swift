import AppKit
import Foundation

enum RecordingHUDStyle: String, CaseIterable {
    case glassBar
    case compactOrb
    case bareWaves
    case flameBar

    var title: String {
        switch self {
        case .glassBar:
            return "Current"
        case .compactOrb:
            return "Round"
        case .bareWaves:
            return "Bare"
        case .flameBar:
            return "Flame"
        }
    }

    var detail: String {
        switch self {
        case .glassBar:
            return "The current glass pill."
        case .compactOrb:
            return "A small frosted glass orb."
        case .bareWaves:
            return "Only the waveform, no plate."
        case .flameBar:
            return "Glass bar with live fire tongues instead of orange bars."
        }
    }

    var panelSize: NSSize {
        switch self {
        case .glassBar:
            return NSSize(width: 248, height: 72)
        case .compactOrb:
            return NSSize(width: 72, height: 72)
        case .bareWaves:
            return NSSize(width: 204, height: 42)
        case .flameBar:
            return NSSize(width: 248, height: 76)
        }
    }
}
