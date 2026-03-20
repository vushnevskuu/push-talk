import AppKit
import Carbon.HIToolbox
import Foundation

enum HotkeyMonitorState: String {
    case inactive
    case globalTap
    case localFallback
}

final class HotkeyMonitor {
    private let stateLock = NSLock()
    private var shortcut = KeyboardShortcut.default
    private var isSuspended = false
    private var isPressed = false
    private var onPressHandler: @MainActor @Sendable () -> Void = {}
    private var onReleaseHandler: @MainActor @Sendable () -> Void = {}
    private var onStateChangeHandler: @MainActor @Sendable (HotkeyMonitorState) -> Void = { _ in }
    private var monitorState: HotkeyMonitorState = .inactive

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var eventHandlerUPP: EventHandlerUPP?
    private var localKeyDownMonitor: Any?
    private var localKeyUpMonitor: Any?

    func start() {
        if hotKeyRef != nil {
            dispatchState(.globalTap)
            return
        }

        if installGlobalHotKey() {
            removeLocalFallbackMonitors()
            dispatchState(.globalTap)
            return
        }

        if localKeyDownMonitor == nil, localKeyUpMonitor == nil {
            installLocalFallbackMonitors()
        }

        dispatchState(.localFallback)
    }

    func setHandlers(
        onPress: @escaping @MainActor @Sendable () -> Void,
        onRelease: @escaping @MainActor @Sendable () -> Void
    ) {
        stateLock.lock()
        onPressHandler = onPress
        onReleaseHandler = onRelease
        stateLock.unlock()
    }

    func setStateHandler(
        _ handler: @escaping @MainActor @Sendable (HotkeyMonitorState) -> Void
    ) {
        stateLock.lock()
        onStateChangeHandler = handler
        let currentState = monitorState
        stateLock.unlock()

        Task { @MainActor in
            handler(currentState)
        }
    }

    func updateShortcut(_ shortcut: KeyboardShortcut) {
        stateLock.lock()
        self.shortcut = shortcut
        isPressed = false
        stateLock.unlock()

        unregisterGlobalHotKey()
        start()
    }

    func setSuspended(_ suspended: Bool) {
        let shouldRelease: Bool

        stateLock.lock()
        isSuspended = suspended
        shouldRelease = suspended && isPressed
        if shouldRelease {
            isPressed = false
        }
        stateLock.unlock()

        if shouldRelease {
            dispatchRelease()
        }
    }

    private func installGlobalHotKey() -> Bool {
        if eventHandlerRef == nil {
            var eventTypes = [
                EventTypeSpec(
                    eventClass: OSType(kEventClassKeyboard),
                    eventKind: UInt32(kEventHotKeyPressed)
                ),
                EventTypeSpec(
                    eventClass: OSType(kEventClassKeyboard),
                    eventKind: UInt32(kEventHotKeyReleased)
                )
            ]

            let eventHandler: EventHandlerUPP = { _, event, userData in
                guard let userData else { return noErr }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                return monitor.handleRegisteredHotKey(event)
            }

            let installStatus = InstallEventHandler(
                GetApplicationEventTarget(),
                eventHandler,
                eventTypes.count,
                &eventTypes,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandlerRef
            )

            guard installStatus == noErr else {
                return false
            }

            eventHandlerUPP = eventHandler
        }

        var hotKeyID = EventHotKeyID(
            signature: fourCharCode("VIns"),
            id: UInt32(shortcut.keyCode)
        )

        let registerStatus = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            carbonModifiers(for: shortcut.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        return registerStatus == noErr
    }

    private func unregisterGlobalHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func handleRegisteredHotKey(_ event: EventRef?) -> OSStatus {
        guard let event else { return noErr }

        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            if shouldTriggerRegisteredPress() {
                dispatchPress()
            }
        case UInt32(kEventHotKeyReleased):
            if shouldTriggerRegisteredRelease() {
                dispatchRelease()
            }
        default:
            break
        }

        return noErr
    }

    private func shouldTriggerRegisteredPress() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !isSuspended else { return false }
        guard !isPressed else { return false }

        isPressed = true
        return true
    }

    private func shouldTriggerRegisteredRelease() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard isPressed else { return false }

        isPressed = false
        return !isSuspended
    }

    private func installLocalFallbackMonitors() {
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalKeyDown(event)
        }

        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalKeyUp(event)
        }
    }

    private func removeLocalFallbackMonitors() {
        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
            self.localKeyDownMonitor = nil
        }

        if let localKeyUpMonitor {
            NSEvent.removeMonitor(localKeyUpMonitor)
            self.localKeyUpMonitor = nil
        }
    }

    private func handleLocalKeyDown(_ event: NSEvent) -> NSEvent? {
        let decision = evaluateLocalKeyEvent(
            type: .keyDown,
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection(KeyboardShortcut.supportedModifiers)
        )

        if decision.triggerPress {
            dispatchPress()
        }

        return decision.shouldSuppress ? nil : event
    }

    private func handleLocalKeyUp(_ event: NSEvent) -> NSEvent? {
        let decision = evaluateLocalKeyEvent(
            type: .keyUp,
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection(KeyboardShortcut.supportedModifiers)
        )

        if decision.triggerRelease {
            dispatchRelease()
        }

        return decision.shouldSuppress ? nil : event
    }

    private func evaluateLocalKeyEvent(
        type: NSEvent.EventType,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> KeyEventDecision {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !isSuspended else {
            return KeyEventDecision(shouldSuppress: false, triggerPress: false, triggerRelease: false)
        }

        switch type {
        case .keyDown:
            guard keyCode == shortcut.keyCode, modifiers == shortcut.modifiers else {
                return KeyEventDecision(shouldSuppress: false, triggerPress: false, triggerRelease: false)
            }

            if isPressed {
                return KeyEventDecision(shouldSuppress: true, triggerPress: false, triggerRelease: false)
            }

            isPressed = true
            return KeyEventDecision(shouldSuppress: true, triggerPress: true, triggerRelease: false)

        case .keyUp:
            guard isPressed, keyCode == shortcut.keyCode else {
                return KeyEventDecision(shouldSuppress: false, triggerPress: false, triggerRelease: false)
            }

            isPressed = false
            return KeyEventDecision(shouldSuppress: true, triggerPress: false, triggerRelease: true)

        default:
            return KeyEventDecision(shouldSuppress: false, triggerPress: false, triggerRelease: false)
        }
    }

    private func dispatchPress() {
        let handler = callback(kind: .press)
        Task { @MainActor in
            handler()
        }
    }

    private func dispatchRelease() {
        let handler = callback(kind: .release)
        Task { @MainActor in
            handler()
        }
    }

    private func dispatchState(_ state: HotkeyMonitorState) {
        let handler = stateChangeHandler(for: state)
        Task { @MainActor in
            handler(state)
        }
    }

    private func callback(kind: CallbackKind) -> @MainActor @Sendable () -> Void {
        stateLock.lock()
        defer { stateLock.unlock() }

        switch kind {
        case .press:
            return onPressHandler
        case .release:
            return onReleaseHandler
        }
    }

    private func stateChangeHandler(for state: HotkeyMonitorState) -> @MainActor @Sendable (HotkeyMonitorState) -> Void {
        stateLock.lock()
        monitorState = state
        let handler = onStateChangeHandler
        stateLock.unlock()
        return handler
    }

    private func carbonModifiers(for modifiers: NSEvent.ModifierFlags) -> UInt32 {
        var carbonModifiers: UInt32 = 0

        if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

        return carbonModifiers
    }

    private func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }
}

private struct KeyEventDecision {
    let shouldSuppress: Bool
    let triggerPress: Bool
    let triggerRelease: Bool
}

private enum CallbackKind {
    case press
    case release
}
