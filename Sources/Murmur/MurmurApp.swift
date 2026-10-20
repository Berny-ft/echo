import AppKit
import SwiftUI


struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = AppDelegate.controller
    @StateObject private var prefs = Preferences.shared

    var body: some Scene {
        Window("Murmur", id: "main") {
            MainView()
                .environmentObject(controller)
                .environmentObject(prefs)
                .tint(Theme.accent)
        }
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 980, height: 700)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(controller)
                .environmentObject(prefs)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarSymbol: String {
        switch controller.phase {
        case .recording: "waveform.circle.fill"
        case .transcribing, .formatting: "ellipsis.circle"
        default: "waveform"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static let controller = DictationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppDelegate.controller.boot()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.identifier?.rawValue.contains("main") == true {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var controller: DictationController
    @EnvironmentObject var prefs: Preferences
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("Murmur").font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                StatusDot(color: controller.transcriber.status == .ready ? Theme.success : Theme.warning)
                Text(controller.transcriber.status == .ready ? "Ready" : controller.transcriber.status.label)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Button { controller.toggleFromUI() } label: {
                HStack {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    Text(isRecording ? "Finish dictation" : "Start dictation")
                    Spacer()
                    KeyCap(label: prefs.hotkey.short)
                }
                .padding(10)
                .foregroundStyle(.white)
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text("STYLE").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(FormatStyle.allCases) { style in
                        Button { prefs.style = style } label: {
                            VStack(spacing: 3) {
                                Image(systemName: style.symbol)
                                Text(style.title).font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(prefs.style == style ? Theme.accent.opacity(0.18) : Color.secondary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(prefs.style == style ? Theme.accent : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let last = controller.history.items.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LAST DICTATION").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    Text(last.formatted).font(.callout).lineLimit(3)
                    Button("Copy again") { Paster.copy(last.formatted) }.buttonStyle(.link).font(.caption)
                }
            }

            Divider()
            HStack {
                Button("Open Murmur") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
    }

    private var isRecording: Bool {
        if case .recording = controller.phase { return true }
        return false
    }
}
