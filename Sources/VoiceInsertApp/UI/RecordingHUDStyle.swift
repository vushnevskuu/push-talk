import AppKit
import Foundation

enum RecordingHUDStyle: String, CaseIterable {
    case glassBar
    case compactOrb
    case bareWaves

    var title: String {
        switch self {
        case .glassBar:
            return "Current"
        case .compactOrb:
            return "Round"
        case .bareWaves:
            return "Bare"
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
        }
    }
}
