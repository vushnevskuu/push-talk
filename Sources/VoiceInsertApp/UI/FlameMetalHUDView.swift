import AppKit
import MetalKit
import SwiftUI

/// SwiftUI bridge for the procedural Metal flame (single continuous plume).
struct FlameMetalHUDView: NSViewRepresentable {
    var audioState: FlameAudioDisplayState
    var reducedMotion: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.framebufferOnly = false
        view.enableSetNeedsDisplay = false
        view.autoResizeDrawable = true
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .invalid
        view.preferredFramesPerSecond = reducedMotion ? FlameVisualizerConstants.flameReducedMotionFPS : 60
        view.sampleCount = 1
        view.isPaused = false

        if let renderer = FlameMetalRenderer(view: view) {
            context.coordinator.renderer = renderer
        }
        context.coordinator.renderer?.update(displayState: audioState, reducedMotion: reducedMotion)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        let fps = reducedMotion ? FlameVisualizerConstants.flameReducedMotionFPS : 60
        if nsView.preferredFramesPerSecond != fps {
            nsView.preferredFramesPerSecond = fps
        }
        context.coordinator.renderer?.update(displayState: audioState, reducedMotion: reducedMotion)
    }

    final class Coordinator {
        var renderer: FlameMetalRenderer?
    }
}
