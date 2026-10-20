import AppKit
import AVFoundation
import Foundation

// `Murmur --selftest <audio file>` runs the transcribe → format pipeline headlessly and prints the results.
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--selftest" {
    let path = CommandLine.arguments[2]
    Task { @MainActor in
        await SelfTest.run(audioPath: path)
        exit(0)
    }
    RunLoop.main.run()
} else {
    MurmurApp.main()
}

@MainActor
enum SelfTest {
    static func run(audioPath: String) async {
        let prefs = Preferences.shared
        let transcriber = Transcriber()
        print("Loading \(prefs.whisperModel)…")
        let t0 = Date()
        transcriber.load(model: prefs.whisperModel)
        while transcriber.status != .ready {
            if case .failed(let msg) = transcriber.status { print("FAILED: \(msg)"); return }
            try? await Task.sleep(for: .milliseconds(200))
        }
        print(String(format: "Model ready in %.1fs", Date().timeIntervalSince(t0)))

        guard let samples = loadSamples(audioPath) else { print("Could not read audio"); return }
        let t1 = Date()
        let raw = (try? await transcriber.transcribe(samples, language: "en")) ?? "<error>"
        print(String(format: "RAW (%.2fs): %@", Date().timeIntervalSince(t1), raw))

        for engine in [FormatEngine.rules, .apple, .ollama] {
            for style in [FormatStyle.smart, .notes, .email] {
                let ctx = TextFormatter.Context(style: style, appName: nil, bundleID: nil, vocabulary: ["Murmur"], replacements: [])
                let t2 = Date()
                let out = await TextFormatter.format(raw, engine: engine, ollamaModel: prefs.ollamaModel, context: ctx)
                print(String(format: "\n── %@ / %@ [%@] (%.2fs)\n%@", engine.title, style.title, out.engineUsed, Date().timeIntervalSince(t2), out.text))
            }
        }
    }

    static func loadSamples(_ path: String) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { return nil }
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target),
              let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: inBuf)) != nil else { return nil }
        let cap = AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate + 1024)
        let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap)!
        var fed = false
        converter.convert(to: out, error: nil) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return inBuf
        }
        return Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
    }
}
