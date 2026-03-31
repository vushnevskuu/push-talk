import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

enum TextInsertionError: LocalizedError {
    case eventCreationFailed
    case automationPermissionDenied
    case accessibilityPermissionDenied

    var errorDescription: String? {
        switch self {
        case .eventCreationFailed:
            return "Couldn't send the input event."
        case .automationPermissionDenied:
            return "Allow VoiceInsert to control System Events, then try dictation again."
        case .accessibilityPermissionDenied:
            return "Turn on Accessibility for VoiceInsert. Without it, text can't be inserted into apps like Cursor."
        }
    }
}

struct TextInsertionTarget {
    let focusedElement: AXUIElement?
    let frontmostAppPID: pid_t?
    let clickPoint: CGPoint?
    let frontmostBundleIdentifier: String?
}

private struct ElementTextSnapshot {
    let value: String?
    let selectedText: String?
}

private struct RecordedClick {
    let location: CGPoint
    let appPID: pid_t
    let bundleIdentifier: String?
    let timestamp: Date
}

private struct MouseDownSample: Sendable {
    let location: CGPoint
    let canUpdateExternalTarget: Bool
}

private struct HelperRunResult: Sendable {
    let terminationStatus: Int32
    let output: String
}

@MainActor
final class TextInsertionService {
    private var lastExternalAppPID: pid_t?
    private var workspaceObserver: NSObjectProtocol?
    private var globalMouseDownMonitor: Any?
    private var localMouseDownMonitor: Any?
    private var lastRecordedClick: RecordedClick?

    init() {
        noteActiveApplication(NSWorkspace.shared.frontmostApplication)
        installMouseTracking()

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [weak self] in
                self?.noteActiveApplication(app)
            }
        }
    }

    func captureTarget(includeFocusedElement: Bool = true) -> TextInsertionTarget {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let frontmostPID = frontmostApplication?.processIdentifier
        let effectivePID = resolvedTargetPID(frontmostPID: frontmostPID)
        let effectiveApplication: NSRunningApplication?
        if let effectivePID, effectivePID == frontmostPID {
            effectiveApplication = frontmostApplication
        } else if let effectivePID {
            effectiveApplication = NSRunningApplication(processIdentifier: effectivePID)
        } else {
            effectiveApplication = frontmostApplication
        }
        let bundleIdentifier = effectiveApplication?.bundleIdentifier
        let focusedElement = includeFocusedElement && AXIsProcessTrusted()
            ? focusedUIElement(for: effectivePID) ?? (frontmostPID == effectivePID ? focusedUIElement() : nil)
            : nil
        // У OpenAI Codex недавний клик по центру окна часто бьёт в сайдбар; геометрия композера стабильнее.
        let clickPoint: CGPoint?
        if bundleIdentifier == "com.openai.codex" {
            clickPoint = inferredClickPoint(for: effectivePID, bundleIdentifier: bundleIdentifier)
                ?? recentClickPoint(for: effectivePID)
        } else {
            clickPoint = recentClickPoint(for: effectivePID)
                ?? inferredClickPoint(for: effectivePID, bundleIdentifier: bundleIdentifier)
        }

        return TextInsertionTarget(
            focusedElement: focusedElement,
            frontmostAppPID: effectivePID,
            clickPoint: clickPoint,
            frontmostBundleIdentifier: bundleIdentifier
        )
    }

    /// Snapshot for the start of hold-to-dictate: PID/bundle + last mouse click only.
    /// Skips AX and `CGWindowListCopyWindowInfo` (used for Codex/Cursor composer inference) so the main thread
    /// doesn’t stall before `SpeechRecognitionService.startSession()`.
    func captureTargetForHoldStart() -> TextInsertionTarget {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let frontmostPID = frontmostApplication?.processIdentifier
        let effectivePID = resolvedTargetPID(frontmostPID: frontmostPID)
        let effectiveApplication: NSRunningApplication?
        if let effectivePID, effectivePID == frontmostPID {
            effectiveApplication = frontmostApplication
        } else if let effectivePID {
            effectiveApplication = NSRunningApplication(processIdentifier: effectivePID)
        } else {
            effectiveApplication = frontmostApplication
        }
        let bundleIdentifier = effectiveApplication?.bundleIdentifier
        let clickPoint = recentClickPoint(for: effectivePID)

        return TextInsertionTarget(
            focusedElement: nil,
            frontmostAppPID: effectivePID,
            clickPoint: clickPoint,
            frontmostBundleIdentifier: bundleIdentifier
        )
    }

    /// After dictation the frontmost app may still be VoiceInsert; refresh AX/cursor state while keeping useful stale fields (e.g. click fallbacks).
    private func mergeWithFreshCapture(stale: TextInsertionTarget?) -> TextInsertionTarget {
        let fresh = captureTarget(includeFocusedElement: true)
        guard let stale else { return fresh }

        // When HUD/settings focus VoiceInsert, `resolvedTargetPID` can fall back to nil and `captureTarget`
        // may report our bundle — overwriting `stale` from key-down would send paste/typing to the wrong app.
        if isInsertionTargetSelfApp(fresh) {
            return TextInsertionTarget(
                focusedElement: stale.focusedElement ?? fresh.focusedElement,
                frontmostAppPID: stale.frontmostAppPID,
                clickPoint: mergedClickPointForInsert(stale: stale, fresh: fresh),
                frontmostBundleIdentifier: stale.frontmostBundleIdentifier
            )
        }

        // `insert` already called `reactivateTargetAppIfNeeded` before merge; a fresh capture can still report
        // another app momentarily (activation lag). Keep the hold bundle/PID for Cursor so we don't paste into the wrong app.
        if let staleBid = stale.frontmostBundleIdentifier,
           staleBid.hasPrefix("com.todesktop."),
           let freshBid = fresh.frontmostBundleIdentifier,
           freshBid != staleBid,
           !isInsertionTargetSelfApp(fresh) {
            return TextInsertionTarget(
                focusedElement: stale.focusedElement ?? fresh.focusedElement,
                frontmostAppPID: stale.frontmostAppPID,
                clickPoint: mergedClickPointForInsert(stale: stale, fresh: fresh),
                frontmostBundleIdentifier: stale.frontmostBundleIdentifier
            )
        }

        return TextInsertionTarget(
            focusedElement: fresh.focusedElement ?? stale.focusedElement,
            frontmostAppPID: fresh.frontmostAppPID ?? stale.frontmostAppPID,
            clickPoint: mergedClickPointForInsert(stale: stale, fresh: fresh),
            frontmostBundleIdentifier: fresh.frontmostBundleIdentifier ?? stale.frontmostBundleIdentifier
        )
    }

    /// Cursor: prefer the hold-start click over `fresh`'s inferred bottom-window point so merge doesn't overwrite
    /// the user's real target with `codexComposerClickPoint`.
    private func mergedClickPointForInsert(stale: TextInsertionTarget, fresh: TextInsertionTarget) -> CGPoint? {
        if stale.frontmostBundleIdentifier?.hasPrefix("com.todesktop.") == true {
            return stale.clickPoint ?? recentClickPoint(for: stale.frontmostAppPID) ?? fresh.clickPoint
        }
        return fresh.clickPoint ?? stale.clickPoint
    }

    private func isInsertionTargetSelfApp(_ target: TextInsertionTarget) -> Bool {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        if let pid = target.frontmostAppPID, pid == selfPID {
            return true
        }
        if let bid = target.frontmostBundleIdentifier, bid == Bundle.main.bundleIdentifier {
            return true
        }
        return false
    }

    func insert(text: String, target: TextInsertionTarget?) async throws {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        guard AXIsProcessTrusted() else {
            beginDebugTrace(text: trimmedText, target: target)
            appendDebugTrace("insert_blocked=accessibility_denied")
            throw TextInsertionError.accessibilityPermissionDenied
        }

        defer {
            Self.persistInsertionTraceForSupport()
        }

        _ = reactivateTargetAppIfNeeded(target)
        try await Task.sleep(for: .milliseconds(120))
        let mergedTarget = mergeWithFreshCapture(stale: target)
        beginDebugTrace(text: trimmedText, target: mergedTarget)

        let focusedElement = mergedTarget.focusedElement
            ?? focusedUIElement(for: mergedTarget.frontmostAppPID)
            ?? captureTarget().focusedElement

        if let focusedElement {
            let rawValue = copyStringAttribute(kAXValueAttribute, from: focusedElement)?
                .replacingOccurrences(of: "\n", with: " ") ?? "<nil>"
            appendDebugTrace("pre_value=\(String(rawValue.prefix(180)))")

            let selectedText = copyStringAttribute(kAXSelectedTextAttribute, from: focusedElement)?
                .replacingOccurrences(of: "\n", with: " ") ?? "<nil>"
            appendDebugTrace("pre_selected_text=\(String(selectedText.prefix(180)))")

            if let selectedRange = copySelectedRange(from: focusedElement) {
                appendDebugTrace("pre_selected_range=\(selectedRange.location),\(selectedRange.length)")
            }
        }

        if let focusedElement,
           shouldSkipDirectAccessibilityInsert(for: mergedTarget, focusedElement: focusedElement) {
            appendDebugTrace("direct_ax_insert=skipped_placeholder_backed")
        } else if focusedElement != nil,
                  shouldSkipDirectAccessibilityInsertForPasteOnlyBundles(mergedTarget) {
            appendDebugTrace("direct_ax_insert=skipped_paste_only_bundle")
        } else if let focusedElement,
                  try insertDirectly(
                    text: trimmedText,
                    into: focusedElement,
                    bundleIdentifier: mergedTarget.frontmostBundleIdentifier
                  ) {
            appendDebugTrace("direct_ax_insert=success")
            return
        } else {
            appendDebugTrace("direct_ax_insert=failed")
        }

        if prefersTypingFallback(for: mergedTarget, focusedElement: focusedElement) {
            appendDebugTrace("bundle_specific_path=codex_menu_paste")

            if try insertViaMenuPaste(trimmedText, target: mergedTarget, focusedElement: focusedElement) {
                appendDebugTrace("menu_paste_path=success")
                return
            }

            appendDebugTrace("menu_paste_path=failed")

            if mergedTarget.frontmostBundleIdentifier == "com.openai.codex" {
                if try insertViaPasteboard(trimmedText, target: mergedTarget, focusedElement: focusedElement) {
                    appendDebugTrace("pasteboard_path=success_codex_after_menu")
                    return
                }
                appendDebugTrace("pasteboard_path=failed_codex_after_menu")
            }

            if shouldPreferHelperTypingFallback(beforePasteFor: mergedTarget, focusedElement: focusedElement) {
                if try await insertViaHelperTyping(
                    trimmedText,
                    target: mergedTarget,
                    axFocusedElement: focusedElement
                ) {
                    appendDebugTrace("helper_typing_path=success")
                    return
                }

                appendDebugTrace("helper_typing_path=failed")

                if try await insertViaHelperPaste(
                    trimmedText,
                    target: mergedTarget,
                    axFocusedElement: focusedElement
                ) {
                    appendDebugTrace("helper_paste_path=success")
                    return
                }

                appendDebugTrace("helper_paste_path=failed")
            } else {
                // Electron/WebView editors often ignore paste even after the composer is reactivated.
                // Fall back to a helper HID typer before asking for heavier Apple Events permissions.
                if try await insertViaHelperPaste(
                    trimmedText,
                    target: mergedTarget,
                    axFocusedElement: focusedElement
                ) {
                    appendDebugTrace("helper_paste_path=success")
                    return
                }

                appendDebugTrace("helper_paste_path=failed")

                if try await insertViaHelperTyping(
                    trimmedText,
                    target: mergedTarget,
                    axFocusedElement: focusedElement
                ) {
                    appendDebugTrace("helper_typing_path=success")
                    return
                }

                appendDebugTrace("helper_typing_path=failed")
            }
            if try insertViaSystemEventsPaste(trimmedText, target: mergedTarget, focusedElement: focusedElement) {
                appendDebugTrace("system_events_paste_path=success")
                return
            }

            appendDebugTrace("system_events_paste_path=failed")
            try insertViaSystemEventsTyping(trimmedText, target: mergedTarget, focusedElement: focusedElement)
            appendDebugTrace("system_events_typing_path=sent")
            return
        }

        if try insertViaPasteboard(trimmedText, target: mergedTarget, focusedElement: focusedElement) {
            appendDebugTrace("pasteboard_path=success")
            return
        }

        appendDebugTrace("pasteboard_path=failed")

        if canAttemptClickBasedHelperFallback(target: mergedTarget, focusedElement: focusedElement) {
            if try await insertViaHelperPaste(
                trimmedText,
                target: mergedTarget,
                axFocusedElement: focusedElement
            ) {
                appendDebugTrace("helper_paste_path=success")
                return
            }

            appendDebugTrace("helper_paste_path=failed")

            if try await insertViaHelperTyping(
                trimmedText,
                target: mergedTarget,
                axFocusedElement: focusedElement
            ) {
                appendDebugTrace("helper_typing_path=success")
                return
            }

            appendDebugTrace("helper_typing_path=failed")
        }

        try insertViaTyping(trimmedText, target: mergedTarget, chunkSize: 8, axFocusedElement: focusedElement)
        appendDebugTrace("typing_path=sent")
    }

    private nonisolated static func persistInsertionTraceForSupport() {
        let text = UserDefaults.standard.string(forKey: DefaultsKey.lastInsertionDebug) ?? ""
        guard !text.isEmpty else { return }

        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let dir = base.appendingPathComponent("VoiceInsert", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("insert-trace.txt", isDirectory: false)
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func focusedUIElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )

        guard result == .success, let value else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func focusedUIElement(for pid: pid_t?) -> AXUIElement? {
        guard let pid else { return nil }

        let application = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )

        guard result == .success, let value else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func insertDirectly(
        text: String,
        into element: AXUIElement,
        bundleIdentifier: String?
    ) throws -> Bool {
        restoreFocusIfPossible(on: element)

        guard let currentValue = editableValueForInsertion(
            from: element,
            bundleIdentifier: bundleIdentifier
        ) else {
            return replaceSelectedText(text: text, in: element)
        }

        let nsString = currentValue as NSString
        let selectedRange = copySelectedRange(from: element) ?? CFRange(location: nsString.length, length: 0)
        let boundedRange = sanitize(range: selectedRange, maxLength: nsString.length)
        let updatedText = nsString.replacingCharacters(in: boundedRange, with: text)

        let setValueResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            updatedText as CFTypeRef
        )

        guard setValueResult == .success else {
            return replaceSelectedText(text: text, in: element)
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.04))

        guard copyStringAttribute(kAXValueAttribute, from: element) == updatedText else {
            return replaceSelectedText(text: text, in: element)
        }

        var newSelection = CFRange(
            location: boundedRange.location + (text as NSString).length,
            length: 0
        )

        if let selectionValue = AXValueCreate(.cfRange, &newSelection) {
            _ = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                selectionValue
            )
        }

        return true
    }

    private func editableValueForInsertion(
        from element: AXUIElement,
        bundleIdentifier: String?
    ) -> String? {
        guard let rawValue = copyStringAttribute(kAXValueAttribute, from: element) else {
            return nil
        }

        let trimmedRawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRawValue.isEmpty else {
            return ""
        }

        if let bid = bundleIdentifier, (bid == "com.openai.codex" || bid.hasPrefix("com.todesktop.")),
           Self.codexPromptPrefixes.contains(where: { trimmedRawValue.hasPrefix($0) }) {
            return ""
        }

        for placeholder in placeholderTexts(for: element) {
            if trimmedRawValue == placeholder {
                return ""
            }
        }

        return rawValue
    }

    /// Web/HTML composers (e.g. ChatGPT in Atlas) may apply AX `kAXValue` and also treat the change as user input, duplicating text. Paste-only avoids that.
    private func shouldSkipDirectAccessibilityInsertForPasteOnlyBundles(_ target: TextInsertionTarget?) -> Bool {
        guard let id = target?.frontmostBundleIdentifier else { return false }
        return Self.isPasteOnlyInsertionBundle(id)
    }

    /// After Cmd+V the field can update in the web view before AX `kAXValue` reflects it, so verification returns false and the menu “Paste” fallback runs again → duplicated text.
    private func shouldSkipMenuPasteRetryAfterCmdV(for target: TextInsertionTarget?) -> Bool {
        guard let id = target?.frontmostBundleIdentifier else { return false }
        return Self.isPasteOnlyInsertionBundle(id)
    }

    private static func isPasteOnlyInsertionBundle(_ id: String) -> Bool {
        pasteOnlyInsertionBundleIdentifiers.contains(id) || id.hasPrefix("com.openai.atlas.")
    }

    private func shouldSkipDirectAccessibilityInsert(
        for target: TextInsertionTarget?,
        focusedElement: AXUIElement
    ) -> Bool {
        guard Self.isCursorLikeApp(target) else {
            return false
        }

        guard let rawValue = copyStringAttribute(kAXValueAttribute, from: focusedElement)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return false
        }

        for placeholder in placeholderTexts(for: focusedElement) {
            if rawValue == placeholder || rawValue.hasSuffix(placeholder) || placeholder.hasSuffix(rawValue) {
                return true
            }
        }

        return false
    }

    private func placeholderTexts(for element: AXUIElement) -> [String] {
        Self.placeholderAttributeNames.compactMap { attribute in
            guard let value = copyStringAttribute(attribute, from: element)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return nil
            }

            return value
        }
    }

    /// Web/Electron composers (LinkedIn, etc.) often react to `NSPasteboard.general` updates; restoring a snapshot
    /// can re-publish an image, file URL, or **plain text** the user had copied earlier—so the page inserts it again
    /// even when our Cmd+V already pasted the transcript (AX verification often lags, so we used to `restore` on “failure”).
    private static func shouldClearPasteboardInsteadOfRestoring(into target: TextInsertionTarget?) -> Bool {
        guard let id = target?.frontmostBundleIdentifier else { return false }
        if id.hasPrefix("com.todesktop.") { return true }
        if id == "com.openai.codex" { return true }
        return unverifiablePasteBundleIdentifiers.contains(id)
    }

    private func restorePasteboardAfterInsertAttempt(snapshot: PasteboardSnapshot, target: TextInsertionTarget?, success: Bool) {
        if success {
            if Self.shouldClearPasteboardInsteadOfRestoring(into: target) {
                NSPasteboard.general.clearContents()
            } else {
                snapshot.restore(omitImageTypes: true)
            }
        } else {
            if Self.shouldClearPasteboardInsteadOfRestoring(into: target) {
                NSPasteboard.general.clearContents()
            } else {
                snapshot.restore(omitImageTypes: false)
            }
        }
    }

    private func insertViaPasteboard(
        _ text: String,
        target: TextInsertionTarget?,
        focusedElement: AXUIElement?
    ) throws -> Bool {
        let snapshot = PasteboardSnapshot.capture()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let baseline = snapshotTextState(of: focusedElement)

        do {
            let targetPID = reactivateTargetAppIfNeeded(target)
            waitForMouseButtonsToRelease()
            try restoreInteractionTarget(target, focusedElement: focusedElement)
            waitForShortcutModifiersToRelease()

            try cursorSelectAllIfNeeded(target: target, focusedElement: focusedElement, targetPID: targetPID)

            try simulatePasteShortcut(targetPID: targetPID)
            let verification = waitForTextInsertion(text, in: focusedElement, baseline: baseline)

            if verification == true {
                restorePasteboardAfterInsertAttempt(snapshot: snapshot, target: target, success: true)
                return true
            }

            if verification == false {
                if shouldSkipMenuPasteRetryAfterCmdV(for: target) {
                    appendDebugTrace("pasteboard_menu_retry=skipped_ax_lag_single_shot")
                    restorePasteboardAfterInsertAttempt(snapshot: snapshot, target: target, success: true)
                    return true
                }
                if performPasteMenuAction(on: targetPID) {
                    let menuVerification = waitForTextInsertion(text, in: focusedElement, baseline: baseline)
                    let ok = menuVerification ?? false
                    restorePasteboardAfterInsertAttempt(snapshot: snapshot, target: target, success: ok)
                    return ok
                }
            }

            if verification == nil {
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                if shouldAssumePasteSucceededWithoutVerification(for: target),
                   !canAttemptClickBasedHelperFallback(target: target, focusedElement: focusedElement) {
                    appendDebugTrace("pasteboard_verification=assumed_success_without_ax")
                    restorePasteboardAfterInsertAttempt(snapshot: snapshot, target: target, success: true)
                    return true
                }
                restorePasteboardAfterInsertAttempt(snapshot: snapshot, target: target, success: false)
                return false
            }

            restorePasteboardAfterInsertAttempt(snapshot: snapshot, target: target, success: false)
            return false
        } catch {
            restorePasteboardAfterInsertAttempt(snapshot: snapshot, target: target, success: false)
            throw error
        }
    }

    private func canAttemptClickBasedHelperFallback(
        target: TextInsertionTarget?,
        focusedElement: AXUIElement?
    ) -> Bool {
        focusedElement == nil && target?.clickPoint != nil
    }

    private func insertViaTyping(_ text: String, target: TextInsertionTarget?, chunkSize: Int, axFocusedElement: AXUIElement?) throws {
        let targetPID = reactivateTargetAppIfNeeded(target)
        waitForMouseButtonsToRelease()
        try restoreInteractionTarget(target, focusedElement: axFocusedElement ?? target?.focusedElement)
        waitForShortcutModifiersToRelease()

        try cursorSelectAllIfNeeded(target: target, focusedElement: axFocusedElement, targetPID: targetPID)

        try simulateTyping(text, targetPID: targetPID, chunkSize: chunkSize)
    }

    /// Cmd+A without a real AX text target often hits the wrong Electron control (sidebar, palette); skip when we only have click-based restore.
    private func cursorSelectAllIfNeeded(
        target: TextInsertionTarget?,
        focusedElement: AXUIElement?,
        targetPID: pid_t?
    ) throws {
        guard Self.isCursorLikeApp(target) else { return }
        guard focusedElement != nil else {
            appendDebugTrace("cursor_select_all=skipped_no_ax_focus")
            return
        }
        try simulateSelectAllShortcut(targetPID: targetPID)
    }

    private func insertViaHelperTyping(
        _ text: String,
        target: TextInsertionTarget?,
        axFocusedElement: AXUIElement?
    ) async throws -> Bool {
        try await runHelperInsertion(
            text,
            target: target,
            axFocusedElement: axFocusedElement,
            extraArguments: []
        )
    }

    private func insertViaHelperPaste(
        _ text: String,
        target: TextInsertionTarget?,
        axFocusedElement: AXUIElement?
    ) async throws -> Bool {
        let snapshot = PasteboardSnapshot.capture()
        do {
            let ok = try await runHelperInsertion(
                text,
                target: target,
                axFocusedElement: axFocusedElement,
                extraArguments: ["--paste"]
            )
            if ok {
                // Electron/WebView targets can consume the general pasteboard a moment after Cmd+V arrives.
                // Clearing/restoring it immediately after the helper exits can cancel an otherwise valid paste.
                try? await Task.sleep(for: .milliseconds(220))
            }
            restorePasteboardAfterInsertAttempt(snapshot: snapshot, target: target, success: ok)
            return ok
        } catch {
            restorePasteboardAfterInsertAttempt(snapshot: snapshot, target: target, success: false)
            throw error
        }
    }

    private func runHelperInsertion(
        _ text: String,
        target: TextInsertionTarget?,
        axFocusedElement: AXUIElement?,
        extraArguments: [String]
    ) async throws -> Bool {
        guard let helperURL = injectorExecutableURL() else {
            appendDebugTrace("helper_typing_error=missing_helper")
            return false
        }

        waitForShortcutModifiersToRelease()
        if Self.isCursorLikeApp(target) {
            let targetPID = reactivateTargetAppIfNeeded(target)
            waitForMouseButtonsToRelease()
            try restoreInteractionTarget(target, focusedElement: axFocusedElement ?? target?.focusedElement)
            try cursorSelectAllIfNeeded(target: target, focusedElement: axFocusedElement, targetPID: targetPID)
        }

        var arguments: [String] = ["--event-injector"]
        arguments.append(contentsOf: extraArguments)

        if let bundleIdentifier = target?.frontmostBundleIdentifier {
            arguments.append(contentsOf: ["--bundle-id", bundleIdentifier])
        }

        if let target,
           shouldReplaySyntheticClick(for: target),
           let clickPoint = trustedClickPoint(for: target) {
            arguments.append(contentsOf: [
                "--click-x",
                String(describing: clickPoint.x),
                "--click-y",
                String(describing: clickPoint.y)
            ])
        }

        do {
            let fm = NSWorkspace.shared.frontmostApplication
            AgentDebugLog.append(
                hypothesisId: "H4",
                location: "TextInsertionService.swift:runHelperInsertion",
                message: "before_runHelper",
                data: [
                    "frontmostPID": fm.map { String($0.processIdentifier) } ?? "nil",
                    "frontmostBundle": fm?.bundleIdentifier ?? "nil",
                    "targetPID": target?.frontmostAppPID.map(String.init) ?? "nil",
                    "targetBundle": target?.frontmostBundleIdentifier ?? "nil",
                    "mode": extraArguments.contains("--paste") ? "paste" : "typing"
                ]
            )
            let result = try await Self.runHelper(
                executableURL: helperURL,
                arguments: arguments,
                text: text
            )

            if !result.output.isEmpty {
                appendDebugTrace("helper_output=\(result.output.replacingOccurrences(of: "\n", with: "|"))")
            }

            return result.terminationStatus == 0
        } catch {
            appendDebugTrace("helper_typing_error=launch_failed")
            return false
        }
    }

    private func insertViaMenuPaste(
        _ text: String,
        target: TextInsertionTarget?,
        focusedElement: AXUIElement?
    ) throws -> Bool {
        let snapshot = PasteboardSnapshot.capture()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let baseline = snapshotTextState(of: focusedElement)

        let targetPID = reactivateTargetAppIfNeeded(target)
        waitForMouseButtonsToRelease()
        try restoreInteractionTarget(target, focusedElement: focusedElement)
        waitForShortcutModifiersToRelease()

        try cursorSelectAllIfNeeded(target: target, focusedElement: focusedElement, targetPID: targetPID)

        guard performPasteMenuAction(on: targetPID) else {
            restorePasteboardAfterInsertAttempt(snapshot: snapshot, target: target, success: false)
            return false
        }

        if let verification = waitForTextInsertion(text, in: focusedElement, baseline: baseline) {
            restorePasteboardAfterInsertAttempt(snapshot: snapshot, target: target, success: verification)
            return verification
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.35))

        if shouldTreatUnverifiedMenuPasteAsFailure(for: target, focusedElement: focusedElement) {
            appendDebugTrace("menu_paste_verification=unverified_retry_fallback")
            restorePasteboardAfterInsertAttempt(snapshot: snapshot, target: target, success: false)
            return false
        }

        restorePasteboardAfterInsertAttempt(snapshot: snapshot, target: target, success: true)
        return true
    }

    private func insertViaSystemEventsPaste(
        _ text: String,
        target: TextInsertionTarget?,
        focusedElement: AXUIElement?
    ) throws -> Bool {
        let snapshot = PasteboardSnapshot.capture()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        do {
            _ = reactivateTargetAppIfNeeded(target)
            waitForMouseButtonsToRelease()
            try restoreInteractionTarget(target, focusedElement: focusedElement)

            let success = try executeAppleScript("""
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """)

            if success {
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            }

            restorePasteboardAfterInsertAttempt(snapshot: snapshot, target: target, success: success)
            return success
        } catch {
            restorePasteboardAfterInsertAttempt(snapshot: snapshot, target: target, success: false)
            throw error
        }
    }

    private func insertViaSystemEventsTyping(
        _ text: String,
        target: TextInsertionTarget?,
        focusedElement: AXUIElement?
    ) throws {
        _ = reactivateTargetAppIfNeeded(target)
        waitForMouseButtonsToRelease()
        try restoreInteractionTarget(target, focusedElement: focusedElement)

        for line in text.components(separatedBy: .newlines) {
            let escapedLine = appleScriptEscaped(line)
            let success = try executeAppleScript("""
            tell application "System Events"
                keystroke "\(escapedLine)"
            end tell
            """)

            appendDebugTrace("system_events_typing_line_success=\(success)")

            if !success {
                throw TextInsertionError.eventCreationFailed
            }
        }
    }

    private func reactivateTargetAppIfNeeded(_ target: TextInsertionTarget?) -> pid_t? {
        guard let pid = target?.frontmostAppPID,
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }) else {
            return target?.frontmostAppPID
        }

        appendDebugTrace("frontmost_before_reactivate=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")")
        let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard currentPID != pid else {
            appendDebugTrace("frontmost_after_reactivate=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")")
            return pid
        }

        _ = app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                break
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.18))
        appendDebugTrace("frontmost_after_reactivate=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")")
        return pid
    }

    private func simulateSelectAllShortcut(targetPID: pid_t?) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let commandDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Command),
                keyDown: true
              ),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: false),
              let commandUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Command),
                keyDown: false
              ) else {
            throw TextInsertionError.eventCreationFailed
        }

        commandDown.flags = .maskCommand
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        commandUp.flags = []

        if let targetPID,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != targetPID {
            commandDown.postToPid(targetPID)
            keyDown.postToPid(targetPID)
            keyUp.postToPid(targetPID)
            commandUp.postToPid(targetPID)
        } else {
            commandDown.post(tap: .cghidEventTap)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            commandUp.post(tap: .cghidEventTap)
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
    }

    private func simulatePasteShortcut(targetPID: pid_t?) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let commandDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Command),
                keyDown: true
              ),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false),
              let commandUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Command),
                keyDown: false
              ) else {
            throw TextInsertionError.eventCreationFailed
        }

        commandDown.flags = .maskCommand
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        commandUp.flags = []

        if let targetPID,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != targetPID {
            commandDown.postToPid(targetPID)
            keyDown.postToPid(targetPID)
            keyUp.postToPid(targetPID)
            commandUp.postToPid(targetPID)
            return
        }

        commandDown.post(tap: .cghidEventTap)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)
    }

    private func simulateTyping(_ text: String, targetPID: pid_t?, chunkSize: Int) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw TextInsertionError.eventCreationFailed
        }

        let chunks = text.chunkedForEventInsertion(maxCharacters: max(chunkSize, 1))

        for chunk in chunks {
            let utf16 = Array(chunk.utf16)

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                throw TextInsertionError.eventCreationFailed
            }

            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)

            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            appendDebugTrace("typing_frontmost_pid=\(frontmostPID ?? 0)")
            appendDebugTrace("typing_target_pid=\(targetPID ?? 0)")

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)

            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func simulateClick(at point: CGPoint) throws {
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
            throw TextInsertionError.eventCreationFailed
        }

        move.post(tap: .cghidEventTap)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func copyStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func copySelectedRange(from element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )

        guard result == .success,
              let rangeValue = value,
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = rangeValue as! AXValue
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    private func sanitize(range: CFRange, maxLength: Int) -> NSRange {
        let start = min(max(range.location, 0), maxLength)
        let length = min(max(range.length, 0), maxLength - start)
        return NSRange(location: start, length: length)
    }

    private func replaceSelectedText(text: String, in element: AXUIElement) -> Bool {
        let baseline = snapshotTextState(of: element)
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        guard result == .success else {
            return false
        }

        return waitForTextInsertion(text, in: element, baseline: baseline) ?? false
    }

    private func restoreInteractionTarget(
        _ target: TextInsertionTarget?,
        focusedElement: AXUIElement?
    ) throws {
        if let focusedElement {
            restoreFocusIfPossible(on: focusedElement)
        } else if let target {
            if shouldReplaySyntheticClick(for: target), let click = trustedClickPoint(for: target) {
                appendDebugTrace("restore_target=click_at_point")
                try simulateClick(at: click)
            } else if target.frontmostBundleIdentifier == "com.openai.codex" {
                appendDebugTrace("restore_target=skip_click_codex")
            } else if target.frontmostBundleIdentifier?.hasPrefix("com.todesktop.") == true {
                appendDebugTrace("restore_target=skip_click_cursor")
            } else if Self.isCursorLikeApp(target) {
                appendDebugTrace("restore_target=skip_click_cursor_no_point")
            }
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }

    /// For Cursor (`com.todesktop.*`), prefer a recent real click when it looks like the editor area, but fall back
    /// to an inferred composer point when the remembered click is clearly in the left rail/sidebar.
    private func trustedClickPoint(for target: TextInsertionTarget) -> CGPoint? {
        guard let pid = target.frontmostAppPID else { return nil }

        if let bundleIdentifier = target.frontmostBundleIdentifier,
           bundleIdentifier.hasPrefix("com.todesktop.") {
            let recentPoint = recentClickPoint(for: pid) ?? target.clickPoint
            let inferredPoint = inferredClickPoint(for: pid, bundleIdentifier: bundleIdentifier)

            if let recentPoint,
               shouldPreferInferredComposerPoint(
                over: recentPoint,
                pid: pid,
                bundleIdentifier: bundleIdentifier
               ),
               let inferredPoint {
                appendDebugTrace("cursor_click_point=inferred_composer")
                return inferredPoint
            }

            return recentPoint ?? inferredPoint
        }

        return target.clickPoint
    }

    /// Cursor-like apps keep wide left rails; an old click there is a poor restore target after hold-to-talk.
    /// Prefer the inferred bottom composer point when the remembered click is clearly in the rail.
    private func shouldPreferInferredComposerPoint(
        over recentPoint: CGPoint,
        pid: pid_t,
        bundleIdentifier: String
    ) -> Bool {
        guard bundleIdentifier.hasPrefix("com.todesktop."),
              let bounds = frontmostWindowBounds(for: pid),
              bounds.width > 0 else {
            return false
        }

        let relativeX = (recentPoint.x - bounds.origin.x) / bounds.width
        return relativeX < 0.28
    }

    private func restoreFocusIfPossible(on element: AXUIElement) {
        _ = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
    }

    private func resolvedTargetPID(frontmostPID: pid_t?) -> pid_t? {
        let currentPID = ProcessInfo.processInfo.processIdentifier

        if let frontmostPID, frontmostPID != currentPID {
            return frontmostPID
        }

        return lastExternalAppPID
    }

    private func noteActiveApplication(_ application: NSRunningApplication?) {
        guard let application else { return }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard application.processIdentifier != currentPID else { return }

        lastExternalAppPID = application.processIdentifier
    }

    private func installMouseTracking() {
        globalMouseDownMonitor = Self.makeGlobalMouseMonitor(service: self)
        localMouseDownMonitor = Self.makeLocalMouseMonitor(service: self)
    }

    private func recordMouseDown(_ sample: MouseDownSample) {
        guard sample.canUpdateExternalTarget else { return }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != currentPID else {
            return
        }

        lastRecordedClick = RecordedClick(
            location: sample.location,
            appPID: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            timestamp: Date()
        )
    }

    nonisolated private static func mouseDownSample(
        from event: NSEvent,
        canUpdateExternalTarget: Bool
    ) -> MouseDownSample {
        MouseDownSample(
            location: event.cgEvent?.location ?? NSEvent.mouseLocation,
            canUpdateExternalTarget: canUpdateExternalTarget
        )
    }

    nonisolated private static func makeGlobalMouseMonitor(
        service: TextInsertionService
    ) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak service] event in
            let sample = mouseDownSample(from: event, canUpdateExternalTarget: true)
            Task { @MainActor [weak service] in
                service?.recordMouseDown(sample)
            }
        }
    }

    nonisolated private static func makeLocalMouseMonitor(
        service: TextInsertionService
    ) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak service] event in
            // Our floating hold-to-talk panel is non-activating, so a click on it can arrive while the real target
            // app is still frontmost. Keep the previous external click instead of replacing it with panel coordinates.
            let sample = mouseDownSample(from: event, canUpdateExternalTarget: false)
            Task { @MainActor [weak service] in
                service?.recordMouseDown(sample)
            }
            return event
        }
    }

    private func recentClickPoint(for pid: pid_t?) -> CGPoint? {
        guard let pid,
              let lastRecordedClick,
              lastRecordedClick.appPID == pid,
              Date().timeIntervalSince(lastRecordedClick.timestamp) <= Self.recordedClickTTL else {
            return nil
        }

        return lastRecordedClick.location
    }

    private func inferredClickPoint(for pid: pid_t?, bundleIdentifier: String?) -> CGPoint? {
        guard let pid, let bundleIdentifier else { return nil }

        if bundleIdentifier == "com.openai.codex" || bundleIdentifier.hasPrefix("com.todesktop.") {
            return codexComposerClickPoint(for: pid, bundleIdentifier: bundleIdentifier)
        }
        return nil
    }

    /// Вертикаль — нижняя зона окна (поле ввода). Горизонталь: у Codex левая навигация забирает фокус при клике в геометрический центр окна.
    private func codexComposerClickPoint(for pid: pid_t, bundleIdentifier: String) -> CGPoint? {
        guard let bounds = frontmostWindowBounds(for: pid) else { return nil }

        let isOpenAICodex = bundleIdentifier == "com.openai.codex"
        // У Codex левый rail широкий; поле ввода правее центра окна.
        let bottomInset: CGFloat = isOpenAICodex ? 200 : 92
        // `CGWindowList` bounds already line up with the click coordinates accepted by our CGEvent injector.
        // Flipping Y here sends the fallback click far above the composer in Codex/Cursor.
        let clickY = bounds.origin.y + bounds.height - bottomInset

        let xRatio: CGFloat = isOpenAICodex ? 0.82 : 0.5
        let clickX = bounds.origin.x + bounds.width * xRatio

        return CGPoint(x: clickX, y: clickY)
    }

    private func frontmostWindowBounds(for pid: pid_t) -> CGRect? {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        var best: CGRect?
        var bestArea: CGFloat = 0

        for windowInfo in windowInfoList {
            let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32
            let layer = windowInfo[kCGWindowLayer as String] as? Int ?? 0

            guard ownerPID == pid, layer == 0 else { continue }
            guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else {
                continue
            }

            let area = bounds.width * bounds.height
            guard area >= 14_000 else { continue }

            if area > bestArea {
                bestArea = area
                best = bounds
            }
        }

        return best
    }

    private func prefersTypingFallback(
        for target: TextInsertionTarget?,
        focusedElement: AXUIElement?
    ) -> Bool {
        guard focusedElement == nil else { return false }
        guard let bundleIdentifier = target?.frontmostBundleIdentifier else { return false }

        return bundleIdentifier == "com.openai.codex" || bundleIdentifier.hasPrefix("com.todesktop.")
    }

    private func shouldReplaySyntheticClick(for target: TextInsertionTarget?) -> Bool {
        guard let bundleIdentifier = target?.frontmostBundleIdentifier else {
            return target?.clickPoint != nil
        }

        if bundleIdentifier == "com.openai.codex" {
            return false
        }

        if bundleIdentifier.hasPrefix("com.todesktop.") {
            return false
        }

        return target?.clickPoint != nil
    }

    private func shouldPreferHelperTypingFallback(
        beforePasteFor target: TextInsertionTarget?,
        focusedElement: AXUIElement?
    ) -> Bool {
        guard focusedElement == nil else { return false }
        guard let bundleIdentifier = target?.frontmostBundleIdentifier else { return false }
        return bundleIdentifier.hasPrefix("com.todesktop.")
    }

    private func shouldTreatUnverifiedMenuPasteAsFailure(
        for target: TextInsertionTarget?,
        focusedElement: AXUIElement?
    ) -> Bool {
        guard focusedElement == nil else { return false }
        guard let bundleIdentifier = target?.frontmostBundleIdentifier else { return false }
        return bundleIdentifier.hasPrefix("com.todesktop.")
    }

    private func shouldAssumePasteSucceededWithoutVerification(for target: TextInsertionTarget?) -> Bool {
        guard let bundleIdentifier = target?.frontmostBundleIdentifier else {
            return false
        }

        return Self.unverifiablePasteBundleIdentifiers.contains(bundleIdentifier)
    }

    private func executeAppleScript(_ source: String) throws -> Bool {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&error)

        if let error {
            appendDebugTrace("applescript_error=\(error)")
            let errorNumber = error[NSAppleScript.errorNumber] as? Int
            if errorNumber == -1743 {
                throw TextInsertionError.automationPermissionDenied
            }
            return false
        }

        return result != nil
    }

    private func appleScriptEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func beginDebugTrace(text: String, target: TextInsertionTarget?) {
        let clickPointDescription: String
        if let clickPoint = target?.clickPoint {
            clickPointDescription = "\(clickPoint.x),\(clickPoint.y)"
        } else {
            clickPointDescription = "nil"
        }

        let lines = [
            "bundle=\(target?.frontmostBundleIdentifier ?? "unknown")",
            "pid=\(target?.frontmostAppPID ?? 0)",
            "focusedElement=\(target?.focusedElement != nil)",
            "clickPoint=\(clickPointDescription)",
            "textLength=\(text.count)"
        ]
        UserDefaults.standard.set(lines.joined(separator: "\n"), forKey: DefaultsKey.lastInsertionDebug)
    }

    private func appendDebugTrace(_ line: String) {
        let existing = UserDefaults.standard.string(forKey: DefaultsKey.lastInsertionDebug) ?? ""
        let updated = existing.isEmpty ? line : existing + "\n" + line
        UserDefaults.standard.set(updated, forKey: DefaultsKey.lastInsertionDebug)
    }

    private func performPasteMenuAction(on pid: pid_t?) -> Bool {
        guard AXIsProcessTrusted(), let pid else { return false }

        let application = AXUIElementCreateApplication(pid)
        guard let menuBar = copyElementAttribute(kAXMenuBarAttribute, from: application) else {
            return false
        }

        return pressPasteMenuItem(in: menuBar, depth: 0)
    }

    private func pressPasteMenuItem(in element: AXUIElement, depth: Int) -> Bool {
        guard depth < 8 else { return false }

        if let title = copyStringAttribute(kAXTitleAttribute, from: element),
           Self.pasteMenuTitles.contains(title) {
            return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
        }

        let attributes = [
            kAXChildrenAttribute as String,
            "AXMenu"
        ]

        for attribute in attributes {
            for child in copyElementArrayAttribute(attribute, from: element) {
                if pressPasteMenuItem(in: child, depth: depth + 1) {
                    return true
                }
            }
        }

        return false
    }

    private func copyElementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    private func copyElementArrayAttribute(_ attribute: String, from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

        guard result == .success,
              let value,
              let array = value as? [AXUIElement] else {
            return []
        }

        return array
    }

    private func snapshotTextState(of element: AXUIElement?) -> ElementTextSnapshot? {
        guard let element else { return nil }

        return ElementTextSnapshot(
            value: copyStringAttribute(kAXValueAttribute, from: element),
            selectedText: copyStringAttribute(kAXSelectedTextAttribute, from: element)
        )
    }

    private func waitForTextInsertion(
        _ text: String,
        in element: AXUIElement?,
        baseline: ElementTextSnapshot?
    ) -> Bool? {
        guard let element, let baseline else { return nil }

        let baselineHasObservableText = baseline.value != nil || baseline.selectedText != nil
        var observedTextAttributes = baselineHasObservableText
        let deadline = Date().addingTimeInterval(0.9)
        while Date() < deadline {
            let currentValue = copyStringAttribute(kAXValueAttribute, from: element)
            if currentValue != nil {
                observedTextAttributes = true
            }
            if let currentValue,
               currentValue != baseline.value,
               currentValue.contains(text) {
                return true
            }

            let currentSelectedText = copyStringAttribute(kAXSelectedTextAttribute, from: element)
            if currentSelectedText != nil {
                observedTextAttributes = true
            }
            if currentSelectedText == text {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        if !observedTextAttributes {
            return nil
        }

        return false
    }

    private func injectorExecutableURL() -> URL? {
        if let executableURL = Bundle.main.executableURL,
           FileManager.default.isExecutableFile(atPath: executableURL.path) {
            return executableURL
        }

        let developmentURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(Self.injectorExecutableName)

        if FileManager.default.isExecutableFile(atPath: developmentURL.path) {
            return developmentURL
        }

        return nil
    }

    private static func runHelper(
        executableURL: URL,
        arguments: [String],
        text: String
    ) async throws -> HelperRunResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outputPipe = Pipe()
            let inputPipe = Pipe()

            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            process.standardInput = inputPipe

            try process.run()

            if let data = text.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            inputPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            return HelperRunResult(
                terminationStatus: process.terminationStatus,
                output: output
            )
        }.value
    }

    private func waitForShortcutModifiersToRelease() {
        let shortcut = KeyboardShortcutStore.load(.fieldInsert)
        var relevantFlags = CGEventFlags()
        if shortcut.modifiers.contains(.command) { relevantFlags.insert(.maskCommand) }
        if shortcut.modifiers.contains(.control) { relevantFlags.insert(.maskControl) }
        if shortcut.modifiers.contains(.option) { relevantFlags.insert(.maskAlternate) }
        if shortcut.modifiers.contains(.shift) { relevantFlags.insert(.maskShift) }

        // Page Up / Page Down frequently report a transient Fn bit in `combinedSessionState`
        // even though the shortcut itself has no supported modifiers. Waiting for that bit to
        // clear delays or blocks the follow-up paste/type events and leaves Electron editors empty.
        if relevantFlags.isEmpty {
            appendDebugTrace("modifier_wait_skipped=no_supported_shortcut_modifiers")
            return
        }

        let initialFlags = CGEventSource.flagsState(.combinedSessionState).intersection(relevantFlags)
        if !initialFlags.isEmpty {
            appendDebugTrace("modifier_wait_start=\(initialFlags.rawValue)")
        }

        let deadline = Date().addingTimeInterval(0.35)
        while Date() < deadline {
            let flags = CGEventSource.flagsState(.combinedSessionState).intersection(relevantFlags)
            if flags.isEmpty {
                if !initialFlags.isEmpty {
                    appendDebugTrace("modifier_wait_end=cleared")
                }
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        let finalFlags = CGEventSource.flagsState(.combinedSessionState).intersection(relevantFlags)
        if !finalFlags.isEmpty {
            appendDebugTrace("modifier_wait_end=timeout:\(finalFlags.rawValue)")
        }
    }

    private func waitForMouseButtonsToRelease() {
        let deadline = Date().addingTimeInterval(0.35)
        var waited = false

        while Date() < deadline {
            let leftDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
            if !leftDown {
                if waited {
                    appendDebugTrace("mouse_wait_end=released")
                    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                }
                return
            }

            if !waited {
                appendDebugTrace("mouse_wait_start=left_down")
                waited = true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        if waited {
            appendDebugTrace("mouse_wait_end=timeout")
        }
    }

    private static let pasteMenuTitles: Set<String> = [
        "Paste",
        "Paste and Match Style",
        "Paste as Plain Text",
        "Insert",
        "Вставить",
        "Вставить и согласовать стиль",
        "Вставить как обычный текст"
    ]

    private static func isCursorLikeApp(_ target: TextInsertionTarget?) -> Bool {
        guard let id = target?.frontmostBundleIdentifier else { return false }
        return id == "com.openai.codex" || id.hasPrefix("com.todesktop.")
    }

    private static let pasteOnlyInsertionBundleIdentifiers: Set<String> = [
        "com.openai.atlas"
    ]

    private static let unverifiablePasteBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.vivaldi.Vivaldi",
        "com.kagi.kagimacOS",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "com.openai.atlas"
    ]

    private static let placeholderAttributeNames = [
        "AXPlaceholderValue",
        kAXDescriptionAttribute as String,
        kAXHelpAttribute as String
    ]

    private static let codexPromptPrefixes = [
        "Ask Codex anything",
        "Ask for follow-up changes"
    ]

    private static let injectorExecutableName = "VoiceInsert"
    private static let recordedClickTTL: TimeInterval = 90
}

private enum DefaultsKey {
    static let lastInsertionDebug = "voiceInsert.lastInsertionDebug"
}

private extension String {
    func chunkedForEventInsertion(maxCharacters: Int) -> [String] {
        guard count > maxCharacters else { return [self] }

        var chunks: [String] = []
        var current = startIndex

        while current < endIndex {
            let next = index(current, offsetBy: maxCharacters, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[current..<next]))
            current = next
        }

        return chunks
    }
}

private struct PasteboardSnapshot {
    let items: [NSPasteboardItem]

    static func capture() -> Self {
        let items = NSPasteboard.general.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()

            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }

            return copy
        } ?? []

        return Self(items: items)
    }

    /// - Parameter omitImageTypes: After pasting text, restoring a full snapshot can put PNG/TIFF back on the general
    ///   pasteboard; web composers (e.g. LinkedIn) may immediately attach that image. Drop image-ish types on restore.
    func restore(omitImageTypes: Bool = false) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard !items.isEmpty else { return }

        let toWrite: [NSPasteboardItem]
        if omitImageTypes {
            toWrite = Self.itemsOmittingImageTypes(items)
        } else {
            toWrite = items
        }

        guard !toWrite.isEmpty else { return }
        pasteboard.writeObjects(toWrite)
    }

    private static func itemsOmittingImageTypes(_ items: [NSPasteboardItem]) -> [NSPasteboardItem] {
        items.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types {
                if isImageLikePasteboardType(type) {
                    continue
                }
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy.types.isEmpty ? nil : copy
        }
    }

    private static func isImageLikePasteboardType(_ type: NSPasteboard.PasteboardType) -> Bool {
        let raw = type.rawValue.lowercased()
        if raw == "public.png" || raw == "public.jpeg" || raw == "public.jpg" || raw == "public.tiff" || raw == "public.gif" {
            return true
        }
        if raw == "com.compuserve.gif" || raw == "public.image" {
            return true
        }
        if raw == "apple png pasteboard type" || raw == "nebula" {
            return true
        }
        if raw.contains("image") && (raw.contains("png") || raw.contains("tiff") || raw.contains("jpeg")) {
            return true
        }
        return false
    }
}
