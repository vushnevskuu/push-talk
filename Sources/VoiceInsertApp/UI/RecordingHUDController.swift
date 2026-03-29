import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class RecordingHUDController {
    private var panel: NSPanel?
    private var isVisible = false
    private weak var hostingView: ClearHUDHostingView<RecordingHUDView>?
    private weak var feedbackModel: RecordingFeedbackModel?
    private var currentStyle: RecordingHUDStyle = .glassBar

    func attach(to feedbackModel: RecordingFeedbackModel, style: RecordingHUDStyle) {
        self.feedbackModel = feedbackModel
        currentStyle = style
        panel = makePanel(with: feedbackModel, style: style)
    }

    func show() {
        guard let panel else { return }

        panel.setFrame(defaultFrame(for: currentStyle.panelSize), display: false)
        panel.alphaValue = isVisible ? 1 : 0
        panel.orderFrontRegardless()

        if isVisible {
            panel.alphaValue = 1
            return
        }
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
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // If show() ran again while fading out, stay visible — avoid orderOut + stuck alpha / ghost hit layer.
                guard !self.isVisible else { return }
                panel.orderOut(nil)
            }
        }
    }

    func updateStyle(_ style: RecordingHUDStyle) {
        currentStyle = style
        guard let panel, let feedbackModel, let hostingView else { return }

        hostingView.rootView = RecordingHUDView(model: feedbackModel, style: style)

        if isVisible {
            panel.setFrame(defaultFrame(for: style.panelSize), display: true, animate: true)
        } else {
            panel.setFrame(defaultFrame(for: style.panelSize), display: false)
        }
    }

    private func makePanel(with feedbackModel: RecordingFeedbackModel, style: RecordingHUDStyle) -> NSPanel {
        let size = style.panelSize
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
        let hostingView = ClearHUDHostingView(rootView: RecordingHUDView(model: feedbackModel, style: style))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        self.hostingView = hostingView

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

private final class ClearHUDHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool {
        false
    }

    /// HUD must never steal clicks / keyboard focus from the app under the cursor (SwiftUI can still hit-test otherwise).
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
