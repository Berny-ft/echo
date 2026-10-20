import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var controller: DictationController
    @EnvironmentObject var prefs: Preferences
    @Binding var showOnboarding: Bool
    @State private var ollamaModels: [String] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Settings")

            group("Shortcut", symbol: "keyboard") {
                row("Dictation key", detail: "Hold to talk, tap once for hands-free, Esc to cancel.") {
                    Picker("", selection: $prefs.hotkey) {
                        ForEach(Hotkey.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 200)
                    .onChange(of: prefs.hotkey) { controller.applyHotkey() }
                }
                if prefs.hotkey == .fn {
                    Text("Tip: set System Settings › Keyboard › “Press 🌐 key to” → Do Nothing, so macOS doesn't open the emoji picker.")
                        .font(.caption).foregroundStyle(Theme.warning)
                }
            }

            group("Speech recognition", symbol: "waveform") {
                VStack(spacing: 8) {
                    ForEach(Transcriber.models) { model in
                        modelRow(model)
                    }
                }
                row("Language", detail: "Pick your language for best accuracy, or auto-detect.") {
                    Picker("", selection: $prefs.language) {
                        ForEach(Preferences.languages, id: \.code) { Text($0.name).tag($0.code) }
                    }
                    .labelsHidden().frame(width: 200)
                }
                if prefs.language != "en" && prefs.language != "auto" && prefs.whisperModel.hasSuffix(".en") {
                    Text("English-only models can't transcribe other languages. Choose Large v3 Turbo.")
                        .font(.caption).foregroundStyle(Theme.warning)
                }
            }

            group("Formatting", symbol: "sparkles") {
                VStack(spacing: 8) {
                    ForEach(FormatEngine.allCases) { engine in
                        engineRow(engine)
                    }
                }
                if prefs.engine == .ollama {
                    row("Ollama model", detail: ollamaModels.isEmpty ? "Ollama isn't running. Start it with `ollama serve`." : "Smaller models are faster.") {
                        HStack {
                            if ollamaModels.isEmpty {
                                TextField("model", text: $prefs.ollamaModel).frame(width: 160)
                            } else {
                                Picker("", selection: $prefs.ollamaModel) {
                                    ForEach(ollamaModels, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden().frame(width: 160)
                            }
                            Button { Task { ollamaModels = await TextFormatter.ollamaModels() } } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                }
            }

            group("Behavior", symbol: "slider.horizontal.3") {
                Toggle("Paste automatically into the active app", isOn: $prefs.autoPaste)
                Toggle("Restore my clipboard after pasting", isOn: $prefs.restoreClipboard)
                Toggle("Play start and stop sounds", isOn: $prefs.playSounds)
                Toggle("Launch Murmur at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            group("Permissions", symbol: "lock.shield") {
                permissionRow("Microphone", granted: controller.micAuthorized, detail: "To hear your voice.") {
                    controller.requestMicrophone()
                }
                permissionRow("Accessibility", granted: controller.accessibilityTrusted, detail: "For the global hotkey and auto-paste.") {
                    controller.requestAccessibility()
                }
                Button("Run setup again") { showOnboarding = true }.buttonStyle(.link)
            }

            Text("Everything runs on this Mac. Audio and text never leave your computer.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .task { ollamaModels = await TextFormatter.ollamaModels() }
    }

    // MARK: - Building blocks

    private func group<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label(title, systemImage: symbol).font(.headline)
                content()
            }
        }
    }

    private func row<Trailing: View>(_ title: String, detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
    }

    private func selectableRow<Badge: View>(selected: Bool, title: String, detail: String, action: @escaping () -> Void,
                                            @ViewBuilder badge: () -> Badge) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.medium)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                badge()
            }
            .padding(10)
            .background(selected ? Theme.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func modelRow(_ model: WhisperModelOption) -> some View {
        let selected = prefs.whisperModel == model.id
        return selectableRow(selected: selected, title: model.name, detail: "\(model.detail) \(model.size).", action: {
            prefs.whisperModel = model.id
            controller.transcriber.load(model: model.id)
        }) {
            if selected {
                Text(controller.transcriber.status == .ready ? "Loaded" : controller.transcriber.status.label)
                    .font(.caption).foregroundStyle(controller.transcriber.status == .ready ? Theme.success : .secondary)
                    .lineLimit(1)
            } else if controller.transcriber.isDownloaded(model.id) {
                Text("Downloaded").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func engineRow(_ engine: FormatEngine) -> some View {
        let selected = prefs.engine == engine
        return selectableRow(selected: selected, title: engine.title, detail: engine.subtitle, action: {
            prefs.engine = engine
            if engine == .ollama { TextFormatter.warmOllama(model: prefs.ollamaModel) }
        }) {
            switch engine {
            case .apple:
                Text(TextFormatter.appleModelStatus)
                    .font(.caption)
                    .foregroundStyle(TextFormatter.appleModelAvailable ? Theme.success : Theme.warning)
                    .lineLimit(2).multilineTextAlignment(.trailing).frame(maxWidth: 180, alignment: .trailing)
            case .ollama:
                Text(ollamaModels.isEmpty ? "Not running" : "\(ollamaModels.count) models")
                    .font(.caption).foregroundStyle(ollamaModels.isEmpty ? Theme.warning : Theme.success)
            case .rules:
                EmptyView()
            }
        }
    }

    private func permissionRow(_ title: String, granted: Bool, detail: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? Theme.success : Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Grant", action: action) }
        }
    }
}
