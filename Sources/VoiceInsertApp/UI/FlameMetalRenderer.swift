import MetalKit
import QuartzCore
import simd

/// Matches `FlameShaderSource.metal` `FlameUniforms`.
private struct FlameMetalUniforms {
    var pack0: SIMD4<Float>
    var pack1: SIMD4<Float>
    var pack2: SIMD4<Float>
    var pack3: SIMD4<Float>
    var pack4: SIMD4<Float>
    /// x: windDownPhase, y: releaseSmoke, z,w: unused
    var pack5: SIMD4<Float>
}

/// Metal flame plume; `MTKView` delegate — keep draw work on GPU.
final class FlameMetalRenderer: NSObject, MTKViewDelegate {
    private weak var mtkView: MTKView?
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private let stateLock = NSLock()
    private var displayState = FlameAudioDisplayState.silent
    private var reducedMotion = false

    /// `MTKView` is configured on the main thread from `NSViewRepresentable`.
    @MainActor
    init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        commandQueue = queue
        super.init()
        view.device = device
        view.delegate = self
        mtkView = view
        pipelineState = Self.makePipeline(device: device)
    }

    @MainActor
    func update(displayState: FlameAudioDisplayState, reducedMotion: Bool) {
        stateLock.lock()
        self.displayState = displayState
        self.reducedMotion = reducedMotion
        stateLock.unlock()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipelineState,
              let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }

        stateLock.lock()
        let state = displayState
        let rm = reducedMotion
        stateLock.unlock()

        let time = Float(CACurrentMediaTime())
        let rmF: Float = rm ? 1.0 : 0.0
        let chroma: Float = rm
            ? FlameVisualizerConstants.flameChromaRetentionReducedMotion
            : FlameVisualizerConstants.flameChromaRetention
        let cap: Float = rm
            ? FlameVisualizerConstants.flameIntensityCapReducedMotion
            : FlameVisualizerConstants.flameIntensityCap
        let timeScaleRM = rm ? FlameVisualizerConstants.flameReducedMotionTimeScale : 1.0

        var uniforms = FlameMetalUniforms(
            pack0: SIMD4<Float>(time, state.smoothedLevel, state.peakLevel, state.speakingActivity),
            pack1: SIMD4<Float>(
                state.lowBand,
                state.midBand,
                state.highBand,
                FlameVisualizerConstants.flameHeightGain
            ),
            pack2: SIMD4<Float>(
                FlameVisualizerConstants.flameWidthGain,
                FlameVisualizerConstants.turbulenceGain,
                FlameVisualizerConstants.idleIntensity,
                FlameVisualizerConstants.glowIntensity
            ),
            pack3: SIMD4<Float>(
                FlameVisualizerConstants.noiseScale,
                FlameVisualizerConstants.noiseSpeed,
                Float(view.drawableSize.width),
                Float(view.drawableSize.height)
            ),
            pack4: SIMD4<Float>(rmF, chroma, cap, timeScaleRM),
            pack5: SIMD4<Float>(state.windDownPhase, state.releaseSmoke, 0, 0)
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FlameMetalUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private static func makePipeline(device: MTLDevice) -> MTLRenderPipelineState? {
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: FlameShaderSource.metal, options: nil)
        } catch {
            return nil
        }
        guard let vfn = library.makeFunction(name: "flameVertex"),
              let ffn = library.makeFunction(name: "flameFragment") else { return nil }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        let att = desc.colorAttachments[0]!
        att.isBlendingEnabled = true
        att.rgbBlendOperation = .add
        att.alphaBlendOperation = .add
        att.sourceRGBBlendFactor = .one
        att.destinationRGBBlendFactor = .oneMinusSourceAlpha
        att.sourceAlphaBlendFactor = .one
        att.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            return try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            return nil
        }
    }
}
