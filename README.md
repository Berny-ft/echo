# Echo

A native macOS dictation app in the spirit of Wispr Flow, running 100% on-device and free.
Hold a key, speak naturally, release: Echo transcribes you, cleans up and organizes the text, and pastes it wherever your cursor is.

## How it works

```
hold Right ⌥ ─► mic (AVAudioEngine, 16 kHz) ─► cut pauses > 5 s ─► 1-minute chunks
            ─► Whisper Large v3 Turbo (WhisperKit, Neural Engine), transcribed while you keep talking
            ─► cleanup: fillers, stutters, "no wait, actually…" corrections, "new line"
            ─► LLM formatting (Apple Intelligence on-device model, or Ollama)
            ─► paste with ⌘V into the app you were in (clipboard restored afterwards)
```

- **Speech to text:** OpenAI Whisper via [WhisperKit](https://github.com/argmaxinc/WhisperKit). Large v3 Turbo by default (632 MB, downloaded once to `~/Library/Application Support/Echo`). Small.en and Base.en are also available.
- **Long dictations:** no time limit. Every minute of audio is transcribed in the background while you keep talking (split at the quietest moment, so no word is cut), so stopping only waits for the last partial minute. Silences over 5 s with no audible sound are cut down to short pads before transcription.
- **Formatting:** Apple's on-device foundation model (default), any Ollama model (e.g. `gemma3:4b`), or rules only. LLM output that looks like the model answered the text instead of formatting it is discarded, and Echo falls back to the rule-based cleanup.
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

Permissions: **Microphone** (to hear you) and **Accessibility** (global hotkey and auto-paste). System Settings → Privacy & Security → Accessibility → enable Echo.

## Build

Requires macOS 26+ and Xcode 26.

```bash
./scripts/build_app.sh            # builds build/Echo.app
./scripts/build_app.sh --install  # also copies to /Applications and launches
```

The app is ad-hoc signed, so **macOS forgets the Accessibility grant after each rebuild**. Toggle Echo off and on again in Accessibility settings after reinstalling.

Headless pipeline check, without the mic:

```bash
say -o /tmp/t.aiff "um so we should ship on thursday no wait friday"
build/Echo.app/Contents/MacOS/Echo --selftest /tmp/t.aiff   # transcribe + every formatter
build/Echo.app/Contents/MacOS/Echo --chunktest /tmp/t.aiff  # 2.5 min session with pauses: silence cutting + chunking
build/Echo.app/Contents/MacOS/Echo --overlaytest /tmp/overlay   # renders the recording indicator in every state
```

## Layout

```
Sources/Echo/
  Engine/   AudioRecorder, Transcriber (WhisperKit), TextFormatter (cleanup + LLM), HotkeyMonitor, Paster
  Model/    DictationController (pipeline state machine), Preferences, HistoryStore
  UI/       MainView (Home/History), StyleView, DictionaryView, SettingsView, Onboarding, Overlay indicator
scripts/    build_app.sh, make_icon.swift
```

## Android

A separate native rewrite in [`android/`](android/) (Kotlin + C++), for Pixel 7 and newer (Android 13+, arm64). Everything runs on the phone.

```
tap the floating bubble ─► mic (AudioRecord, 16 kHz) in a foreground service ─► pauses > 1 s trimmed, 25 s chunks
                        ─► Whisper Small.en (whisper.cpp, q5_1) transcribed while you keep talking
                        ─► cleanup: same rules as the Mac app
                        ─► optional on-device formatting with Qwen 2.5 (llama.cpp), instructions pre-processed while you speak
                        ─► typed into the focused field by an accessibility service (or copied if there's no field)
```

- **Bubble:** draggable, snaps to the screen edge, shows only while a text field is focused (configurable). Tap to start, tap to finish, long-press to open Echo.
- **Models** download once inside the app: speech (Base.en 60 MB, Small.en 190 MB, Small multilingual, Large v3 Turbo 574 MB) and formatting (Qwen 2.5 0.5B / 1.5B). With no formatting model, Echo does rule-based cleanup only.
- **Install from an APK:** Android blocks accessibility services for sideloaded apps at first. If it says the setting is restricted, open App info → ⋮ → *Allow restricted settings*, then enable Echo in Accessibility.

Build (needs JDK 21+, Android SDK 36 and NDK 27.2; the native engines are downloaded by CMake):

```bash
cd android
./gradlew assembleRelease   # app/build/outputs/apk/release/app-release.apk
```

Release signing reads `android/keystore.properties` (not committed). Without it, the release APK is built unsigned.

Pipeline check on a device with a WAV file (16 kHz mono):

```bash
adb push t.wav /sdcard/Android/data/com.echo.dictation/files/t.wav
adb shell am start -n com.echo.dictation/.ui.MainActivity --es selftest /sdcard/Android/data/com.echo.dictation/files/t.wav
adb logcat -s EchoSelfTest EchoWhisper EchoLLM
```
