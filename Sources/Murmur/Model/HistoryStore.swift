import Foundation

struct Dictation: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var raw: String
    var formatted: String
    var appName: String?
    var style: FormatStyle
    var engine: String
    var duration: TimeInterval

    var wordCount: Int { formatted.split(whereSeparator: { $0.isWhitespace }).count }
}

/// Persists dictation history as JSON in Application Support.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [Dictation] = []

    private let url = Transcriber.storageRoot.appendingPathComponent("history.json")
    private let limit = 500

    init() {
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = (try? decoder.decode([Dictation].self, from: data)) ?? []
        }
    }

    func add(_ item: Dictation) {
        items.insert(item, at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
        save()
    }

    func delete(_ item: Dictation) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    var totalWords: Int { items.reduce(0) { $0 + $1.wordCount } }

    var averageWPM: Int {
        let spoken = items.filter { $0.duration > 1 }
        let minutes = spoken.reduce(0) { $0 + $1.duration } / 60
        guard minutes > 0 else { return 0 }
        return Int(Double(spoken.reduce(0) { $0 + $1.wordCount }) / minutes)
    }

    /// Typing at ~40 WPM vs. speaking: minutes saved.
    var minutesSaved: Int {
        let typingMinutes = Double(totalWords) / 40
        let speakingMinutes = items.reduce(0) { $0 + $1.duration } / 60
        return max(0, Int(typingMinutes - speakingMinutes))
    }

    var todayCount: Int {
        items.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    /// Days in a row (ending today or yesterday) with at least one dictation.
    var streak: Int {
        let cal = Calendar.current
        let days = Set(items.map { cal.startOfDay(for: $0.date) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while days.contains(day) {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
