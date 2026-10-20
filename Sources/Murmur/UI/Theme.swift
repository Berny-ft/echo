import SwiftUI

enum Theme {
    static let accent = Color(red: 0.40, green: 0.33, blue: 0.96)
    static let accent2 = Color(red: 0.86, green: 0.38, blue: 0.82)
    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let success = Color(red: 0.20, green: 0.75, blue: 0.48)
    static let warning = Color(red: 0.98, green: 0.62, blue: 0.20)
}

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.6), radius: 3)
    }
}

struct KeyCap: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.08), radius: 0, y: 1)
    }
}

/// Animated bar waveform driven by recent loudness values.
struct Waveform: View {
    let levels: [CGFloat]
    var color: AnyShapeStyle = AnyShapeStyle(Color.white)
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2.5
    var maxHeight: CGFloat = 22

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                // Taper the edges so the shape reads as a soft blob.
                let edge = CGFloat(min(index, levels.count - 1 - index)) / CGFloat(max(levels.count / 2, 1))
                let taper = 0.45 + 0.55 * min(1, edge * 1.6)
                Capsule()
                    .fill(color)
                    .frame(width: barWidth, height: max(barWidth, level * maxHeight * taper + 3))
            }
        }
        .frame(height: maxHeight)
        .animation(.easeOut(duration: 0.08), value: levels)
    }
}
