# Jot: notes for agents and contributors

Local dictation, notes, class and call recording for macOS 26 on Apple Silicon. SwiftUI + AppKit, Swift 5 mode.
Dependencies: MacToolsKit (`../Kit` if present, else github.com/andrewneuwirth/mac-tools-kit) and FluidAudio (pinned).

## Check your work

- `swift build && .build/debug/Jot --self-check` (pure logic, CI runs it) and `swift test`.
- `.build/debug/Jot --ui-preview DIR` renders every page and walkthrough step, light and dark, from made-up data in an
  offscreen window. Look at the PNGs after any UI change. Never launch the app or record from a real microphone to test.

## Sources (`Sources/JotCore`)

- `Application.swift`: app delegate, menu-bar item, main window, floating bubble panel, `jot://toggle`.
- `AppModel.swift`: dictation state machine (record → live preview → final transcript → cleanup → insert), `Page`,
  preferences, walkthrough flag (`isNewUser`, `onboarded`).
- `SpeechEngine.swift`: `SpeechMode` (ultra, v3, 160, 320), FluidAudio loading, `Recorder` (mic to .caf + stream),
  `Jot --transcribe`.
- `Models.swift`: `SpeechCatalog` (cards, sizes, folders) and `ModelStore` (download with progress, cancel, size check,
  delete) behind a `ModelBackend` so the self-check uses a fake.
- `ApplePreview.swift`, `PreviewTranscript.swift`: Apple SpeechAnalyzer live text.
- `ClassRecorder.swift`: Record Class / Record Call sessions (`kind`), 15-minute segments, crash recovery.
- `SystemAudioTap.swift`: Core Audio process tap + private aggregate device for calls.
- `TextInsertion.swift`, `SmartPaste.swift`, `Hotkeys.swift`: Accessibility insertion, keyboard tap (the dictation shortcut: Globe, a
  lone modifier tap or a key combination, `DictationShortcut` in defaults key `dictationShortcut`, missing = Globe; Esc;
  Space hold). The shortcut recorder is `ShortcutRecorder` in `SettingsPage.swift`.
- `LocalCleanup.swift`: optional Ollama cleanup with meaning guards. `Library.swift`: notes/history JSON.
- Views: `MainWindow.swift` (root + sidebar), `DictationPage`, `NotesPage`, `RecordingsPage`, `ModelsPage`,
  `SettingsPage`, `Onboarding`, `Overlay` (bubble), shared pieces in `JotUI.swift`, `UIPreview.swift`.
- `Migration.swift`, `SelfCheck.swift`.

## Identity and data

- Bundle id `app.newitools.Jot` (override in gitignored `config.local.env`, see `config.example.env`).
- Distributed notification `app.newitools.jot.recording` (`userInfo["active"]: Bool`); when the build sets
  `PREVIOUS_BUNDLE_ID`, `<previous id>.recording` is posted too until listeners move over.
- URL scheme `jot://toggle`. Aggregate device UID prefix `app.newitools.jot.call.`.
- Data: `~/Library/Application Support/Jot/` (`library.json`, `Recordings/`, `Classes/`, `Models/`, `runtime.json`).
  No Keychain items, no LaunchAgents; Open at Login is `SMAppService.mainApp`.
- Migration: with `PREVIOUS_BUNDLE_ID` set, the old defaults domain is copied once into the new one (never overwriting,
  marked with `migratedFrom`). The Application Support folder name is unchanged, so data carries over.

## Rules

- Audio and transcripts stay on the Mac. No cloud transcription without an explicit, documented opt-in.
- Don't download large models in tests or CI; extend the fake backend instead.
- Don't rewrite working capture or transcription logic to restyle it.
- No real names, paths or emails in code, tests, demo data or docs.
- Intentional, not to-dos: `jot://toggle` runs without a confirmation prompt, and Record Call shows no consent notice.
  Don't add either.
