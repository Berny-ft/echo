import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case home, history, style, dictionary, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .history: "History"
        case .style: "Style"
        case .dictionary: "Dictionary"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .history: "clock"
        case .style: "textformat"
        case .dictionary: "book.closed"
        case .settings: "gearshape"
        }
    }
}

struct MainView: View {
    @EnvironmentObject var controller: DictationController
    @EnvironmentObject var prefs: Preferences
    @State private var pane: Pane? = .home
    @State private var showOnboarding = false

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                Label(p.title, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 176, max: 220)
            .safeAreaInset(edge: .bottom) { modelStatus }
        } detail: {
            Group {
                switch pane ?? .home {
                case .home: HomeView(pane: $pane)
                case .history: HistoryView()
                case .style: StyleView()
                case .dictionary: DictionaryView()
                case .settings: SettingsView(showOnboarding: $showOnboarding)
                }
            }
            .navigationTitle((pane ?? .home).title)
        }
        .frame(minWidth: 680, minHeight: 460)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView { showOnboarding = false; prefs.hasOnboarded = true }
                .environmentObject(controller)
                .environmentObject(prefs)
        }
        .onAppear {
            controller.refreshPermissions()
            if !prefs.hasOnboarded || !controller.micAuthorized { showOnboarding = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshPermissions()
        }
    }

    private var modelStatus: some View {
        let status = controller.transcriber.status
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(status == .ready ? Color.green : status.isFailure ? .red : .orange)
                    .frame(width: 6, height: 6)
                Text(status == .ready ? "Model ready" : status.label)
                    .lineLimit(1)
            }
            if case .downloading(let p) = status {
                ProgressView(value: p).controlSize(.small)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

extension Transcriber.Status {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject var controller: DictationController
    @EnvironmentObject var prefs: Preferences
    @Binding var pane: Pane?

    private var isRecording: Bool {
        if case .recording = controller.phase { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if !controller.micAuthorized || !controller.accessibilityTrusted { permissionNotice }
                stats
                recent
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(statusTitle)
                    .font(.title2.weight(.semibold))
                HStack(spacing: 4) {
                    Text("Hold")
                    KeyCap(label: prefs.hotkey.short)
                    Text("to dictate. Tap once for hands-free.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                Text("\(prefs.style.title) style · \(prefs.engine.title)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button { controller.toggleFromUI() } label: {
                Label(isRecording ? "Stop" : "Dictate", systemImage: isRecording ? "stop.fill" : "mic")
                    .frame(minWidth: 72)
            }
            .controlSize(.large)
            .disabled(controller.phase == .transcribing || controller.phase == .formatting)
        }
    }

    private var statusTitle: String {
        switch controller.phase {
        case .recording: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .formatting: return "Formatting…"
        default:
            switch controller.transcriber.status {
            case .ready: return "Ready"
            case .failed: return "Speech model failed to load"
            default: return "Preparing speech model…"
            }
        }
    }

    private var permissionNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(!controller.micAuthorized
                 ? "Microphone access is required to dictate."
                 : "Grant Accessibility access to use the shortcut in other apps and paste automatically.")
                .font(.callout)
            Spacer()
            Button(!controller.micAuthorized ? "Allow…" : "Open Settings…") {
                if !controller.micAuthorized { controller.requestMicrophone() } else { controller.requestAccessibility() }
            }
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var stats: some View {
        GroupBox {
            HStack(spacing: 0) {
                stat("\(controller.history.totalWords.formatted())", "Words")
                Divider().frame(height: 30)
                stat("\(controller.history.averageWPM)", "Words per minute")
                Divider().frame(height: 30)
                stat("\(controller.history.minutesSaved) min", "Time saved")
                Divider().frame(height: 30)
                stat("\(controller.history.todayCount)", "Today")
            }
            .padding(.vertical, 4)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent").font(.headline)
                Spacer()
                if !controller.history.items.isEmpty {
                    Button("Show All") { pane = .history }
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }
            if controller.history.items.isEmpty {
                Text("Dictations appear here. Click into any text field, hold \(prefs.hotkey.short), and speak.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                GroupBox {
                    VStack(spacing: 0) {
                        let items = Array(controller.history.items.prefix(5))
                        ForEach(items) { item in
                            DictationRow(item: item)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                            if item.id != items.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Dictation row

struct DictationRow: View {
    @EnvironmentObject var controller: DictationController
    let item: Dictation
    @State private var hovering = false
    @State private var showOriginal = false
    @State private var copied = false
    @State private var rewriting = false
    @State private var rewritten: String?

    private var text: String { rewritten ?? item.formatted }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .lineLimit(showOriginal ? nil : 3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(rewriting ? "Rewriting…" : item.metaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if showOriginal {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Original transcript").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text(item.raw).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        Text("\(item.engine) · \(String(format: "%.0fs", item.duration)) of speech · \(item.wordCount) words")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.top, 4)
                }
            }
            HStack(spacing: 2) {
                Button { copy() } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .help("Copy")
                Menu {
                    menuItems
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .buttonStyle(.borderless)
            .opacity(hovering || copied ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { menuItems }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Copy") { copy() }
        Button("Copy Original Transcript") { Paster.copy(item.raw) }
        Menu("Rewrite As") {
            ForEach(FormatStyle.allCases.filter { $0 != .smart }) { style in
                Button(style.title) { rewrite(style) }
            }
        }
        Button(showOriginal ? "Hide Original" : "Show Original") { showOriginal.toggle() }
        Divider()
        Button("Delete", role: .destructive) { controller.history.delete(item) }
    }

    private func copy() {
        Paster.copy(text)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }

    private func rewrite(_ style: FormatStyle) {
        rewriting = true
        Task {
            rewritten = await controller.reformat(item, style: style)
            rewriting = false
        }
    }
}

// MARK: - History

struct HistoryView: View {
    @EnvironmentObject var controller: DictationController
    @State private var query = ""
    @State private var confirmClear = false

    private var filtered: [Dictation] {
        guard !query.isEmpty else { return controller.history.items }
        return controller.history.items.filter {
            $0.formatted.localizedCaseInsensitiveContains(query) || $0.raw.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            ForEach(filtered) { item in
                DictationRow(item: item).padding(.vertical, 4)
            }
        }
        .listStyle(.inset)
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No Dictations" : "No Results",
                    systemImage: query.isEmpty ? "waveform" : "magnifyingglass",
                    description: Text(query.isEmpty ? "Everything you dictate is kept here, on this Mac only." : "Try a different search.")
                )
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search")
        .toolbar {
            ToolbarItem {
                Button("Clear History", systemImage: "trash") { confirmClear = true }
                    .disabled(controller.history.items.isEmpty)
            }
        }
        .confirmationDialog("Clear all history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { controller.history.clear() }
        } message: {
            Text("This can't be undone.")
        }
    }
}
