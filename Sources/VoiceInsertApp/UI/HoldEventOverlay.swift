import AppKit
import SwiftUI

struct HoldEventOverlay: NSViewRepresentable {
    let onPress: () -> Void
    let onRelease: () -> Void

    func makeNSView(context: Context) -> HoldTrackingView {
        let view = HoldTrackingView()
        view.onPress = onPress
        view.onRelease = onRelease
        return view
    }

    func updateNSView(_ nsView: HoldTrackingView, context: Context) {
        nsView.onPress = onPress
        nsView.onRelease = onRelease
    }
}

final class HoldTrackingView: NSView {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    private var isHandlingPress = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard !isHandlingPress else { return }
        isHandlingPress = true
        onPress()
    }

    override func mouseUp(with event: NSEvent) {
        guard isHandlingPress else { return }
        onRelease()
        isHandlingPress = false
    }
}
