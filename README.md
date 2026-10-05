# Jot

A local macOS dictation and notes app. Native SwiftUI/AppKit, NVIDIA Parakeet Realtime EOU 120M through FluidAudio/Core ML, blue accents, menu-bar recording. No server, account, analytics, or cloud transcription.

## Use

- Globe: tap to start, tap again to finish. Escape cancels.
- Rear/bottom mouse side button: Ctrl–Command–J, toggles dictation.
- Front/top mouse side button: Command–V, paste.
- Notes: create, edit, pin, organize in folders, search, export. Formatting toolbar inserts Markdown.
- Dictation History: recover, copy, save as a note, retry/play retained recordings.
- Settings: actual selected model/mode, microphone, permissions, launch at login, vocabulary, local storage and real benchmarks.

Microphone access is required to record. Accessibility access is required for global shortcuts and insertion into other apps. Enable these for **Jot** in macOS Privacy & Security, then click Refresh in Settings.

Live updates use the target app's Accessibility text interface and stop if focus, selection or contents change. Unsupported fields use a live overlay and final paste when the original focus remains unchanged. Otherwise the transcript stays in History and can be copied manually. No Enter key is sent. Rich-text fields may normalize formatting when their AX value is replaced; use final-only insertion when preserving complex formatting matters.

## Models and measurements

Selected default: `FluidInference/parakeet-ultra-coreml` for final transcription of the original microphone audio, with Apple SpeechAnalyzer / SpeechTranscriber providing local live previews. The small EOU model is not loaded in Ultra mode; legacy 160/320 ms modes remain selectable. Initial download is online; inference is local. Assets are cached under `~/Library/Application Support/Jot/Models`. Chunk duration is not end-to-end latency or a speed claim.

Benchmarks show real audio duration, processing time, realtime multiplier, flush latency, hardware and transcript. WER is computed only with an explicit reference. Model load is excluded. A file benchmark is not a microphone latency test. Actual dictation history separately records stop-to-finish duration.

```
swift test
./build.sh                     # release bundle, Apple Development signature
./build.sh --install           # install and open (quit Jot first)
JOT_ADHOC=1 ./build.sh          # local development fallback without signing key
.build/release/Jot --prepare-model
.build/release/Jot --benchmark Tests/Fixtures/jfk.wav --reference "And so my fellow Americans ask not what your country can do for you ask what you can do for your country"
.build/release/Jot --benchmark Tests/Fixtures/jfk.wav --320
```

Swift 6.2+ and macOS 26+ on Apple Silicon. Dependency revision is pinned in Package.swift and Package.resolved.

## Privacy and storage

Notes, transcripts, spelling rules and measurements: `~/Library/Application Support/Jot/library.json`, atomically saved. Recovery audio: `Recordings/`. Successful audio is deleted by default; failures and cancellations retain audio. Optional successful audio retention is off by default. Export through the UI; backing up this folder backs up the library. No OpenWhispr data is imported or deleted.

## License and attribution

Jot code: MIT (LICENSE). FluidAudio has its own Apache-2.0 license. NVIDIA's model and FluidInference's conversion retain their respective license/model terms, linked from Settings. Model weights are downloaded, not checked into this repo. The `jfk.wav` benchmark fixture comes from https://github.com/ggml-org/whisper.cpp/blob/master/samples/jfk.wav and contains an excerpt of President Kennedy's public inaugural address. It is a short smoke test, not a general accuracy evaluation.
