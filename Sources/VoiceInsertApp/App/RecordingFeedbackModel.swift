import Foundation

@MainActor
final class RecordingFeedbackModel: ObservableObject {
    @Published private(set) var audioLevel = 0.0
    @Published private(set) var audioLevelHistory = Array(repeating: 0.08, count: 20)
    /// Smoothed microphone + spectral features for the Metal flame HUD.
    @Published private(set) var flameAudioState = FlameAudioDisplayState.silent

    private var samplesAfterReset = 0
    private var smPeak: Double = 0
    private var smLow: Double = Double(FlameAudioDisplayState.silent.lowBand)
    private var smMid: Double = Double(FlameAudioDisplayState.silent.midBand)
    private var smHigh: Double = Double(FlameAudioDisplayState.silent.highBand)
    private var smActivity: Double = 0

    private(set) var isWindDownActive = false
    private var windDownElapsed: Double = 0
    private var windDownDuration: Double = 0.78
    private var windDownSnapshot = FlameAudioDisplayState.silent

    func visualizerLevels(barCount: Int = 18) -> [Double] {
        let baseline = Array(repeating: 0.08, count: barCount)
        guard !audioLevelHistory.isEmpty else { return baseline }

        if audioLevelHistory.count >= barCount {
            return Array(audioLevelHistory.suffix(barCount))
        }

        return Array(repeating: 0.08, count: max(0, barCount - audioLevelHistory.count)) + audioLevelHistory
    }

    func push(metrics: VoiceInsertAudioFrameMetrics) {
        guard !isWindDownActive else { return }
        let c = FlameVisualizerConstants.self
        let clampedLevel = min(max(metrics.rmsNormalized, 0), 1)
        samplesAfterReset += 1
        let inertia: Double = samplesAfterReset <= 12 ? 0.35 : 0.15
        let smoothedLevel = max(0.04, (audioLevel * inertia) + (clampedLevel * (1 - inertia)))
        audioLevel = smoothedLevel
        audioLevelHistory.append(smoothedLevel)

        if audioLevelHistory.count > 28 {
            audioLevelHistory.removeFirst(audioLevelHistory.count - 28)
        }

        let floor = c.noiseFloor
        let gatedRms = metrics.rmsNormalized < floor
            ? metrics.rmsNormalized * (0.25 + 0.35 * (metrics.rmsNormalized / max(floor, 1e-6)))
            : metrics.rmsNormalized

        let levelTarget = min(1, max(0, gatedRms))
        let smLevel = smoothStep(
            target: levelTarget,
            current: Double(flameAudioState.smoothedLevel),
            rise: c.levelAttack,
            fall: c.levelRelease
        )

        smPeak = smoothStep(
            target: min(1, max(0, metrics.peakNormalized)),
            current: smPeak,
            rise: c.peakAttack,
            fall: c.peakRelease
        )

        smLow = smoothStep(target: metrics.lowBand, current: smLow, rise: c.bandAttack, fall: c.bandRelease)
        smMid = smoothStep(target: metrics.midBand, current: smMid, rise: c.bandAttack, fall: c.bandRelease)
        smHigh = smoothStep(target: metrics.highBand, current: smHigh, rise: c.bandAttack, fall: c.bandRelease)

        let actTarget = smLevel > 0.075 ? 1.0 : 0.0
        smActivity = smoothStep(
            target: actTarget,
            current: smActivity,
            rise: c.activityAttack,
            fall: c.activityRelease
        )

        flameAudioState = FlameAudioDisplayState(
            smoothedLevel: Float(min(1, max(0, smLevel))),
            peakLevel: Float(min(1, max(0, smPeak))),
            lowBand: Float(min(1, max(0, smLow))),
            midBand: Float(min(1, max(0, smMid))),
            highBand: Float(min(1, max(0, smHigh))),
            speakingActivity: Float(min(1, max(0, smActivity))),
            windDownPhase: 0,
            releaseSmoke: 0
        )
    }

    /// Снимок последнего кадра пламени; плавное затухание и короткий остаточный дым на GPU.
    func beginWindDown() {
        windDownSnapshot = flameAudioState
        windDownElapsed = 0
        isWindDownActive = true
    }

    /// Один кадр затухания. Возвращает `true`, когда пора скрыть HUD и вызвать `completeWindDownCleanup()`.
    func tickWindDown(delta: Double) -> Bool {
        guard isWindDownActive else { return true }
        windDownElapsed += delta
        let p = min(1, windDownElapsed / windDownDuration)
        let ease = 1 - pow(1 - p, 2.35)

        let s0 = windDownSnapshot
        let idle = FlameAudioDisplayState.silent

        func lerpF(_ a: Float, _ b: Float, _ t: Double) -> Float { a + (b - a) * Float(t) }

        let smokePhase = smoothstep(0.18, 0.42, p) * (1 - smoothstep(0.68, 0.98, p))
        let releaseSmoke = Float(min(1, smokePhase * 1.2))

        flameAudioState = FlameAudioDisplayState(
            smoothedLevel: lerpF(s0.smoothedLevel, idle.smoothedLevel, ease),
            peakLevel: lerpF(s0.peakLevel, 0, min(1, p * 3.2)),
            lowBand: lerpF(s0.lowBand, idle.lowBand, ease),
            midBand: lerpF(s0.midBand, idle.midBand, ease),
            highBand: lerpF(s0.highBand, idle.highBand, ease),
            speakingActivity: lerpF(s0.speakingActivity, 0, min(1, p * 5)),
            windDownPhase: Float(p),
            releaseSmoke: releaseSmoke
        )

        if p >= 1 {
            return true
        }
        return false
    }

    func completeWindDownCleanup() {
        isWindDownActive = false
        windDownElapsed = 0
        reset()
    }

    func cancelWindDownIfNeeded() {
        guard isWindDownActive else { return }
        isWindDownActive = false
        windDownElapsed = 0
        reset()
    }

    func reset() {
        audioLevel = 0
        samplesAfterReset = 0
        audioLevelHistory = Array(repeating: 0.08, count: 20)
        smPeak = 0
        smLow = Double(FlameAudioDisplayState.silent.lowBand)
        smMid = Double(FlameAudioDisplayState.silent.midBand)
        smHigh = Double(FlameAudioDisplayState.silent.highBand)
        smActivity = 0
        isWindDownActive = false
        windDownElapsed = 0
        flameAudioState = .silent
    }

    private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / max(edge1 - edge0, 1e-9), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private func smoothStep(target: Double, current: Double, rise: Double, fall: Double) -> Double {
        let coeff = target > current ? rise : fall
        return current + (target - current) * coeff
    }
}
