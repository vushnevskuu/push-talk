import AppKit
import Carbon.HIToolbox
import Foundation

enum ShortcutKind: String {
    case fieldInsert
    case obsidianCapture

    var displayTitle: String {
        switch self {
        case .fieldInsert:
            return "Insert Dictation"
        case .obsidianCapture:
            return "Obsidian Capture"
        }
    }

    var defaultsKey: String {
        switch self {
        case .fieldInsert:
            return "voiceInsert.keyboardShortcut"
        case .obsidianCapture:
            return "voiceInsert.obsidianKeyboardShortcut"
        }
    }

    var defaultShortcut: KeyboardShortcut {
        switch self {
        case .fieldInsert:
            return .default
        case .obsidianCapture:
            return .obsidianDefault
        }
    }
}

struct KeyboardShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifiersRawValue: UInt

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiersRawValue = modifiers.intersection(Self.supportedModifiers).rawValue
    }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRawValue).intersection(Self.supportedModifiers)
    }

    var displayString: String {
        let modifierPart = Self.displayString(for: modifiers)
        let keyPart = Self.displayString(for: keyCode)
        return modifierPart + keyPart
    }

    static let supportedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    static let `default` = KeyboardShortcut(
        keyCode: UInt16(kVK_Space),
        modifiers: [.control, .option]
    )
    static let obsidianDefault = KeyboardShortcut(
        keyCode: UInt16(kVK_Space),
        modifiers: [.control, .option, .shift]
    )

    static func capture(from event: NSEvent) -> KeyboardShortcut? {
        let keyCode = event.keyCode

        guard !modifierOnlyKeyCodes.contains(keyCode) else {
            return nil
        }

        return KeyboardShortcut(
            keyCode: keyCode,
            modifiers: event.modifierFlags.intersection(supportedModifiers)
        )
    }

    func matchesKeyDown(event: NSEvent) -> Bool {
        event.type == .keyDown &&
        event.keyCode == keyCode &&
        event.modifierFlags.intersection(Self.supportedModifiers) == modifiers
    }

    func matchesKeyUp(event: NSEvent) -> Bool {
        event.type == .keyUp && event.keyCode == keyCode
    }

    private static let modifierOnlyKeyCodes: Set<UInt16> = [
        UInt16(kVK_Command),
        UInt16(kVK_RightCommand),
        UInt16(kVK_Control),
        UInt16(kVK_RightControl),
        UInt16(kVK_Option),
        UInt16(kVK_RightOption),
        UInt16(kVK_Shift),
        UInt16(kVK_RightShift),
        UInt16(kVK_CapsLock),
        63
    ]

    private static func displayString(for modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""

        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }

        return result
    }

    private static func displayString(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space:
            return "Space"
        case kVK_Return:
            return "Return"
        case kVK_Tab:
            return "Tab"
        case kVK_Delete:
            return "Delete"
        case kVK_Escape:
            return "Escape"
        case kVK_ForwardDelete:
            return "Forward Delete"
        case kVK_Home:
            return "Home"
        case kVK_End:
            return "End"
        case kVK_PageUp:
            return "Page Up"
        case kVK_PageDown:
            return "Page Down"
        case kVK_LeftArrow:
            return "Left Arrow"
        case kVK_RightArrow:
            return "Right Arrow"
        case kVK_UpArrow:
            return "Up Arrow"
        case kVK_DownArrow:
            return "Down Arrow"
        case kVK_F1...kVK_F20:
            return "F\(Int(keyCode) - kVK_F1 + 1)"
        default:
            return keyNameMap[keyCode] ?? "Key \(keyCode)"
        }
    }

    private static let keyNameMap: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A",
        UInt16(kVK_ANSI_B): "B",
        UInt16(kVK_ANSI_C): "C",
        UInt16(kVK_ANSI_D): "D",
        UInt16(kVK_ANSI_E): "E",
        UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G",
        UInt16(kVK_ANSI_H): "H",
        UInt16(kVK_ANSI_I): "I",
        UInt16(kVK_ANSI_J): "J",
        UInt16(kVK_ANSI_K): "K",
        UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M",
        UInt16(kVK_ANSI_N): "N",
        UInt16(kVK_ANSI_O): "O",
        UInt16(kVK_ANSI_P): "P",
        UInt16(kVK_ANSI_Q): "Q",
        UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S",
        UInt16(kVK_ANSI_T): "T",
        UInt16(kVK_ANSI_U): "U",
        UInt16(kVK_ANSI_V): "V",
        UInt16(kVK_ANSI_W): "W",
        UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y",
        UInt16(kVK_ANSI_Z): "Z",
        UInt16(kVK_ANSI_0): "0",
        UInt16(kVK_ANSI_1): "1",
        UInt16(kVK_ANSI_2): "2",
        UInt16(kVK_ANSI_3): "3",
        UInt16(kVK_ANSI_4): "4",
        UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6",
        UInt16(kVK_ANSI_7): "7",
        UInt16(kVK_ANSI_8): "8",
        UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_ANSI_Minus): "-",
        UInt16(kVK_ANSI_Equal): "=",
        UInt16(kVK_ANSI_LeftBracket): "[",
        UInt16(kVK_ANSI_RightBracket): "]",
        UInt16(kVK_ANSI_Semicolon): ";",
        UInt16(kVK_ANSI_Quote): "'",
        UInt16(kVK_ANSI_Comma): ",",
        UInt16(kVK_ANSI_Period): ".",
        UInt16(kVK_ANSI_Slash): "/",
        UInt16(kVK_ANSI_Backslash): "\\"
    ]
}

enum KeyboardShortcutStore {
    static func load(_ kind: ShortcutKind = .fieldInsert) -> KeyboardShortcut {
        guard let data = UserDefaults.standard.data(forKey: kind.defaultsKey),
              let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) else {
            return kind.defaultShortcut
        }

        return shortcut
    }

    static func save(_ shortcut: KeyboardShortcut, kind: ShortcutKind = .fieldInsert) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        UserDefaults.standard.set(data, forKey: kind.defaultsKey)
    }
}
