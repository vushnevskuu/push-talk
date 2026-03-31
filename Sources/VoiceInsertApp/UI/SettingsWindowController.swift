import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
        let hostingView = NSHostingView(rootView: SettingsView(model: model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "VoiceInsert Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.minSize = NSSize(width: 820, height: 660)
        window.setFrameAutosaveName("VoiceInsertSettingsWindow")

        self.window = window

        super.init()
        self.window.delegate = self
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        model?.clearShortcutRecordingSessionIfNeeded()
    }
}
