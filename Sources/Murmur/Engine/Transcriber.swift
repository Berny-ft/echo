import Foundation
import WhisperKit

struct WhisperModelOption: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let size: String
}

/// Wraps WhisperKit: downloads the chosen model once, keeps it loaded, and transcribes audio buffers locally.
@MainActor
final class Transcriber: ObservableObject {
    enum Status: Equatable {
        case notLoaded
        case downloading(Double)
        case loading
        case ready
        case failed(String)

        var label: String {
            switch self {
            case .notLoaded: "Not loaded"
            case .downloading(let p): "Downloading \(Int(p * 100))%"
            case .loading: "Optimizing for Neural Engine…"
            case .ready: "Ready"
            case .failed(let msg): "Error: \(msg)"
            }
        }
    }

    static let models: [WhisperModelOption] = [
        .init(id: "openai_whisper-large-v3-v20240930_turbo_632MB",
              name: "Whisper Large v3 Turbo",
              detail: "Best accuracy, multilingual. Recommended.",
              size: "632 MB"),
        .init(id: "openai_whisper-small.en",
              name: "Whisper Small (English)",
              detail: "Fast and accurate for English.",
              size: "~480 MB"),
        .init(id: "openai_whisper-base.en",
              name: "Whisper Base (English)",
              detail: "Very fast, lighter accuracy.",
              size: "~140 MB"),
    ]

    @Published private(set) var status: Status = .notLoaded
    @Published private(set) var loadedModel: String?

    private var kit: WhisperKit?
    private var loadTask: Task<Void, Never>?

    static var storageRoot: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Murmur", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func cachedFolderKey(_ model: String) -> String { "modelFolder.\(model)" }

    func isDownloaded(_ model: String) -> Bool {
        guard let path = UserDefaults.standard.string(forKey: Self.cachedFolderKey(model)) else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    func load(model: String) {
        if loadedModel == model, kit != nil { return }
        loadTask?.cancel()
        loadTask = Task { await performLoad(model: model) }
    }

    private func performLoad(model: String) async {
        kit = nil
        loadedModel = nil
        do {
            let folder: URL
            if let cached = UserDefaults.standard.string(forKey: Self.cachedFolderKey(model)),
               FileManager.default.fileExists(atPath: cached) {
                folder = URL(fileURLWithPath: cached)
            } else {
                status = .downloading(0)
                folder = try await WhisperKit.download(
                    variant: model,
                    downloadBase: Self.storageRoot.appendingPathComponent("models"),
                    progressCallback: { progress in
                        let fraction = progress.fractionCompleted
                        Task { @MainActor [weak self] in
                            if case .downloading = self?.status { self?.status = .downloading(fraction) }
                        }
                    }
                )
                UserDefaults.standard.set(folder.path, forKey: Self.cachedFolderKey(model))
            }
            try Task.checkCancellation()

            status = .loading
            let config = WhisperKitConfig(
                model: model,
                downloadBase: Self.storageRoot.appendingPathComponent("models"),
                modelFolder: folder.path,
                tokenizerFolder: Self.storageRoot.appendingPathComponent("tokenizers"),
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
            let newKit = try await WhisperKit(config)
            try Task.checkCancellation()
            kit = newKit
            loadedModel = model
            status = .ready
        } catch is CancellationError {
            // A newer load replaced this one.
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// - Parameter language: ISO code such as "en", or nil to auto-detect.
    func transcribe(_ samples: [Float], language: String?) async throws -> String {
        guard let kit else { throw MurmurError.modelNotReady }
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperatureFallbackCount: 3,
            usePrefillPrompt: language != nil,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            chunkingStrategy: samples.count > Int(AudioRecorder.sampleRate * 28) ? .vad : ChunkingStrategy.none
        )
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ")
        return Self.stripArtifacts(text)
    }

    /// Removes Whisper's bracketed non-speech tags and common silence hallucinations.
    static func stripArtifacts(_ text: String) -> String {
        var t = text.replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*(music|silence|blank|inaudible|applause)[^)]*\)|<\|[^|]*\|>"#,
                                          with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hallucinations: Set<String> = ["thank you.", "thanks for watching!", "thank you for watching.", "you", "bye.", "."]
        if hallucinations.contains(t.lowercased()) { return "" }
        return t
    }
}

enum MurmurError: LocalizedError {
    case modelNotReady
    case formatter(String)

    var errorDescription: String? {
        switch self {
        case .modelNotReady: "The speech model is still loading."
        case .formatter(let msg): msg
        }
    }
}
