import SwiftUI

struct StyleView: View {
    @EnvironmentObject var prefs: Preferences

    private let examples: [FormatStyle: (said: String, written: String)] = [
        .smart: ("so the plan is first fix the login bug second update the docs and then ship it",
                 "The plan is:\n1. Fix the login bug\n2. Update the docs\n3. Ship it"),
        .clean: ("so um I think we should uh ship it on friday",
                 "So I think we should ship it on Friday."),
        .polished: ("I was thinking that maybe we could possibly move the meeting because a lot of people are out",
                    "Could we move the meeting? A lot of people are out."),
        .notes: ("for groceries we need milk eggs and bread and also call mom about sunday",
                 "- Groceries\n  - Milk\n  - Eggs\n  - Bread\n- Call Mom about Sunday"),
        .email: ("hey sarah just following up on the deck can you send it by friday thanks",
                 "Hey Sarah,\n\nJust following up on the deck. Can you send it by Friday?\n\nThanks!"),
        .message: ("yeah sounds good see you at like seven",
                   "Yeah sounds good, see you at 7!"),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Style", selection: $prefs.style) {
                    ForEach(FormatStyle.allCases) { style in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(style.title)
                            Text(style.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            } header: {
                Text("Default style")
            } footer: {
                Text("Smart uses Email in mail apps and Message in chat apps such as Slack and Messages.")
                    .foregroundStyle(.secondary)
            }

            if let example = examples[prefs.style] {
                Section("Example") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You say").font(.caption).foregroundStyle(.secondary)
                        Text("“\(example.said)”").foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Murmur writes").font(.caption).foregroundStyle(.secondary)
                        Text(example.written).textSelection(.enabled)
                    }
                }
            }

            Section("Spoken commands") {
                LabeledContent("“new line”, “new paragraph”", value: "Inserts a break")
                LabeledContent("“no wait”, “actually”", value: "Replaces what you just said")
                LabeledContent("“scratch that”", value: "Removes the previous sentence")
            }
        }
        .formStyle(.grouped)
    }
}
