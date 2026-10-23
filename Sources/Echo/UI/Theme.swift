import SwiftUI

/// Small keyboard-key badge, e.g. "Right ⌥".
struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Bar waveform driven by recent loudness values.
struct Waveform: View {
    let levels: [CGFloat]
    var barWidth: CGFloat = 2
    var spacing: CGFloat = 2
    var maxHeight: CGFloat = 14

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .frame(width: barWidth, height: max(barWidth, level * maxHeight))
            }
        }
        .frame(height: maxHeight)
        .animation(.easeOut(duration: 0.08), value: levels)
    }
}

extension Dictation {
    var metaLine: String {
        var parts = [date.formatted(.relative(presentation: .named))]
        if let appName { parts.append(appName) }
        parts.append(style.title)
        return parts.joined(separator: " · ")
    }
}
