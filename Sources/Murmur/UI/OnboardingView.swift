import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var controller: DictationController
    @EnvironmentObject var prefs: Preferences
    var onDone: () -> Void

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set up Murmur").font(.title3.weight(.semibold))
                    Text("Dictation that runs entirely on this Mac.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(spacing: 0) {
                    row("Microphone", detail: "Required to hear you.", done: controller.micAuthorized) {
                        controller.requestMicrophone()
                    }
                    Divider()
                    row("Accessibility", detail: "For the shortcut in any app and automatic pasting.",
                        done: controller.accessibilityTrusted) {
                        controller.requestAccessibility()
                    }
                    Divider()
                    modelRow
                }
            }

            HStack(spacing: 4) {
                Text("Then hold")
                KeyCap(label: prefs.hotkey.short)
                Text("in any app and start speaking.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(controller.micAuthorized ? "Done" : "Later", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onReceive(timer) { _ in controller.refreshPermissions() }
    }

    private var modelRow: some View {
        let status = controller.transcriber.status
        return HStack(spacing: 10) {
            statusIcon(done: status == .ready)
            VStack(alignment: .leading, spacing: 2) {
                Text("Speech model")
                if case .downloading(let p) = status {
                    ProgressView(value: p).controlSize(.small)
                    Text("Downloading Whisper (one time)… \(Int(p * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(status == .ready ? "Whisper is ready." : status.label)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(8)
    }

    private func row(_ title: String, detail: String, done: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            statusIcon(done: done)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !done { Button("Allow…", action: action) }
        }
        .padding(8)
    }

    private func statusIcon(done: Bool) -> some View {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(done ? Color.green : Color.secondary)
            .font(.system(size: 15))
    }
}
