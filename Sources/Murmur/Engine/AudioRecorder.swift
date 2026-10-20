import AVFoundation
import Foundation

/// Captures microphone audio and converts it to the 16 kHz mono Float32 stream Whisper expects.
final class AudioRecorder {
    enum RecorderError: LocalizedError {
        case noInputDevice
        var errorDescription: String? { "No microphone input is available." }
    }

    static let sampleRate: Double = 16_000

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
    private var samples: [Float] = []
    private var peakRMS: Float = 0

    private(set) var isRunning = false

    func start() throws {
        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            peakRMS = 0
        }

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

    /// Stops capture and returns the recorded samples plus the loudest RMS seen.
    func stop() -> (samples: [Float], peakRMS: Float) {
        if isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            isRunning = false
        }
        return lock.withLock { (samples, peakRMS) }
    }

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
        guard error == nil, let channel = output.floatChannelData else { return }

        let count = Int(output.frameLength)
        guard count > 0 else { return }
        let chunk = Array(UnsafeBufferPointer(start: channel[0], count: count))

        var sum: Float = 0
        for s in chunk { sum += s * s }
        let rms = sqrt(sum / Float(count))

        lock.withLock {
            samples.append(contentsOf: chunk)
            peakRMS = max(peakRMS, rms)
        }

        let db = 20 * log10(max(rms, 1e-6))
        let level = max(0, min(1, (db + 55) / 45))
        onLevel?(level)
    }
}
