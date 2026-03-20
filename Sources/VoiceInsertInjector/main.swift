import AppKit
import ApplicationServices
import Foundation

struct InjectorOptions {
    var bundleIdentifier: String?
    var clickPoint: CGPoint?
}

enum InjectorError: Error {
    case missingText
    case missingEventSource
    case malformedArguments
    case missingMouseEvent
    case missingKeyboardEvent
}

@main
struct VoiceInsertInjector {
    static func main() {
        do {
            let options = try parseOptions(arguments: Array(CommandLine.arguments.dropFirst()))
            let text = FileHandle.standardInput.readDataToEndOfFile()
            guard let string = String(data: text, encoding: .utf8)?
                .trimmingCharacters(in: .newlines),
                  !string.isEmpty else {
                throw InjectorError.missingText
            }

            if let bundleIdentifier = options.bundleIdentifier {
                activateApplication(bundleIdentifier: bundleIdentifier)
            }

            if let clickPoint = options.clickPoint {
                try click(at: clickPoint)
                RunLoop.current.run(until: Date().addingTimeInterval(0.08))
            }

            try type(string)
        } catch {
            fputs("\(error)\n", stderr)
            exit(1)
        }
    }

    private static func parseOptions(arguments: [String]) throws -> InjectorOptions {
        var options = InjectorOptions()
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--bundle-id":
                index += 1
                guard index < arguments.count else { throw InjectorError.malformedArguments }
                options.bundleIdentifier = arguments[index]
            case "--click-x":
                index += 1
                guard index < arguments.count,
                      let x = Double(arguments[index]) else {
                    throw InjectorError.malformedArguments
                }
                index += 1
                guard index < arguments.count,
                      arguments[index] == "--click-y" else {
                    throw InjectorError.malformedArguments
                }
                index += 1
                guard index < arguments.count,
                      let y = Double(arguments[index]) else {
                    throw InjectorError.malformedArguments
                }
                options.clickPoint = CGPoint(x: x, y: y)
            default:
                throw InjectorError.malformedArguments
            }

            index += 1
        }

        return options
    }

    private static func activateApplication(bundleIdentifier: String) {
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else {
            return
        }

        _ = application.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier {
                break
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    }

    private static func click(at point: CGPoint) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let move = CGEvent(
                mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: point,
                mouseButton: .left
              ),
              let down = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: point,
                mouseButton: .left
              ),
              let up = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: point,
                mouseButton: .left
              ) else {
            throw InjectorError.missingMouseEvent
        }

        move.post(tap: .cghidEventTap)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func type(_ text: String) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw InjectorError.missingEventSource
        }

        for chunk in chunked(text, maxCharacters: 24) {
            let utf16 = Array(chunk.utf16)

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                throw InjectorError.missingKeyboardEvent
            }

            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private static func chunked(_ text: String, maxCharacters: Int) -> [String] {
        guard text.count > maxCharacters else { return [text] }

        var chunks: [String] = []
        var current = text.startIndex

        while current < text.endIndex {
            let next = text.index(current, offsetBy: maxCharacters, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[current..<next]))
            current = next
        }

        return chunks
    }
}
