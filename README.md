# Murmur

A native macOS dictation app in the spirit of Wispr Flow, running 100% on-device and free.
Hold a key, speak naturally, release: Murmur transcribes you, cleans up and organizes the text, and pastes it wherever your cursor is.

## How it works

```
hold Right ⌥ ─► mic (AVAudioEngine, 16 kHz) ─► Whisper Large v3 Turbo (WhisperKit, Neural Engine)
            ─► cleanup: fillers, stutters, "no wait, actually…" corrections, "new line"
            ─► LLM formatting (Apple Intelligence on-device model, or Ollama)
            ─► paste with ⌘V into the app you were in (clipboard restored afterwards)
```

- **Speech to text:** OpenAI Whisper via [WhisperKit](https://github.com/argmaxinc/WhisperKit). Large v3 Turbo by default (632 MB, downloaded once to `~/Library/Application Support/Murmur`). Small.en and Base.en are also available.
- **Formatting:** Apple's on-device foundation model (default), any Ollama model (e.g. `gemma3:4b`), or rules only. LLM output that looks like the model answered the text instead of formatting it is discarded, and Murmur falls back to the rule-based cleanup.
- **Styles:** Smart (adapts to the target app: Email in Mail, Message in Slack/Messages), Clean, Polished, Notes (bullets), Email, Message.
- **Dictionary:** custom vocabulary plus spoken → written replacements ("my email" → `me@example.com`).
- **History:** every dictation, with the raw transcript, stats (words, WPM, time saved, streak), and "Rewrite as" another style.

## Using it

| Action | What happens |
| --- | --- |
| Hold **Right ⌥** | Push-to-talk. Release to transcribe and paste. |
| Tap **Right ⌥** | Hands-free mode. Tap again (or click ■) to finish. |
| **Esc** | Cancel the recording. |

The key can be changed to Right ⌘, Right ⌃ or fn in Settings.

Permissions: **Microphone** (to hear you) and **Accessibility** (global hotkey and auto-paste). System Settings → Privacy & Security → Accessibility → enable Murmur.

## Build

Requires macOS 26+ and Xcode 26.

```bash
./scripts/build_app.sh            # builds build/Murmur.app
./scripts/build_app.sh --install  # also copies to /Applications and launches
```

The app is ad-hoc signed, so **macOS forgets the Accessibility grant after each rebuild**. Toggle Murmur off and on again in Accessibility settings after reinstalling.

Headless pipeline check, without the mic:

```bash
say -o /tmp/t.aiff "um so we should ship on thursday no wait friday"
build/Murmur.app/Contents/MacOS/Murmur --selftest /tmp/t.aiff
```

## Layout

```
Sources/Murmur/
  Engine/   AudioRecorder, Transcriber (WhisperKit), TextFormatter (cleanup + LLM), HotkeyMonitor, Paster
  Model/    DictationController (pipeline state machine), Preferences, HistoryStore
  UI/       MainView (Home/History), Style & Dictionary, Settings, Onboarding, floating Overlay pill
scripts/    build_app.sh, make_icon.swift
```
