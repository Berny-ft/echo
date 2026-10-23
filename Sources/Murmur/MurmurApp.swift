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
        }
        .defaultSize(width: 820, height: 560)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(controller)
                .environmentObject(prefs)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarSymbol: String {
        switch controller.phase {
        case .recording: "record.circle"
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
}

struct MenuBarContent: View {
    @EnvironmentObject var controller: DictationController
    @EnvironmentObject var prefs: Preferences
    @Environment(\.openWindow) private var openWindow

    private var isRecording: Bool {
        if case .recording = controller.phase { return true }
        return false
    }

    var body: some View {
        Button(isRecording ? "Stop Dictation" : "Start Dictation") { controller.toggleFromUI() }
            .disabled(controller.phase == .transcribing || controller.phase == .formatting)
        Text(controller.transcriber.status == .ready
             ? "Hold \(prefs.hotkey.short) to dictate"
             : controller.transcriber.status.label)

        Divider()

        Picker("Style", selection: $prefs.style) {
            ForEach(FormatStyle.allCases) { Text($0.title).tag($0) }
        }
        Button("Copy Last Dictation") {
            if let last = controller.history.items.first { Paster.copy(last.formatted) }
        }
        .disabled(controller.history.items.isEmpty)

        Divider()

        Button("Open Murmur") {
            openWindow(id: "main")
            NSApp.activate()
        }
        .keyboardShortcut("o")

        Divider()

        Button("Quit Murmur") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
