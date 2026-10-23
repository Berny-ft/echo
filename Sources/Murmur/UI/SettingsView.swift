import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var controller: DictationController
    @EnvironmentObject var prefs: Preferences
    @Binding var showOnboarding: Bool
    @State private var ollamaModels: [String] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Picker("Dictation key", selection: $prefs.hotkey) {
                    ForEach(Hotkey.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: prefs.hotkey) { controller.applyHotkey() }
            } header: {
                Text("Shortcut")
            } footer: {
                Text(prefs.hotkey == .fn
                     ? "Hold to talk, tap once for hands-free, Esc to cancel. Set System Settings › Keyboard › “Press 🌐 key to” to Do Nothing."
                     : "Hold to talk, tap once for hands-free, Esc to cancel.")
                    .foregroundStyle(.secondary)
            }

            Section("Speech recognition") {
                Picker("Model", selection: $prefs.whisperModel) {
                    ForEach(Transcriber.models) { model in
                        Text("\(model.name) — \(model.size)").tag(model.id)
                    }
                }
                .onChange(of: prefs.whisperModel) { _, model in controller.transcriber.load(model: model) }
                LabeledContent("Status") {
                    HStack(spacing: 8) {
                        if case .downloading(let p) = controller.transcriber.status {
                            ProgressView(value: p).frame(width: 80)
                        }
                        Text(controller.transcriber.status.label)
                            .foregroundStyle(controller.transcriber.status.isFailure ? .red : .secondary)
                    }
                }
                Picker("Language", selection: $prefs.language) {
                    ForEach(Preferences.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                if prefs.language != "en" && prefs.language != "auto" && prefs.whisperModel.hasSuffix(".en") {
                    Text("English-only models can't transcribe other languages. Choose Whisper Large v3 Turbo.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section {
                Picker("Engine", selection: $prefs.engine) {
                    ForEach(FormatEngine.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: prefs.engine) { _, engine in
                    TextFormatter.prewarm(engine: engine, ollamaModel: prefs.ollamaModel)
                }
                switch prefs.engine {
                case .apple:
                    LabeledContent("Status", value: TextFormatter.appleModelStatus)
                case .ollama:
                    if ollamaModels.isEmpty {
                        LabeledContent("Status") {
                            HStack {
                                Text("Ollama isn't running").foregroundStyle(.secondary)
                                Button("Retry") { Task { ollamaModels = await TextFormatter.ollamaModels() } }
                            }
                        }
                    } else {
                        Picker("Model", selection: $prefs.ollamaModel) {
                            ForEach(ollamaModels, id: \.self) { Text($0).tag($0) }
                        }
                    }
                case .rules:
                    EmptyView()
                }
            } header: {
                Text("Formatting")
            } footer: {
                Text(prefs.engine.subtitle).foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Paste into the active app", isOn: $prefs.autoPaste)
                Toggle("Restore clipboard after pasting", isOn: $prefs.restoreClipboard)
                Toggle("Play sounds", isOn: $prefs.playSounds)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section {
                permissionRow("Microphone", granted: controller.micAuthorized) { controller.requestMicrophone() }
                permissionRow("Accessibility", granted: controller.accessibilityTrusted) { controller.requestAccessibility() }
            } header: {
                Text("Permissions")
            } footer: {
                HStack {
                    Text("Audio and text never leave this Mac.")
                    Spacer()
                    Button("Show Setup…") { showOnboarding = true }.buttonStyle(.link)
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { ollamaModels = await TextFormatter.ollamaModels() }
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
            } else {
                Button("Grant…", action: action)
            }
        }
    }
}
