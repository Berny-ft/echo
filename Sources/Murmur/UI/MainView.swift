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
        case .history: "clock.arrow.circlepath"
        case .style: "textformat"
        case .dictionary: "character.book.closed"
        case .settings: "gearshape"
        }
    }
}

struct MainView: View {
    @EnvironmentObject var controller: DictationController
    @EnvironmentObject var prefs: Preferences
    @State private var pane: Pane = .home
    @State private var showOnboarding = false

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                Label(p.title, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .top) { brand }
            .safeAreaInset(edge: .bottom) { sidebarStatus }
        } detail: {
            ScrollView {
                Group {
                    switch pane {
                    case .home: HomeView(pane: $pane)
                    case .history: HistoryView()
                    case .style: StyleView()
                    case .dictionary: DictionaryView()
                    case .settings: SettingsView(showOnboarding: $showOnboarding)
                    }
                }
                .padding(28)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .background(.background)
        }
        .frame(minWidth: 820, minHeight: 580)
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

    private var brand: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text("Murmur").font(.system(size: 17, weight: .bold, design: .rounded))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var sidebarStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StatusDot(color: modelColor)
                Text(controller.transcriber.status == .ready ? "Speech model ready" : controller.transcriber.status.label)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if case .downloading(let p) = controller.transcriber.status {
                ProgressView(value: p).progressViewStyle(.linear).tint(Theme.accent)
            }
        }
        .padding(14)
    }

    private var modelColor: Color {
        switch controller.transcriber.status {
        case .ready: Theme.success
        case .failed: .red
        default: Theme.warning
        }
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject var controller: DictationController
    @EnvironmentObject var prefs: Preferences
    @Binding var pane: Pane

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            hero
            if !controller.micAuthorized || !controller.accessibilityTrusted { permissionBanner }
            stats
            recent
        }
    }

    private var hero: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(greeting).font(.system(size: 30, weight: .bold, design: .rounded))
                HStack(spacing: 6) {
                    Text("Hold").foregroundStyle(.secondary)
                    KeyCap(label: prefs.hotkey.short)
                    Text("and speak. Tap it once for hands-free.").foregroundStyle(.secondary)
                }
                .font(.callout)
                HStack(spacing: 8) {
                    chip(prefs.style.title, symbol: prefs.style.symbol) { pane = .style }
                    chip(prefs.engine.title, symbol: "cpu") { pane = .settings }
                }
                .padding(.top, 4)
            }
            Spacer()
            MicButton()
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.gradient.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.accent.opacity(0.18)))
        }
    }

    private func chip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.background, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator))
        }
        .buttonStyle(.plain)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }

    private var permissionBanner: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield").font(.title2).foregroundStyle(Theme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finish setup").font(.headline)
                    Text(!controller.micAuthorized
                         ? "Murmur needs microphone access to hear you."
                         : "Grant Accessibility so Murmur can use your hotkey anywhere and paste for you.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(!controller.micAuthorized ? "Allow Microphone" : "Open Accessibility") {
                    if !controller.micAuthorized { controller.requestMicrophone() } else { controller.requestAccessibility() }
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 14) {
            StatTile(value: "\(controller.history.totalWords)", label: "Words dictated", symbol: "text.word.spacing")
            StatTile(value: "\(controller.history.averageWPM)", label: "Avg. words / min", symbol: "speedometer")
            StatTile(value: "\(controller.history.minutesSaved)m", label: "Time saved", symbol: "hourglass")
            StatTile(value: "\(controller.history.streak)", label: "Day streak", symbol: "flame")
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent").font(.title3.weight(.semibold))
                Spacer()
                if !controller.history.items.isEmpty {
                    Button("See all") { pane = .history }.buttonStyle(.link)
                }
            }
            if controller.history.items.isEmpty {
                Card {
                    VStack(spacing: 10) {
                        Image(systemName: "waveform.badge.mic").font(.system(size: 34)).foregroundStyle(Theme.gradient)
                        Text("Your dictations will show up here").font(.headline)
                        Text("Click into any text field, hold \(prefs.hotkey.short), and talk naturally. Murmur cleans it up and pastes it for you.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }
            } else {
                ForEach(controller.history.items.prefix(4)) { item in
                    DictationRow(item: item)
                }
            }
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).foregroundStyle(Theme.gradient).font(.system(size: 15, weight: .semibold))
                Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).contentTransition(.numericText())
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct MicButton: View {
    @EnvironmentObject var controller: DictationController
    @State private var hover = false

    private var recording: Bool {
        if case .recording = controller.phase { return true }
        return false
    }

    var body: some View {
        Button { controller.toggleFromUI() } label: {
            ZStack {
                Circle()
                    .fill(Theme.gradient)
                    .frame(width: 84, height: 84)
                    .shadow(color: Theme.accent.opacity(hover ? 0.55 : 0.35), radius: hover ? 18 : 12, y: 6)
                if recording {
                    Waveform(levels: Array(controller.levels.suffix(9)), barWidth: 4, spacing: 3, maxHeight: 30)
                } else if controller.phase == .transcribing || controller.phase == .formatting {
                    ProgressView().controlSize(.regular).tint(.white)
                } else {
                    Image(systemName: "mic.fill").font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .scaleEffect(hover ? 1.04 : 1)
            .animation(.spring(response: 0.3), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(recording ? "Finish dictation" : "Start a hands-free dictation (copies to clipboard)")
    }
}

// MARK: - History

struct DictationRow: View {
    @EnvironmentObject var controller: DictationController
    let item: Dictation
    @State private var expanded = false
    @State private var copied = false
    @State private var reformatting = false
    @State private var override: String?

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(item.style.title, systemImage: item.style.symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accent)
                    if let app = item.appName {
                        Text("· \(app)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.tertiary)
                }
                Text(override ?? item.formatted)
                    .font(.body)
                    .textSelection(.enabled)
                    .lineLimit(expanded ? nil : 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if expanded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ORIGINAL TRANSCRIPT").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                        Text(item.raw).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        Text("\(item.engine) · \(String(format: "%.1fs", item.duration)) · \(item.wordCount) words")
                            .font(.caption2).foregroundStyle(.tertiary).padding(.top, 2)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                }
                HStack(spacing: 14) {
                    Button { Paster.copy(override ?? item.formatted); flashCopied() } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    Menu {
                        ForEach(FormatStyle.allCases.filter { $0 != .smart }) { style in
                            Button { reformat(style) } label: { Label(style.title, systemImage: style.symbol) }
                        }
                    } label: {
                        Label(reformatting ? "Rewriting…" : "Rewrite as", systemImage: "wand.and.stars")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(reformatting)
                    Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                        Label(expanded ? "Less" : "Details", systemImage: expanded ? "chevron.up" : "chevron.down")
                    }
                    Spacer()
                    Button(role: .destructive) { controller.history.delete(item) } label: { Image(systemName: "trash") }
                        .help("Delete")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func flashCopied() {
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }

    private func reformat(_ style: FormatStyle) {
        reformatting = true
        Task {
            let text = await controller.reformat(item, style: style)
            override = text
            reformatting = false
        }
    }
}

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
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                SectionHeader(title: "History", subtitle: "\(controller.history.items.count) dictations, stored only on this Mac.")
                Spacer()
                if !controller.history.items.isEmpty {
                    Button("Clear all", role: .destructive) { confirmClear = true }
                }
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search dictations", text: $query).textFieldStyle(.plain)
            }
            .padding(10)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))

            if filtered.isEmpty {
                Text(query.isEmpty ? "Nothing yet." : "No matches.").foregroundStyle(.secondary).padding(.top, 20)
            }
            LazyVStack(spacing: 10) {
                ForEach(filtered) { DictationRow(item: $0) }
            }
        }
        .confirmationDialog("Delete all history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { controller.history.clear() }
        }
    }
}
