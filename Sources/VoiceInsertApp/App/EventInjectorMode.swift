import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

enum EventInjectorMode {
    private enum InsertionMode {
        case typing
        case paste
    }

    private struct Options {
        var bundleIdentifier: String?
        var clickPoint: CGPoint?
        var insertionMode: InsertionMode = .typing
    }

    private enum InjectorError: Error {
        case missingText
        case malformedArguments
        case missingEventSource
        case missingMouseEvent
        case missingKeyboardEvent
    }

    static func runIfRequested(arguments: [String]) -> Bool {
        guard arguments.dropFirst().contains("--event-injector") else {
            return false
        }

        do {
            let options = try parseOptions(arguments: Array(arguments.dropFirst()))
            let textData = FileHandle.standardInput.readDataToEndOfFile()
            guard let text = String(data: textData, encoding: .utf8)?
                .trimmingCharacters(in: .newlines),
                  !text.isEmpty else {
                throw InjectorError.missingText
            }

            var targetPID: pid_t?
            if let bundleIdentifier = options.bundleIdentifier {
                targetPID = activateApplication(bundleIdentifier: bundleIdentifier)
                // #region agent log
                let fm = NSWorkspace.shared.frontmostApplication
                AgentDebugLog.append(
                    hypothesisId: "H1",
                    location: "EventInjectorMode.swift:after_activate",
                    message: "injector_activate_done",
                    data: [
                        "bundle": bundleIdentifier,
                        "targetPID": targetPID.map(String.init) ?? "nil",
                        "frontmostPID": fm.map { String($0.processIdentifier) } ?? "nil",
                        "frontmostBundle": fm?.bundleIdentifier ?? "nil"
                    ]
                )
                // #endregion
            }

            if let clickPoint = options.clickPoint {
                try click(at: clickPoint)
                RunLoop.current.run(until: Date().addingTimeInterval(0.08))
            }

            switch options.insertionMode {
            case .typing:
                try type(text, targetPID: targetPID)
            case .paste:
                try paste(text, targetPID: targetPID)
            }
        } catch {
            fputs("\(error)\n", stderr)
            exit(1)
        }

        return true
    }

    private static func parseOptions(arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--event-injector":
                break
            case "--paste":
                options.insertionMode = .paste
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

        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let usesDirectHIDTyping = true
        // #region agent log
        AgentDebugLog.append(
            hypothesisId: "H1",
            location: "EventInjectorMode.swift:type_begin",
            message: "injector_typing",
            data: [
                "targetPID": targetPID.map(String.init) ?? "nil",
                "frontmostPID": frontmost.map(String.init) ?? "nil",
                "usePostToPid": (!usesDirectHIDTyping && targetPID != nil).description,
                "textChars": String(text.count)
            ]
        )
        // #endregion

        for chunk in chunked(text, maxCharacters: 24) {
            let utf16 = Array(chunk.utf16)

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                throw InjectorError.missingKeyboardEvent
            }

            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            // Unicode CGEvents posted directly to a PID are often ignored by Electron/WebView composers
            // (Codex/Cursor included). After activating and refocusing the target, HID injection is reliable.
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

        AgentDebugLog.append(
            hypothesisId: "H1",
            location: "EventInjectorMode.swift:paste_begin",
            message: "injector_paste",
            data: [
                "targetPID": targetPID.map(String.init) ?? "nil",
                "frontmostPID": NSWorkspace.shared.frontmostApplication.map { String($0.processIdentifier) } ?? "nil",
                "textChars": String(text.count)
            ]
        )

        commandDown.post(tap: .cghidEventTap)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)
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
