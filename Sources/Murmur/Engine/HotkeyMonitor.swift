import AppKit

/// Watches a single modifier key system-wide.
/// Hold it to talk (push-to-talk); tap it quickly to start hands-free mode, tap again to finish.
/// Esc cancels an active recording.
@MainActor
final class HotkeyMonitor {
    var hotkey: Hotkey = .rightOption

    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?
    /// Called when a hold turns into hands-free mode.
    var onHandsFree: (() -> Void)?

    private var monitors: [Any] = []
    private var isDown = false
    private var downAt: Date?
    private var active = false
    private var handsFree = false
    private var otherKeyPressedDuringHold = false

    private let tapThreshold: TimeInterval = 0.28

    func start() {
        stop()
        let flagsHandler: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handleFlags(event) }
        }
        let keyHandler: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handleKeyDown(event) }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flagsHandler) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: keyHandler) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { flagsHandler($0); return $0 }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { keyHandler($0); return $0 }) { monitors.append(m) }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    /// Lets the app end a session it started some other way (button, menu), keeping state in sync.
    func reset() {
        active = false
        handsFree = false
        isDown = false
        downAt = nil
    }

    func beginExternally() {
        active = true
        handsFree = true
    }

    private func handleFlags(_ event: NSEvent) {
        guard event.keyCode == hotkey.keyCode else { return }
        let pressed = event.modifierFlags.contains(hotkey.flag)

        if pressed, !isDown {
            isDown = true
            downAt = Date()
            otherKeyPressedDuringHold = false
            if active, handsFree {
                // Second tap ends hands-free mode.
                active = false
                handsFree = false
                onStop?()
            } else if !active {
                active = true
                onStart?()
            }
        } else if !pressed, isDown {
            isDown = false
            let held = Date().timeIntervalSince(downAt ?? Date())
            guard active else { return }
            if otherKeyPressedDuringHold {
                // The modifier was used as part of a shortcut, not to dictate.
                active = false
                onCancel?()
            } else if held < tapThreshold {
                handsFree = true
                onHandsFree?()
            } else {
                active = false
                onStop?()
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 53, active { // Esc
            active = false
            handsFree = false
            onCancel?()
            return
        }
        if isDown, active, !handsFree {
            otherKeyPressedDuringHold = true
        }
    }
}
