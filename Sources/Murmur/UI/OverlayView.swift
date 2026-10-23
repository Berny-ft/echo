import AppKit
import SwiftUI

/// Floating, non-activating indicator near the bottom of the screen that shows dictation state
/// without stealing focus from the app you're typing in.
@MainActor
final class OverlayController {
    static let shared = OverlayController()

    private var panel: NSPanel?
    private let size = NSSize(width: 260, height: 44)

    func show(controller: DictationController) {
        let panel = self.panel ?? makePanel(controller: controller)
        self.panel = panel
        position(panel)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }

    private func makePanel(controller: DictationController) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: OverlayView().environmentObject(controller))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 20))
    }
}

struct OverlayView: View {
    @EnvironmentObject var controller: DictationController

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background {
            Capsule()
                .fill(Color(white: 0.1).opacity(0.92))
                .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.15), value: controller.phase)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .recording(let handsFree):
            Circle().fill(.red).frame(width: 6, height: 6)
            Waveform(levels: Array(controller.levels.suffix(18)))
                .foregroundStyle(.white.opacity(0.9))
            Text(timeString(controller.elapsed))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))
            if handsFree {
                Button { controller.finishRecording() } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 16, height: 16)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Finish dictation")
            }
        case .transcribing:
            ProgressView().controlSize(.mini)
            Text("Transcribing")
        case .formatting:
            ProgressView().controlSize(.mini)
            Text("Formatting")
        case .done(let message):
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
            Text(message)
        case .error(let message):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(message).lineLimit(1)
        case .idle:
            EmptyView()
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}
