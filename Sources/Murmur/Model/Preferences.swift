import Foundation
import SwiftUI

enum FormatStyle: String, CaseIterable, Identifiable, Codable {
    case smart, clean, polished, notes, email, message

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: "Smart"
        case .clean: "Clean"
        case .polished: "Polished"
        case .notes: "Notes"
        case .email: "Email"
        case .message: "Message"
        }
    }

    var subtitle: String {
        switch self {
        case .smart: "Adapts to the app you're typing in"
        case .clean: "Your words, minus the ums and stumbles"
        case .polished: "Clear, well-structured prose"
        case .notes: "Organized bullet points"
        case .email: "Greeting, paragraphs, sign-off"
        case .message: "Short and conversational"
        }
    }

    var symbol: String {
        switch self {
        case .smart: "sparkles"
        case .clean: "wand.and.rays"
        case .polished: "text.quote"
        case .notes: "list.bullet"
        case .email: "envelope"
        case .message: "bubble.left.and.bubble.right"
        }
    }
}

enum FormatEngine: String, CaseIterable, Identifiable, Codable {
    case apple, ollama, rules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .ollama: "Ollama"
        case .rules: "Basic cleanup only"
        }
    }

    var subtitle: String {
        switch self {
        case .apple: "On-device Apple foundation model. Fast, private, free."
        case .ollama: "Any local model served by Ollama."
        case .rules: "No AI rewriting. Removes fillers and fixes capitalization."
        }
    }
}

enum Hotkey: String, CaseIterable, Identifiable, Codable {
    case rightOption, rightCommand, rightControl, fn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rightOption: "Right ⌥ Option"
        case .rightCommand: "Right ⌘ Command"
        case .rightControl: "Right ⌃ Control"
        case .fn: "fn / 🌐 Globe"
        }
    }

    var short: String {
        switch self {
        case .rightOption: "Right ⌥"
        case .rightCommand: "Right ⌘"
        case .rightControl: "Right ⌃"
        case .fn: "fn"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .rightOption: 61
        case .rightCommand: 54
        case .rightControl: 62
        case .fn: 63
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightOption: .option
        case .rightCommand: .command
        case .rightControl: .control
        case .fn: .function
        }
    }
}

struct Replacement: Identifiable, Codable, Hashable {
    var id = UUID()
    var spoken: String
    var written: String
}

/// User settings, persisted to UserDefaults.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @AppStorage("style") var style: FormatStyle = .smart
    @AppStorage("engine") var engine: FormatEngine = .apple
    @AppStorage("ollamaModel") var ollamaModel: String = "gemma3:4b"
    @AppStorage("whisperModel") var whisperModel: String = Transcriber.models[0].id
    @AppStorage("language") var language: String = "en"
    @AppStorage("hotkey") var hotkey: Hotkey = .rightOption
    @AppStorage("restoreClipboard") var restoreClipboard: Bool = true
    @AppStorage("playSounds") var playSounds: Bool = true
    @AppStorage("autoPaste") var autoPaste: Bool = true
    @AppStorage("hasOnboarded") var hasOnboarded: Bool = false
    @AppStorage("vocabulary") var vocabularyRaw: String = ""
    @AppStorage("replacements") var replacementsData: Data = Data()

    var vocabulary: [String] {
        vocabularyRaw.split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var replacements: [Replacement] {
        get { (try? JSONDecoder().decode([Replacement].self, from: replacementsData)) ?? [] }
        set {
            replacementsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            objectWillChange.send()
        }
    }

    static let languages: [(code: String, name: String)] = [
        ("auto", "Auto-detect"), ("en", "English"), ("fr", "French"), ("es", "Spanish"),
        ("de", "German"), ("it", "Italian"), ("pt", "Portuguese"), ("nl", "Dutch"),
        ("ja", "Japanese"), ("zh", "Chinese"), ("ko", "Korean"), ("ar", "Arabic"), ("hi", "Hindi"),
    ]
}
