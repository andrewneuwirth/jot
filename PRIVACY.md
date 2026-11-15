# Jot Privacy Policy

_Last updated: November 2026_

Jot is an open-source dictation, notes and recording app that runs on your Mac. This policy covers the Jot app built from
this repository.

## The short version

Your voice is transcribed on your Mac. No audio or text is sent to the authors or to any transcription service. Jot has no
server, account, analytics, tracking, crash reporting or advertising.

## Audio

- **Dictation**: while you dictate, the microphone audio is written to a recovery file in
  `~/Library/Application Support/Jot/Recordings/`. When the dictation succeeds the file is deleted, unless you turn on
  Settings › "Keep audio of successful dictations". Failed, cancelled and interrupted dictations keep their audio so you
  can retry; delete them from History.
- **Record Class** and **Record Call**: audio is saved continuously to
  `~/Library/Application Support/Jot/Classes/<recording>/` and kept until you delete the recording (it goes to the Trash).
  Record Call also captures what your Mac plays (the other side of a call) through a private Core Audio tap that exists
  only while recording. Recording people may require their consent where you live; tell them.

## Transcription: who receives your audio

Nobody. Speech is turned into text by models running on your Mac:

- **Parakeet** models (NVIDIA, Core ML conversions by FluidInference) through the FluidAudio library, on the Neural Engine.
- **Apple's on-device speech** (SpeechAnalyzer) for live words and class/call transcripts.

## Text

- Transcripts, notes, folders, spelling rules and benchmarks are stored in
  `~/Library/Application Support/Jot/library.json`; class and call transcripts next to their audio.
- **Typing into other apps** uses Accessibility to read the focused text field (to insert at the right place and to stop
  if you change it) and to write your words. When an app doesn't allow that, Jot pastes: the transcript is put on the
  clipboard and stays there.
- **Optional cleanup** sends the finished transcript, as text, to [Ollama](https://ollama.com) at `127.0.0.1:11434` on your
  own Mac. Redirects are refused, so it can't be sent elsewhere. It is off by default.

## Network requests

- **Model downloads**: when you download a model, Jot fetches its files from `huggingface.co`
  (the FluidInference repositories linked on each model card). Nothing about you or your audio is sent.
- **Apple speech assets**: macOS may download its own on-device speech model the first time it's needed.
- Nothing else. Jot does not check for updates or phone home.

## Other local data

- `~/Library/Application Support/Jot/runtime.json`: a small status file (ready/recording, window position, current page)
  rewritten every few seconds, for troubleshooting.
- While recording, Jot posts the distributed notification `app.newitools.jot.recording` (only "active: true/false") that
  other apps on your Mac can observe.
- Settings live in macOS user defaults: `defaults delete app.newitools.Jot` (or your own bundle id) removes them.
- Deleting `~/Library/Application Support/Jot` removes notes, history, recordings and models.

## Changes and contact

Changes to this policy are made in this file and visible in the repository history. Questions: hello@newitools.app or open
an issue.
