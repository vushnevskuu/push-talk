import Foundation

/// Snapshot from the realtime audio tap (before MainActor smoothing).
struct VoiceInsertAudioFrameMetrics: Sendable {
    /// RMS mapped to 0…1 (same perceptual curve as legacy `TapAudioMath`).
    var rmsNormalized: Double
    /// Peak |sample| mapped to 0…1.
    var peakNormalized: Double
    /// Normalized spectral band energies (FFT), roughly 0…1 each.
    var lowBand: Double
    var midBand: Double
    var highBand: Double
}
