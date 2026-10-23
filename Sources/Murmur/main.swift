import AppKit
import SwiftUI
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
} else if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--chunktest" {
    let path = CommandLine.arguments[2]
    Task { @MainActor in
        await SelfTest.chunkTest(audioPath: path)
        exit(0)
    }
    RunLoop.main.run()
} else if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--overlaytest" {
    let dir = URL(fileURLWithPath: CommandLine.arguments[2])
    MainActor.assumeIsolated { SelfTest.renderOverlay(to: dir) }
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

    /// Simulates a long session: speech separated by long and short pauses, fed through the
    /// recorder's silence trimming and one-minute chunking, then transcribed chunk by chunk.
    static func chunkTest(audioPath: String) async {
        guard let speech = loadSamples(audioPath) else { print("Could not read audio"); return }
        func quiet(_ seconds: Double) -> [Float] {
            (0..<Int(seconds * 16_000)).map { _ in Float.random(in: -0.001...0.001) } // room noise, inaudible
        }
        var session: [Float] = []
        for i in 0..<6 { session += speech + quiet(i % 2 == 0 ? 12 : 3) }
        print(String(format: "Session: %.1fs total (6 × %.1fs speech, alternating 12s / 3s pauses)",
                     Double(session.count) / 16_000, Double(speech.count) / 16_000))

        let recorder = AudioRecorder()
        var chunks: [[Float]] = []
        var i = 0
        while i < session.count {
            let end = min(i + 1600, session.count) // 100 ms blocks, like the mic tap
            recorder.ingest(Array(session[i..<end]))
            i = end
            if let c = recorder.takeChunk(seconds: 60) { chunks.append(c) }
        }
        let final = recorder.stop().samples
        chunks.append(final)
        let stats = recorder.stats
        print(String(format: "Kept %.1fs, cut %.1fs of silence. Expected cut: 3 × (12 − 1.2) = 32.4s", stats.kept, stats.cut))
        print("Chunks: " + chunks.map { String(format: "%.1fs", Double($0.count) / 16_000) }.joined(separator: ", "))

        let transcriber = Transcriber()
        transcriber.load(model: Preferences.shared.whisperModel)
        while transcriber.status != .ready {
            if case .failed(let msg) = transcriber.status { print("FAILED: \(msg)"); return }
            try? await Task.sleep(for: .milliseconds(200))
        }
        var parts: [String] = []
        for (n, c) in chunks.enumerated() {
            let t = Date()
            let text = (try? await transcriber.transcribe(c, language: "en")) ?? "<error>"
            print(String(format: "\n[chunk %d, %.1fs audio → %.2fs] %@", n + 1, Double(c.count) / 16_000, Date().timeIntervalSince(t), text))
            parts.append(text)
        }
        let joined = parts.joined(separator: " ").lowercased()
        let count = joined.components(separatedBy: "let me know if you have any questions").count - 1
        print("\nFull sentence 'let me know if you have any questions' found \(count)/6 times")
    }

    /// Renders the recording indicator in each state to PNGs, without needing a microphone.
    static func renderOverlay(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let controller = DictationController()
        let wave: [CGFloat] = (0..<28).map { i in CGFloat(0.25 + 0.6 * abs(sin(Double(i) * 0.7))) }
        let states: [(String, DictationController.Phase, TimeInterval)] = [
            ("1-recording", .recording(handsFree: false), 7),
            ("2-handsfree", .recording(handsFree: true), 754),
            ("3-transcribing", .transcribing, 0),
            ("4-formatting", .formatting, 0),
            ("5-done", .done("Pasted"), 0),
            ("6-error", .error("No speech detected"), 0),
        ]
        for (name, phase, elapsed) in states {
            controller.preview(phase: phase, levels: wave, elapsed: elapsed)
            let view = OverlayView()
                .environmentObject(controller)
                .frame(width: 260, height: 44)
                .background(Color(white: 0.85))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
                print("wrote \(name).png")
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
