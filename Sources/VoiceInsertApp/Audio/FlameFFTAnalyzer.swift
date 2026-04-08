import Accelerate
import AVFoundation
import Foundation

/// 512-point complex FFT (real input) on the audio tap thread — no allocations in `analyze`.
final class FlameFFTAnalyzer: @unchecked Sendable {
    private static let fftLength = 512
    private static let log2n: vDSP_Length = 9

    private let fftSetup: FFTSetup
    private var window: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var scratchFloat: [Float]

    init() {
        // `FFTRadix(2)` == C `kFFTRadix2_Radix4` (radix-2/4 mixed).
        guard let setup = vDSP_create_fftsetup(Self.log2n, FFTRadix(2)) else {
            fatalError("VoiceInsert: vDSP_create_fftsetup failed")
        }
        fftSetup = setup
        window = [Float](repeating: 0, count: Self.fftLength)
        real = [Float](repeating: 0, count: Self.fftLength)
        imag = [Float](repeating: 0, count: Self.fftLength)
        scratchFloat = [Float](repeating: 0, count: Self.fftLength)
        vDSP_hann_window(&window, vDSP_Length(Self.fftLength), Int32(vDSP_HANN_NORM))
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func analyze(buffer: AVAudioPCMBuffer) -> VoiceInsertAudioFrameMetrics {
        let n = Self.fftLength
        let frameCount = min(Int(buffer.frameLength), n)
        guard frameCount > 0 else {
            return VoiceInsertAudioFrameMetrics(
                rmsNormalized: 0,
                peakNormalized: 0,
                lowBand: 0,
                midBand: 0,
                highBand: 0
            )
        }

        let sampleRate = max(buffer.format.sampleRate, 1)

        // Float mono → scratchFloat[0..<n]
        if let ch = buffer.floatChannelData {
            scratchFloat.withUnsafeMutableBufferPointer { dst in
                memcpy(dst.baseAddress!, ch[0], frameCount * MemoryLayout<Float>.size)
                if frameCount < n {
                    memset(dst.baseAddress! + frameCount, 0, (n - frameCount) * MemoryLayout<Float>.size)
                }
            }
        } else if let ch16 = buffer.int16ChannelData {
            vDSP_vflt16(ch16[0], 1, &scratchFloat, 1, vDSP_Length(frameCount))
            var scale = 1.0 / Float(Int16.max)
            vDSP_vsmul(scratchFloat, 1, &scale, &scratchFloat, 1, vDSP_Length(frameCount))
            if frameCount < n {
                scratchFloat.replaceSubrange(frameCount..<n, with: [Float](repeating: 0, count: n - frameCount))
            }
        } else {
            return VoiceInsertAudioFrameMetrics(
                rmsNormalized: 0,
                peakNormalized: 0,
                lowBand: 0,
                midBand: 0,
                highBand: 0
            )
        }

        var peakAbs: Float = 0
        for i in 0..<frameCount {
            peakAbs = max(peakAbs, abs(scratchFloat[i]))
        }

        var meanSq: Float = 0
        vDSP_measqv(scratchFloat, 1, &meanSq, vDSP_Length(n))
        let rms = sqrt(meanSq)
        let rmsNorm = Self.normalizedUnit(fromRMS: rms)
        let peakNorm = Self.normalizedUnit(fromRMS: max(peakAbs, 1e-6))

        vDSP_vmul(scratchFloat, 1, window, 1, &real, 1, vDSP_Length(n))
        imag.withUnsafeMutableBufferPointer { bp in
            if let base = bp.baseAddress {
                vDSP_vclr(base, 1, vDSP_Length(n))
            }
        }

        real.withUnsafeMutableBufferPointer { rbp in
            imag.withUnsafeMutableBufferPointer { ibp in
                var split = DSPSplitComplex(realp: rbp.baseAddress!, imagp: ibp.baseAddress!)
                vDSP_fft_zip(fftSetup, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
            }
        }

        // Energy in linear frequency bins (skip DC).
        let binHz = Float(sampleRate / Double(n))
        var lowE: Float = 0
        var midE: Float = 0
        var highE: Float = 0
        let lowMaxHz: Float = 500
        let midMaxHz: Float = 4_000

        for k in 1..<(n / 2) {
            let re = real[k]
            let im = imag[k]
            let mag = re * re + im * im
            let hz = Float(k) * binHz
            if hz < lowMaxHz {
                lowE += mag
            } else if hz < midMaxHz {
                midE += mag
            } else {
                highE += mag
            }
        }

        let norm: Float = 1 / (1e-8 + lowE + midE + highE)

        return VoiceInsertAudioFrameMetrics(
            rmsNormalized: rmsNorm,
            peakNormalized: peakNorm,
            lowBand: Double(min(max(lowE * norm, 0), 1)),
            midBand: Double(min(max(midE * norm, 0), 1)),
            highBand: Double(min(max(highE * norm, 0), 1))
        )
    }

    private static func normalizedUnit(fromRMS rms: Float) -> Double {
        let clampedRMS = max(rms, 0.000_01)
        let decibels = 20 * log10(clampedRMS)
        let normalized = (decibels + 52) / 52
        return Double(min(max(normalized, 0), 1))
    }
}
