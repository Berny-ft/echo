import AVFoundation
import Foundation

/// Captures microphone audio as the 16 kHz mono Float32 stream Whisper expects.
///
/// Silence handling: any stretch with no audible sound longer than `maxSilence` is cut down to a short
/// pad on each side, so long pauses cost nothing to transcribe. Audio is handed off in roughly
/// one-minute chunks (split at the quietest nearby moment) so transcription can run while you talk.
final class AudioRecorder {
    enum RecorderError: LocalizedError {
        case noInputDevice
        var errorDescription: String? { "No microphone input is available." }
    }

    static let sampleRate: Double = 16_000
    /// RMS below this (about -44 dBFS) counts as silence.
    static let silenceThreshold: Float = 0.006
    static let maxSilence: TimeInterval = 5
    /// Silence kept on each side of a cut, so speech doesn't sound clipped.
    static let silencePad: TimeInterval = 0.6

    private static let frameSize = 480 // 30 ms
    private static var maxSilenceSamples: Int { Int(maxSilence * sampleRate) }
    private static var padSamples: Int { Int(silencePad * sampleRate) }

    /// Called on an audio thread with a normalized 0...1 loudness value.
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioRecorder.sampleRate,
        channels: 1,
        interleaved: false
    )!

    private let lock = NSLock()
    /// Audio kept and not yet handed out as a chunk.
    private var kept: [Float] = []
    /// Silent frames waiting to see whether the pause exceeds `maxSilence`.
    private var pendingSilence: [Float] = []
    private var pendingSilenceTotal = 0
    private var remainder: [Float] = []
    private var peakRMS: Float = 0
    private var keptTotal = 0
    private var droppedTotal = 0

    private(set) var isRunning = false

    // MARK: - Capture

    func start() throws {
        reset()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.noInputDevice
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    /// Stops capture and returns the audio not yet taken as chunks.
    func stop() -> (samples: [Float], peakRMS: Float) {
        if isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            isRunning = false
        }
        return lock.withLock {
            // Keep only a short pad of trailing silence.
            let tail = pendingSilence.prefix(Self.padSamples)
            kept.append(contentsOf: tail)
            keptTotal += tail.count
            droppedTotal += pendingSilenceTotal - tail.count
            pendingSilence.removeAll()
            pendingSilenceTotal = 0
            let out = kept
            kept.removeAll()
            return (out, peakRMS)
        }
    }

    func reset() {
        lock.withLock {
            kept.removeAll(keepingCapacity: true)
            pendingSilence.removeAll()
            pendingSilenceTotal = 0
            remainder.removeAll()
            peakRMS = 0
            keptTotal = 0
            droppedTotal = 0
        }
    }

    /// Seconds of audio kept (after silence trimming) and seconds cut, for the whole session.
    var stats: (kept: TimeInterval, cut: TimeInterval) {
        lock.withLock { (Double(keptTotal) / Self.sampleRate, Double(droppedTotal) / Self.sampleRate) }
    }

    // MARK: - Chunking

    /// Returns about `seconds` of audio once that much has accumulated, split at the quietest point
    /// in the last few seconds so a word is never cut in half.
    func takeChunk(seconds: TimeInterval = 60) -> [Float]? {
        lock.withLock {
            let target = Int(seconds * Self.sampleRate)
            guard kept.count >= target else { return nil }
            let window = Int(0.3 * Self.sampleRate)
            let searchStart = max(window, target - Int(8 * Self.sampleRate))
            var bestCut = target
            var bestEnergy = Float.greatestFiniteMagnitude
            var i = searchStart
            while i + window <= kept.count && i <= target {
                var sum: Float = 0
                for j in i..<(i + window) { sum += kept[j] * kept[j] }
                if sum < bestEnergy {
                    bestEnergy = sum
                    bestCut = i + window / 2
                }
                i += window / 2
            }
            let chunk = Array(kept[..<bestCut])
            kept.removeFirst(bestCut)
            return chunk
        }
    }

    // MARK: - Processing

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = output.floatChannelData, output.frameLength > 0 else { return }
        ingest(Array(UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength))))
    }

    /// Feeds 16 kHz mono samples through silence trimming. Public so the self-test can drive it from a file.
    func ingest(_ samples: [Float]) {
        var loudest: Float = 0
        lock.withLock {
            remainder.append(contentsOf: samples)
            var offset = 0
            while offset + Self.frameSize <= remainder.count {
                let frame = remainder[offset..<(offset + Self.frameSize)]
                offset += Self.frameSize
                var sum: Float = 0
                for s in frame { sum += s * s }
                let rms = sqrt(sum / Float(Self.frameSize))
                loudest = max(loudest, rms)
                peakRMS = max(peakRMS, rms)

                if rms >= Self.silenceThreshold {
                    flushSilence()
                    kept.append(contentsOf: frame)
                    keptTotal += frame.count
                } else {
                    appendSilence(frame)
                }
            }
            remainder.removeFirst(offset)
        }
        let db = 20 * log10(max(loudest, 1e-6))
        onLevel?(max(0, min(1, (db + 55) / 45)))
    }

    /// Holds silence; once a pause exceeds the limit, keeps only the head pad plus a rolling tail pad.
    private func appendSilence(_ frame: ArraySlice<Float>) {
        pendingSilence.append(contentsOf: frame)
        pendingSilenceTotal += frame.count
        let pad = Self.padSamples
        if pendingSilenceTotal > Self.maxSilenceSamples, pendingSilence.count > pad * 2 {
            pendingSilence.removeSubrange(pad..<(pendingSilence.count - pad))
        }
    }

    /// Sound resumed: commit the pause (trimmed if it was too long).
    private func flushSilence() {
        guard pendingSilenceTotal > 0 else { return }
        kept.append(contentsOf: pendingSilence)
        keptTotal += pendingSilence.count
        droppedTotal += pendingSilenceTotal - pendingSilence.count
        pendingSilence.removeAll(keepingCapacity: true)
        pendingSilenceTotal = 0
    }
}
