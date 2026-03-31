import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

struct InjectorOptions {
    var bundleIdentifier: String?
    var clickPoint: CGPoint?
    var usesPaste = false
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

            var targetPID: pid_t?
            if let bundleIdentifier = options.bundleIdentifier {
                targetPID = activateApplication(bundleIdentifier: bundleIdentifier)
            }

            waitForMouseButtonsToRelease()
            waitForStandardModifiersToRelease()

            if let clickPoint = options.clickPoint {
                try click(at: clickPoint)
                RunLoop.current.run(until: Date().addingTimeInterval(0.08))
            }

            if options.usesPaste {
                try paste(string, targetPID: targetPID)
            } else {
                try type(string, targetPID: targetPID)
            }
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
            case "--paste":
                options.usesPaste = true
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

    private static func activateApplication(bundleIdentifier: String) -> pid_t? {
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else {
            return nil
        }

        let pid = application.processIdentifier
        _ = application.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                break
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        return pid
    }

    private static func waitForMouseButtonsToRelease() {
        let deadline = Date().addingTimeInterval(0.35)
        while Date() < deadline {
            if !CGEventSource.buttonState(.combinedSessionState, button: .left) {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
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

    private static func type(_ text: String, targetPID: pid_t?) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw InjectorError.missingEventSource
        }

        for chunk in chunked(text, maxCharacters: 24) {
            let utf16 = Array(chunk.utf16)

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                throw InjectorError.missingKeyboardEvent
            }

            keyDown.flags = []
            keyUp.flags = []
            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            // Keep helper behavior aligned with the in-app event injector: HID posting survives
            // Electron/WebView editors more reliably than posting Unicode events directly to a PID.
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private static func paste(_ text: String, targetPID: pid_t?) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard let source = CGEventSource(stateID: .hidSystemState),
              let commandDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Command),
                keyDown: true
              ),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
              ),
              let commandUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Command),
                keyDown: false
              ) else {
            throw InjectorError.missingKeyboardEvent
        }

        commandDown.flags = .maskCommand
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        commandUp.flags = []

        commandDown.post(tap: .cghidEventTap)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
    }

    private static func waitForStandardModifiersToRelease() {
        let relevantFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        let deadline = Date().addingTimeInterval(0.35)
        while Date() < deadline {
            let flags = CGEventSource.flagsState(.combinedSessionState).intersection(relevantFlags)
            if flags.isEmpty {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
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
