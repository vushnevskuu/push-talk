import Foundation
import simd

/// Smoothed values consumed by the Metal flame renderer (time is added on the GPU each frame).
struct FlameAudioDisplayState: Equatable, Sendable {
    var smoothedLevel: Float
    var peakLevel: Float
    var lowBand: Float
    var midBand: Float
    var highBand: Float
    var speakingActivity: Float
    /// 0 = запись; 0…1 = плавное затухание после отпускания хоткея (для GPU).
    var windDownPhase: Float
    /// Усиление тонкого остаточного дыма при затухании.
    var releaseSmoke: Float

    static let silent = FlameAudioDisplayState(
        smoothedLevel: 0.06,
        peakLevel: 0,
        lowBand: 0.08,
        midBand: 0.06,
        highBand: 0.05,
        speakingActivity: 0,
        windDownPhase: 0,
        releaseSmoke: 0
    )

    /// Demo motion for Settings previews (no microphone).
    static func previewDemo(elapsed: TimeInterval) -> FlameAudioDisplayState {
        let wobble = sin(elapsed * 2.1) * 0.5 + 0.5
        let burst = max(0, sin(elapsed * 6.2)) * 0.35
        let level = Float(0.14 + wobble * 0.35 + burst)
        return FlameAudioDisplayState(
            smoothedLevel: level,
            peakLevel: min(1, level + Float(burst * 0.8)),
            lowBand: Float(0.25 + wobble * 0.35),
            midBand: Float(0.2 + sin(elapsed * 3.4) * 0.2 + 0.2),
            highBand: Float(0.15 + sin(elapsed * 8.1) * 0.12 + 0.15),
            speakingActivity: Float(min(1, Double(level) * 1.2)),
            windDownPhase: 0,
            releaseSmoke: 0
        )
    }
}

/// Tunable flame look — edit values here (Swift 6: `let` only for concurrency safety).
enum FlameVisualizerConstants {
    /// Scales how tall the plume grows with voice level.
    static let flameHeightGain: Float = 1.08
    /// Scales base width; low frequencies add on top inside shader.
    static let flameWidthGain: Float = 1.07
    /// Extra turbulence from mid-band energy.
    static let turbulenceGain: Float = 1.15
    /// Minimum “alive” flame when quiet (idle ember).
    static let idleIntensity: Float = 0.14
    /// Outer glow multiplier.
    static let glowIntensity: Float = 1.08
    /// Spatial scale for procedural noise in UV space.
    static let noiseScale: Float = 1.0
    /// Scroll speed for upward flow.
    static let noiseSpeed: Float = 1.35

    // MARK: - Design-guide tuning (premium / a11y / motion)

    /// Chromatic retention after luma mix (lower = calmer, less «arcade orange»).
    static let flameChromaRetention: Float = 0.84
    static let flameChromaRetentionReducedMotion: Float = 0.70
    /// Post-tone-map cap on linear-ish RGB before premultiply (reduces harsh hotspots).
    static let flameIntensityCap: Float = 0.99
    static let flameIntensityCapReducedMotion: Float = 0.88
    /// Time scale inside shader when Reduce Motion is on (slow, almost still sheet).
    static let flameReducedMotionTimeScale: Float = 0.22
    /// MTKView refresh rate when Reduce Motion is enabled.
    static let flameReducedMotionFPS: Int = 18

    /// Smoothing: higher = faster follow when level rises.
    static let levelAttack: Double = 0.58
    /// Smoothing: higher = faster decay when level falls (still slower than attack).
    static let levelRelease: Double = 0.12
    static let peakAttack: Double = 0.9
    static let peakRelease: Double = 0.28
    static let bandAttack: Double = 0.42
    static let bandRelease: Double = 0.14
    static let activityAttack: Double = 0.48
    static let activityRelease: Double = 0.07
    /// RMS gate; below this, input is attenuated toward idle.
    static let noiseFloor: Double = 0.014
}
