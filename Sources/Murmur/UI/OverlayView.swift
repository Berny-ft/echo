import AppKit
import SwiftUI

/// Floating, non-activating pill near the bottom of the screen that shows dictation state
/// without stealing focus from the app you're typing in.
@MainActor
final class OverlayController {
    static let shared = OverlayController()

    private var panel: NSPanel?
    private let size = NSSize(width: 340, height: 64)

    func show(controller: DictationController) {
        let panel = self.panel ?? makePanel(controller: controller)
        self.panel = panel
        position(panel)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
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
        panel.isMovableByWindowBackground = false
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
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 28))
    }
}

struct OverlayView: View {
    @EnvironmentObject var controller: DictationController

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            pill
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pill: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background {
            Capsule()
                .fill(Color.black.opacity(0.82))
                .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: controller.phase)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .recording(let handsFree):
            Circle().fill(Color.red).frame(width: 8, height: 8)
                .modifier(Pulse())
            Waveform(levels: controller.levels, color: AnyShapeStyle(Theme.gradient), maxHeight: 24)
            Text(timeString(controller.elapsed))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            if handsFree {
                Button { controller.finishRecording() } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Theme.gradient, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Finish (or tap your hotkey)")
            }
        case .transcribing:
            ProgressDots()
            Text("Transcribing").overlayLabel()
        case .formatting:
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.gradient)
                .symbolEffect(.pulse)
            Text("Polishing").overlayLabel()
        case .done(let message):
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
            Text(message).overlayLabel()
        case .error(let message):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            Text(message).overlayLabel()
        case .idle:
            Image(systemName: "waveform").foregroundStyle(.white.opacity(0.6))
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

private extension Text {
    func overlayLabel() -> some View {
        self.font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
    }
}

private struct Pulse: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever()) { on = true }
            }
    }
}

struct ProgressDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Theme.gradient)
                        .frame(width: 6, height: 6)
                        .offset(y: -3 * CGFloat(sin(t * 6 - Double(i) * 0.8)))
                }
            }
        }
        .frame(width: 26)
    }
}
