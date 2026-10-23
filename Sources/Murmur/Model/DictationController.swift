import AppKit
import AVFoundation
import Combine
import SwiftUI

/// Orchestrates one dictation: hotkey → record → transcribe → format → paste.
@MainActor
final class DictationController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording(handsFree: Bool)
        case transcribing
        case formatting
        case done(String)
        case error(String)

        var isBusy: Bool {
            switch self {
            case .recording, .transcribing, .formatting: true
            default: false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    /// Recent loudness values for the waveform, newest last.
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: 28)
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var targetAppName: String?
    @Published private(set) var micAuthorized = false
    @Published private(set) var accessibilityTrusted = false

    let prefs = Preferences.shared
    let transcriber = Transcriber()
    let history = HistoryStore()
    private let recorder = AudioRecorder()
    private let hotkeys = HotkeyMonitor()

    private var startedAt: Date?
    private var targetApp: NSRunningApplication?
    private var timer: Timer?
    private var pendingLevel: Float = 0
    private var levelLock = NSLock()
    private var cancellables = Set<AnyCancellable>()
    private var resetWork: DispatchWorkItem?
    private var sessionID = UUID()
    private var permissionPoll: Timer?
    private var chunkTasks: [Task<String, Error>] = []
    private var sessionLanguage: String?
    static let chunkSeconds: TimeInterval = 60

    init() {
        recorder.onLevel = { [weak self] level in
            guard let self else { return }
            self.levelLock.withLock { self.pendingLevel = max(self.pendingLevel, level) }
        }
        hotkeys.onStart = { [weak self] in self?.startRecording(handsFree: false) }
        hotkeys.onStop = { [weak self] in self?.finishRecording() }
        hotkeys.onCancel = { [weak self] in self?.cancel() }
        hotkeys.onHandsFree = { [weak self] in
            guard let self, case .recording = self.phase else { return }
            self.phase = .recording(handsFree: true)
        }
        transcriber.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        history.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func boot() {
        refreshPermissions()
        hotkeys.hotkey = prefs.hotkey
        hotkeys.start()
        transcriber.load(model: prefs.whisperModel)
        TextFormatter.prewarm(engine: prefs.engine, ollamaModel: prefs.ollamaModel)
    }

    func applyHotkey() {
        hotkeys.hotkey = prefs.hotkey
        hotkeys.start()
    }

    // MARK: - Permissions

    func refreshPermissions() {
        micAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let trusted = AXIsProcessTrusted()
        if trusted, !accessibilityTrusted {
            // Global key monitors only receive events once trusted; re-register them.
            hotkeys.start()
        }
        accessibilityTrusted = trusted
        if !trusted, permissionPoll == nil {
            permissionPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.refreshPermissions()
                    if self.accessibilityTrusted {
                        self.permissionPoll?.invalidate()
                        self.permissionPoll = nil
                    }
                }
            }
        }
    }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in self.refreshPermissions() }
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        if !accessibilityTrusted {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    // MARK: - Session

    func toggleFromUI() {
        switch phase {
        case .recording: finishRecording()
        case .transcribing, .formatting: break
        default:
            hotkeys.beginExternally()
            startRecording(handsFree: true)
        }
    }

    func startRecording(handsFree: Bool) {
        guard !phase.isBusy else { return }
        refreshPermissions()
        guard micAuthorized else {
            requestMicrophone()
            show(.error("Microphone access needed"))
            hotkeys.reset()
            return
        }

        resetWork?.cancel()
        sessionID = UUID()
        chunkTasks.removeAll()
        let front = NSWorkspace.shared.frontmostApplication
        targetApp = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front
        targetAppName = targetApp?.localizedName
        sessionLanguage = prefs.language == "auto" ? nil : prefs.language

        do {
            try recorder.start()
        } catch {
            show(.error(error.localizedDescription))
            hotkeys.reset()
            return
        }
        levels = Array(repeating: 0, count: levels.count)
        startedAt = Date()
        elapsed = 0
        phase = .recording(handsFree: handsFree)
        if prefs.playSounds { NSSound(named: "Tink")?.play() }
        OverlayController.shared.show(controller: self)
        TextFormatter.prewarm(engine: prefs.engine, ollamaModel: prefs.ollamaModel)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let level = levelLock.withLock { () -> Float in
            let v = pendingLevel
            pendingLevel *= 0.55
            return v
        }
        var next = levels
        next.removeFirst()
        next.append(CGFloat(level))
        levels = next
        if let startedAt { elapsed = Date().timeIntervalSince(startedAt) }
        // Transcribe each finished minute in the background while the user keeps talking.
        if let chunk = recorder.takeChunk(seconds: Self.chunkSeconds) {
            enqueueChunk(chunk)
        }
    }

    /// Transcribes chunks strictly in order, one at a time.
    private func enqueueChunk(_ samples: [Float]) {
        let previous = chunkTasks.last
        let language = sessionLanguage
        let task = Task<String, Error> { @MainActor [transcriber] in
            _ = try? await previous?.value
            try await Self.waitForModel(transcriber)
            return try await transcriber.transcribe(samples, language: language)
        }
        chunkTasks.append(task)
    }

    private static func waitForModel(_ transcriber: Transcriber) async throws {
        // The model may still be loading on first launch.
        while transcriber.status != .ready {
            if case .failed(let msg) = transcriber.status { throw MurmurError.formatter(msg) }
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    func cancel() {
        guard case .recording = phase else { return }
        timer?.invalidate()
        _ = recorder.stop()
        chunkTasks.forEach { $0.cancel() }
        chunkTasks.removeAll()
        hotkeys.reset()
        phase = .idle
        OverlayController.shared.hide()
    }

    func finishRecording() {
        guard case .recording = phase else { return }
        timer?.invalidate()
        hotkeys.reset()
        let (samples, peak) = recorder.stop()
        let speechDuration = recorder.stats.kept
        if prefs.playSounds { NSSound(named: "Pop")?.play() }

        // Ignore accidental taps and silence; Whisper hallucinates on empty audio.
        guard speechDuration > 0.4, peak > 0.008 else {
            chunkTasks.forEach { $0.cancel() }
            chunkTasks.removeAll()
            show(.error(speechDuration <= 0.4 ? "Too short" : "No speech detected"))
            return
        }
        if Double(samples.count) / AudioRecorder.sampleRate > 0.3 {
            enqueueChunk(samples)
        }

        phase = .transcribing
        let id = sessionID
        let target = targetApp
        let tasks = chunkTasks
        chunkTasks.removeAll()
        Task {
            await process(chunks: tasks, duration: speechDuration, target: target, id: id)
        }
    }

    private func process(chunks: [Task<String, Error>], duration: TimeInterval,
                         target: NSRunningApplication?, id: UUID) async {
        do {
            var parts: [String] = []
            for chunk in chunks {
                let text = try await chunk.value
                if !text.isEmpty { parts.append(text) }
            }
            let raw = parts.joined(separator: " ")
            guard id == sessionID else { return }
            guard !raw.isEmpty else {
                show(.error("No speech detected"))
                return
            }

            phase = .formatting
            let context = TextFormatter.Context(
                style: prefs.style,
                appName: target?.localizedName,
                bundleID: target?.bundleIdentifier,
                vocabulary: prefs.vocabulary,
                replacements: prefs.replacements
            )
            let output = await TextFormatter.format(raw, engine: prefs.engine, ollamaModel: prefs.ollamaModel, context: context)
            guard id == sessionID else { return }
            let text = output.text.isEmpty ? raw : output.text

            history.add(Dictation(
                date: Date(),
                raw: raw,
                formatted: text,
                appName: target?.localizedName,
                style: TextFormatter.resolvedStyle(context),
                engine: output.engineUsed,
                duration: duration
            ))

            deliver(text, to: target)
        } catch {
            show(.error(error.localizedDescription))
        }
    }

    private func deliver(_ text: String, to target: NSRunningApplication?) {
        refreshPermissions()
        if prefs.autoPaste, accessibilityTrusted, let target, !target.isTerminated {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
                target.activate()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [prefs] in
                Paster.paste(text, restoreClipboard: prefs.restoreClipboard)
            }
            show(.done("Pasted"))
        } else {
            Paster.copy(text)
            show(.done(accessibilityTrusted || !prefs.autoPaste ? "Copied to clipboard" : "Copied — enable Accessibility to auto-paste"))
        }
    }

    private func show(_ phase: Phase) {
        self.phase = phase
        OverlayController.shared.show(controller: self)
        resetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.phase.isBusy else { return }
            self.phase = .idle
            OverlayController.shared.hide()
        }
        resetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (phase == .done("Pasted") ? 1.0 : 2.2), execute: work)
    }

    /// Puts the controller into a given visual state; used by the overlay self-test.
    func preview(phase: Phase, levels: [CGFloat], elapsed: TimeInterval) {
        self.phase = phase
        self.levels = levels
        self.elapsed = elapsed
    }

    /// Re-run formatting on a history item with a different style.
    func reformat(_ item: Dictation, style: FormatStyle) async -> String {
        let context = TextFormatter.Context(style: style, appName: nil, bundleID: nil,
                                            vocabulary: prefs.vocabulary, replacements: prefs.replacements)
        return await TextFormatter.format(item.raw, engine: prefs.engine, ollamaModel: prefs.ollamaModel, context: context).text
    }
}
