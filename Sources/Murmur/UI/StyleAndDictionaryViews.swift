import SwiftUI

struct StyleView: View {
    @EnvironmentObject var prefs: Preferences

    private let examples: [FormatStyle: String] = [
        .smart: "Picks Email in Mail, Message in Slack or Messages, and natural prose or lists everywhere else.",
        .clean: "“So um I think we should uh ship it friday” → “So I think we should ship it Friday.”",
        .polished: "Tightens rambling thoughts into clear sentences and paragraphs.",
        .notes: "“we need milk eggs and uh bread” →\n- Milk\n- Eggs\n- Bread",
        .email: "“hey sarah just wanted to follow up on the deck thanks” →\nHey Sarah,\n\nJust wanted to follow up on the deck.\n\nThanks!",
        .message: "“yeah sounds good see you at like seven” → “Yeah sounds good, see you at 7!”",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Style", subtitle: "How Murmur organizes what you say before pasting it.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(FormatStyle.allCases) { style in
                    styleCard(style)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Spoken commands", systemImage: "command").font(.headline)
                    Text("Say **“new line”** or **“new paragraph”** to break text. Correct yourself mid-sentence with **“no wait”** or **“actually”** and only the fix is kept. Say **“bullet point”** or list items naturally to get a list.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func styleCard(_ style: FormatStyle) -> some View {
        let selected = prefs.style == style
        return Button { prefs.style = style } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: style.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.gradient))
                        .frame(width: 32, height: 32)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.accent.opacity(0.1)))
                        }
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(.title3)
                    }
                }
                Text(style.title).font(.headline)
                Text(style.subtitle).font(.callout).foregroundStyle(.secondary)
                Text(examples[style] ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Color.secondary.opacity(0.2), lineWidth: selected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct DictionaryView: View {
    @EnvironmentObject var prefs: Preferences
    @State private var spoken = ""
    @State private var written = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Dictionary", subtitle: "Teach Murmur your names, jargon, and shortcuts.")

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Vocabulary", systemImage: "character.book.closed").font(.headline)
                    Text("Names and terms to always spell correctly. One per line or comma-separated.")
                        .font(.callout).foregroundStyle(.secondary)
                    TextEditor(text: $prefs.vocabularyRaw)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 110)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                    if prefs.engine == .rules {
                        Text("Vocabulary is applied by the AI formatter. Turn on Apple Intelligence or Ollama in Settings to use it.")
                            .font(.caption).foregroundStyle(Theme.warning)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Replacements", systemImage: "arrow.left.arrow.right").font(.headline)
                    Text("Whenever you say the phrase on the left, Murmur writes the text on the right. Great for emails, links, and signatures.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        TextField("When I say… (e.g. my email)", text: $spoken)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        TextField("Write… (e.g. me@example.com)", text: $written)
                        Button("Add") {
                            var list = prefs.replacements
                            list.append(Replacement(spoken: spoken.trimmingCharacters(in: .whitespaces),
                                                    written: written))
                            prefs.replacements = list
                            spoken = ""; written = ""
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                        .disabled(spoken.trimmingCharacters(in: .whitespaces).isEmpty || written.isEmpty)
                    }
                    .textFieldStyle(.roundedBorder)

                    if prefs.replacements.isEmpty {
                        Text("No replacements yet.").font(.callout).foregroundStyle(.tertiary).padding(.vertical, 6)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(prefs.replacements) { r in
                                HStack {
                                    Text(r.spoken).fontWeight(.medium)
                                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                                    Text(r.written).foregroundStyle(.secondary).lineLimit(1)
                                    Spacer()
                                    Button {
                                        prefs.replacements = prefs.replacements.filter { $0.id != r.id }
                                    } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                                        .buttonStyle(.plain)
                                }
                                .padding(.vertical, 8)
                                if r.id != prefs.replacements.last?.id { Divider() }
                            }
                        }
                    }
                }
            }
        }
    }
}
