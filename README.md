# Jot

Talk instead of type, on your Mac. Tap the Globe key (or a shortcut you choose), speak, tap again, and the words land where your cursor is.
Notes, class recordings and call recordings live in the same app. Every model runs on your Mac: no account, no server,
no cloud transcription. SwiftUI and AppKit, macOS 26, Apple Silicon.

From [newi tools](https://newitools.app/jot/).

## Features

- **Dictate into any app**: tap Globe (fn) to start and finish, Esc to cancel. No Globe key, or macOS uses it? Pick a key
  combination (⌃⌥Space) or a lone tap of Right ⌘ / Right ⌥ in Settings › Shortcuts. Words appear live in the text box where
  the app allows it; otherwise Jot pastes when you stop. Everything is kept in **History**, so nothing you say is lost.
- **Models you choose**, downloaded in the app: Parakeet Ultra (most accurate English), Parakeet v3 (25 European
  languages), Parakeet Realtime (fastest streaming), with Apple's on-device speech for live words. Download, cancel,
  switch and delete them on the **Models** page.
- **Notes** with folders, pins, search and Markdown shortcuts. Dictate straight into a note, or save any dictation or
  recording as one.
- **Record Class**: hours of audio saved to disk as it goes (a crash loses at most a moment), with a live transcript and
  re-transcription later with your chosen model.
- **Record Call**: your microphone plus what the Mac plays, so both sides of a FaceTime, Zoom or Meet call are in one
  transcript. Jot shows no consent notice by design; telling the other side you're recording is up to you.
- **Optional cleanup** of fillers and spoken corrections ("Tuesday, I mean Wednesday") with a local model in
  [Ollama](https://ollama.com). The original stays in History; quotes are kept verbatim.
- Hold Space to talk in chosen apps, spelling rules, a floating bubble, Open at Login, and a first-launch walkthrough.

## Screenshots

_Coming soon._ `Jot --ui-preview DIR` renders every page with made-up data.

## Build from source

Needs Xcode 26 or later (Swift 6.2 tools) on macOS 26 and an Apple Silicon Mac.

```sh
git clone <this repo> Jot && cd Jot
swift build && .build/debug/Jot --self-check   # should end with "self-check ok"
swift test                                      # unit tests
./build.sh                                      # makes build/Jot.app
open build/Jot.app
```

Jot uses MacToolsKit from [mac-tools-kit](https://github.com/andrewneuwirth/mac-tools-kit) (SwiftPM fetches it, or uses
a checkout at `../Kit`) and [FluidAudio](https://github.com/FluidInference/FluidAudio) for Parakeet on Core ML, pinned in
`Package.swift`. `build.sh` signs with your Apple Development identity if you have one (a stable signature keeps the
Microphone and Accessibility grants across rebuilds), otherwise ad hoc. To use your own bundle id or signing identity, copy
`config.example.env` to `config.local.env` and edit it.

## Permissions

- **Microphone**: required, to hear you.
- **Accessibility**: for the dictation shortcut and typing into other apps.
- **System audio recording**: only for Record Call; macOS asks the first time.

If tapping Globe opens the emoji picker or Apple's dictation, set System Settings › Keyboard › "Press 🌐 key to" to
**Do Nothing**.

## For other tools

- `Jot --transcribe <file>` prints a raw Parakeet Ultra transcript of an audio file (wav, m4a, mp3, flac, caf, ogg,
  WebM/Opus) and exits; it never downloads and never opens a window.
- `jot://toggle` starts or finishes a dictation. It asks for no confirmation, by design: it can only start or finish a
  dictation, which shows the bubble and goes into History like any other.
- While Jot records it posts the distributed notification `app.newitools.jot.recording` with `userInfo["active"]`
  (a Bool), so a wake-word listener can pause.
- `Jot --prepare-model`, `Jot --benchmark <file> [--reference "<text>"]` for local measurements.

## Privacy

Audio and transcripts never leave your Mac. The only network requests are model downloads from Hugging Face (and macOS
fetching its own speech assets). Full policy: [PRIVACY.md](PRIVACY.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md). Security issues: [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). FluidAudio is Apache-2.0. The Parakeet models (NVIDIA, converted to Core ML by FluidInference) keep their
own licenses, linked from each model card. Model weights are downloaded, never checked in. `Tests/Fixtures/jfk.wav` is a
public-domain excerpt of a 1961 inaugural address, from the [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
samples, used as a short smoke test.
