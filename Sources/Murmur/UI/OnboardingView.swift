import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var controller: DictationController
    @EnvironmentObject var prefs: Preferences
    var onDone: () -> Void

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Theme.accent.opacity(0.4), radius: 12, y: 6)
                Text("Welcome to Murmur").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Speak naturally. Get clean, formatted text wherever you type. 100% on-device.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                step(1, title: "Microphone", detail: "So Murmur can hear you.", done: controller.micAuthorized) {
                    controller.requestMicrophone()
                }
                step(2, title: "Accessibility", detail: "For the hotkey in every app, and pasting for you.",
                     done: controller.accessibilityTrusted) {
                    controller.requestAccessibility()
                }
                modelStep
            }

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text("Then hold").foregroundStyle(.secondary)
                    KeyCap(label: prefs.hotkey.short)
                    Text("anywhere and start talking.").foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            Button(action: onDone) {
                Text(controller.micAuthorized ? "Start dictating" : "Skip for now")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 480)
        .onReceive(timer) { _ in controller.refreshPermissions() }
    }

    private var modelStep: some View {
        let status = controller.transcriber.status
        return HStack(spacing: 14) {
            badge(3, done: status == .ready)
            VStack(alignment: .leading, spacing: 4) {
                Text("Speech model").fontWeight(.semibold)
                if case .downloading(let p) = status {
                    ProgressView(value: p).tint(Theme.accent)
                    Text("Downloading Whisper once (\(Int(p * 100))%)…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(status == .ready ? "Whisper is loaded and ready." : status.label)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func step(_ n: Int, title: String, detail: String, done: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            badge(n, done: done)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !done {
                Button("Allow", action: action).buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func badge(_ n: Int, done: Bool) -> some View {
        ZStack {
            Circle().fill(done ? AnyShapeStyle(Theme.success) : AnyShapeStyle(Theme.accent.opacity(0.15)))
                .frame(width: 30, height: 30)
            if done {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            } else {
                Text("\(n)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.accent)
            }
        }
    }
}
