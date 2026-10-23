import SwiftUI

struct DictionaryView: View {
    @EnvironmentObject var prefs: Preferences
    @State private var spoken = ""
    @State private var written = ""

    private var canAdd: Bool {
        !spoken.trimmingCharacters(in: .whitespaces).isEmpty && !written.isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $prefs.vocabularyRaw)
                    .font(.body)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
            } header: {
                Text("Vocabulary")
            } footer: {
                Text(prefs.engine == .rules
                     ? "Vocabulary is applied by the AI formatter, which is turned off in Settings."
                     : "Names and terms to always spell correctly. One per line or separated by commas.")
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(prefs.replacements) { r in
                    LabeledContent(r.spoken) {
                        HStack {
                            Text(r.written).lineLimit(1)
                            Button {
                                prefs.replacements = prefs.replacements.filter { $0.id != r.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove")
                        }
                    }
                }
                HStack {
                    TextField("When I say", text: $spoken, prompt: Text("my email"))
                    TextField("Write", text: $written, prompt: Text("name@example.com"))
                    Button("Add", action: add)
                        .disabled(!canAdd)
                }
                .labelsHidden()
                .onSubmit { if canAdd { add() } }
            } header: {
                Text("Replacements")
            } footer: {
                Text("When you say the phrase on the left, Echo writes the text on the right.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        prefs.replacements = prefs.replacements + [
            Replacement(spoken: spoken.trimmingCharacters(in: .whitespaces), written: written)
        ]
        spoken = ""
        written = ""
    }
}
