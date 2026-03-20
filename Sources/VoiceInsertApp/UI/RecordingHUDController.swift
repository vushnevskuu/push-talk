import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class RecordingHUDController {
    private var panel: NSPanel?
    private var isVisible = false

    func attach(to feedbackModel: RecordingFeedbackModel) {
        panel = makePanel(with: feedbackModel)
    }

    func show() {
        guard let panel else { return }

        panel.setFrame(defaultFrame(for: panel.frame.size), display: false)
        panel.alphaValue = isVisible ? 1 : 0
        panel.orderFrontRegardless()

        guard !isVisible else { return }
        isVisible = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, isVisible else { return }
        isVisible = false

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
            }
        }
    }

    private func makePanel(with feedbackModel: RecordingFeedbackModel) -> NSPanel {
        let size = NSSize(width: 248, height: 72)
        let panel = NonActivatingPanel(
            contentRect: defaultFrame(for: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        panel.contentView = NSHostingView(rootView: RecordingHUDView(model: feedbackModel))

        return panel
    }

    private func defaultFrame(for size: NSSize) -> NSRect {
        let screen = activeScreen() ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        let origin = NSPoint(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.maxY - size.height - 22
        )

        return NSRect(origin: origin, size: size)
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }
}
